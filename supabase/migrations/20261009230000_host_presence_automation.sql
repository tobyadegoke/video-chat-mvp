-- Priority 1: authoritative host presence and timed Away status.
-- Review before applying. This migration changes database write permissions
-- for host_presence and enables pg_cron to expire Away sessions while the app
-- is closed.
--
-- Status rules:
--   - Hosts may explicitly request Away for 1..60 minutes (default 15).
--   - Available / Busy / Live / Offline are trusted backend transitions.
--   - An expired Away becomes Live if profiles.is_live is true; otherwise it
--     becomes Available only when the host heartbeat is recent (<= 2 minutes),
--     and Offline otherwise.
--   - This migration does not invent call/broadcast tables. Trusted backend
--     code must call set_host_automatic_status() when those activities change.

BEGIN;

ALTER TABLE public.host_presence
  ADD COLUMN IF NOT EXISTS away_until timestamptz;

-- Do not infer that old Away records are still valid: this column did not
-- previously exist, so normalize such records to Offline before constraints.
UPDATE public.host_presence
SET status = 'offline',
    away_until = NULL
WHERE status IS NULL
   OR status NOT IN ('offline', 'available', 'away', 'busy', 'live')
   OR (status = 'away' AND away_until IS NULL);

UPDATE public.host_presence
SET away_until = NULL
WHERE status <> 'away' AND away_until IS NOT NULL;

ALTER TABLE public.host_presence
  ALTER COLUMN status SET DEFAULT 'offline',
  ALTER COLUMN status SET NOT NULL;

DO $constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.host_presence'::regclass
      AND conname = 'host_presence_status_allowed'
  ) THEN
    ALTER TABLE public.host_presence
      ADD CONSTRAINT host_presence_status_allowed
      CHECK (status IN ('offline', 'available', 'away', 'busy', 'live'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.host_presence'::regclass
      AND conname = 'host_presence_away_until_consistent'
  ) THEN
    ALTER TABLE public.host_presence
      ADD CONSTRAINT host_presence_away_until_consistent
      CHECK (
        (status = 'away' AND away_until IS NOT NULL)
        OR
        (status <> 'away' AND away_until IS NULL)
      );
  END IF;
END;
$constraints$;

-- Existing host profiles with no presence row are not assumed to be online.
UPDATE public.profiles p
SET is_online = false,
    updated_at = now()
WHERE p.role = 'host'
  AND p.is_live = false
  AND p.is_online = true
  AND NOT EXISTS (
    SELECT 1 FROM public.host_presence hp WHERE hp.host_id = p.id
  );

-- Backfill every existing host. Preserve an existing is_live=true signal.
INSERT INTO public.host_presence (host_id, status, last_seen_at, updated_at)
SELECT
  p.id,
  CASE WHEN p.is_live THEN 'live' ELSE 'offline' END,
  now(),
  now()
FROM public.profiles p
WHERE p.role = 'host'
ON CONFLICT (host_id) DO NOTHING;

-- Maintain updated_at even for heartbeat-only writes.
CREATE OR REPLACE FUNCTION public.touch_host_presence_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS touch_host_presence_updated_at ON public.host_presence;
CREATE TRIGGER touch_host_presence_updated_at
BEFORE UPDATE ON public.host_presence
FOR EACH ROW
EXECUTE FUNCTION public.touch_host_presence_updated_at();

-- Host-controlled operation: Away is the only status a host can request.
-- Duration is bounded to avoid indefinite or accidentally very long Away.
CREATE OR REPLACE FUNCTION public.request_host_away(
  p_duration_minutes integer DEFAULT 15
)
RETURNS public.host_presence
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_role text;
  v_is_live boolean;
  v_current_status text;
  v_presence public.host_presence;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '28000';
  END IF;

  IF p_duration_minutes IS NULL OR p_duration_minutes < 1 OR p_duration_minutes > 60 THEN
    RAISE EXCEPTION 'Away duration must be between 1 and 60 minutes.'
      USING ERRCODE = '22023';
  END IF;

  -- Read the role first without taking a row lock. Then lock presence before
  -- the profile row, matching the lock order used by automatic transitions and
  -- expiry to reduce deadlock risk.
  SELECT p.role, p.is_live
    INTO v_role, v_is_live
  FROM public.profiles p
  WHERE p.id = v_user_id;

  IF v_role IS DISTINCT FROM 'host' THEN
    RAISE EXCEPTION 'Only host accounts can set Away.'
      USING ERRCODE = '42501';
  END IF;

  SELECT hp.status
    INTO v_current_status
  FROM public.host_presence hp
  WHERE hp.host_id = v_user_id
  FOR UPDATE;

  SELECT p.is_live
    INTO v_is_live
  FROM public.profiles p
  WHERE p.id = v_user_id
  FOR UPDATE;

  IF COALESCE(v_is_live, false) OR v_current_status = 'live' THEN
    RAISE EXCEPTION 'Stop the live broadcast before setting Away.'
      USING ERRCODE = '55000';
  END IF;

  IF v_current_status = 'busy' THEN
    RAISE EXCEPTION 'Finish the active call before setting Away.'
      USING ERRCODE = '55000';
  END IF;

  IF v_current_status IS DISTINCT FROM 'available'
     AND v_current_status IS DISTINCT FROM 'away' THEN
    RAISE EXCEPTION 'Only an available host can set or renew Away.'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO public.host_presence (
    host_id, status, away_until, last_seen_at, updated_at
  )
  VALUES (
    v_user_id, 'away',
    now() + make_interval(mins => p_duration_minutes),
    now(), now()
  )
  ON CONFLICT (host_id) DO UPDATE
  SET status = 'away',
      away_until = EXCLUDED.away_until,
      last_seen_at = now(),
      updated_at = now()
  RETURNING * INTO v_presence;

  UPDATE public.profiles
  SET is_online = true,
      last_seen_at = now(),
      updated_at = now()
  WHERE id = v_user_id;

  RETURN v_presence;
END;
$function$;

-- Trusted automatic transition. A trusted backend must call this after
-- connection, call, broadcast, and disconnect events.
CREATE OR REPLACE FUNCTION public.set_host_automatic_status(
  p_host_id uuid,
  p_status text
)
RETURNS public.host_presence
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_presence public.host_presence;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND session_user <> 'postgres' THEN
    RAISE EXCEPTION 'Trusted server-side operation required.'
      USING ERRCODE = '42501';
  END IF;

  IF p_status IS NULL OR p_status NOT IN ('offline', 'available', 'busy', 'live') THEN
    RAISE EXCEPTION 'Automatic status must be offline, available, busy, or live.'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_host_id AND p.role = 'host'
  ) THEN
    RAISE EXCEPTION 'Host profile not found.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.host_presence (
    host_id, status, away_until, last_seen_at, updated_at
  )
  VALUES (p_host_id, p_status, NULL, now(), now())
  ON CONFLICT (host_id) DO UPDATE
  SET status = EXCLUDED.status,
      away_until = NULL,
      last_seen_at = now(),
      updated_at = now()
  RETURNING * INTO v_presence;

  UPDATE public.profiles
  SET is_online = (p_status <> 'offline'),
      is_live = (p_status = 'live'),
      last_seen_at = now(),
      updated_at = now()
  WHERE id = p_host_id;

  RETURN v_presence;
END;
$function$;

-- Called by the scheduled job. A recent host_presence heartbeat is required
-- before an expired Away can become Available. Otherwise the host goes Offline.
CREATE OR REPLACE FUNCTION public.expire_away_hosts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_updated integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND session_user <> 'postgres' THEN
    RAISE EXCEPTION 'Trusted server-side operation required.'
      USING ERRCODE = '42501';
  END IF;

  WITH expired AS (
    SELECT hp.host_id
    FROM public.host_presence hp
    WHERE hp.status = 'away'
      AND hp.away_until <= now()
    FOR UPDATE SKIP LOCKED
  ),
  changed AS (
    UPDATE public.host_presence hp
    SET status = CASE
          WHEN p.is_live THEN 'live'
          WHEN hp.last_seen_at >= now() - interval '2 minutes' THEN 'available'
          ELSE 'offline'
        END,
        away_until = NULL,
        updated_at = now()
    FROM expired e
    JOIN public.profiles p ON p.id = e.host_id
    WHERE hp.host_id = e.host_id
    RETURNING hp.host_id, hp.status
  )
  UPDATE public.profiles p
  SET is_online = (c.status <> 'offline'),
      is_live = (c.status = 'live'),
      updated_at = now()
  FROM changed c
  WHERE p.id = c.host_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$function$;

-- Preserve read access, but prevent authenticated clients from inserting
-- arbitrary presence rows or setting automatic statuses directly. Heartbeats
-- remain possible on the caller's own row through last_seen_at only.
-- Remove all direct client-facing table privileges, including DELETE,
-- TRUNCATE, TRIGGER, and REFERENCES. RLS is not a substitute for revoking
-- dangerous table-level privileges such as TRUNCATE.
REVOKE ALL PRIVILEGES ON TABLE public.host_presence FROM PUBLIC, anon, authenticated;
-- Also revoke any column-level grants that a prior setup may have left behind;
-- table-level REVOKE alone does not remove column-specific grants.
REVOKE INSERT (
  id, host_id, status, away_until, last_seen_at, updated_at, created_at
) ON TABLE public.host_presence FROM PUBLIC, anon, authenticated;
REVOKE UPDATE (
  id, host_id, status, away_until, updated_at, created_at
) ON TABLE public.host_presence FROM PUBLIC, anon, authenticated;

-- Authenticated users can read presence. The existing row-level UPDATE policy
-- limits the heartbeat update to the host's own row.
GRANT SELECT ON TABLE public.host_presence TO authenticated;
GRANT UPDATE (last_seen_at) ON TABLE public.host_presence TO authenticated;

REVOKE ALL ON FUNCTION public.request_host_away(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_host_away(integer) TO authenticated;

REVOKE ALL ON FUNCTION public.set_host_automatic_status(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_host_automatic_status(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.expire_away_hosts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_away_hosts() TO service_role;

-- Preserve the existing referral validation and identity protections, while
-- ensuring new host profiles receive a presence row initialized as Offline.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_display_name text;
  v_username text;
  v_role text := 'guest';
  v_referral_code text;
  v_agent_id uuid;
BEGIN
  v_display_name := COALESCE(
    NULLIF(pg_catalog.btrim(NEW.raw_user_meta_data ->> 'display_name'), ''),
    'New User'
  );

  IF pg_catalog.lower(COALESCE(NEW.raw_user_meta_data ->> 'account_type', '')) = 'host' THEN
    v_referral_code := pg_catalog.upper(
      pg_catalog.btrim(COALESCE(NEW.raw_user_meta_data ->> 'referral_code', ''))
    );

    IF v_referral_code = '' THEN
      RAISE EXCEPTION 'A referral code is required for host registration.'
        USING ERRCODE = '22023';
    END IF;

    SELECT arc.agent_id
      INTO v_agent_id
      FROM public.agent_referral_codes AS arc
     WHERE arc.code = v_referral_code
       AND arc.is_active = true;

    IF v_agent_id IS NULL THEN
      RAISE EXCEPTION 'The referral code is invalid or inactive.'
        USING ERRCODE = '22023';
    END IF;

    v_role := 'host';
  END IF;

  v_username := public.generate_unique_username();

  INSERT INTO public.profiles (id, username, display_name, role)
  VALUES (NEW.id, v_username, v_display_name, v_role);

  IF v_role = 'host' THEN
    INSERT INTO public.host_referral_attributions (user_id, agent_id, referral_code)
    VALUES (NEW.id, v_agent_id, v_referral_code);

    INSERT INTO public.host_presence (
      host_id, status, away_until, last_seen_at, updated_at
    )
    VALUES (NEW.id, 'offline', NULL, now(), now())
    ON CONFLICT (host_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

-- Ensure a single scheduled expiry job exists. pg_cron is a Supabase-supported
-- extension; if extension creation or scheduling fails, the transaction fails
-- rather than silently leaving Away expiry unscheduled.
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $schedule$
DECLARE
  v_job_id bigint;
BEGIN
  FOR v_job_id IN
    SELECT jobid FROM cron.job
    WHERE jobname = 'expire-away-hosts-every-minute'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'expire-away-hosts-every-minute',
    '* * * * *',
    'SELECT public.expire_away_hosts();'
  );
END;
$schedule$;

COMMIT;

-- Post-migration verification:
-- SELECT p.id, p.display_name, p.is_online, p.is_live, hp.status, hp.away_until
-- FROM public.profiles p LEFT JOIN public.host_presence hp ON hp.host_id = p.id
-- WHERE p.role = 'host' ORDER BY p.created_at;
--
-- SELECT jobid, jobname, schedule, command FROM cron.job
-- WHERE jobname = 'expire-away-hosts-every-minute';
--
-- Do not roll back by dropping away_until or the status functions after hosts
-- have begun using Away. A rollback must first restore the previous app/client
-- write model and deliberately reconcile Away rows.
