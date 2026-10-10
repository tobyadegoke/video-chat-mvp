# Priority 1 host-presence migration review

Migration: `20261009230000_host_presence_automation.sql`

Branch: `priority-1/host-presence-foundation`

## What it changes

- Adds `host_presence.away_until`.
- Normalizes invalid/null statuses to `offline`, enforces the five supported statuses, and requires `away_until` only for `away`.
- Backfills missing presence rows for existing host profiles. A host without a presence row is not assumed to be online.
- Updates `public.handle_new_user()` without removing referral validation, generated usernames, or host referral attribution. New host registrations get an `offline` presence row.
- Adds `request_host_away(minutes)`, available to authenticated users but limited to their own host account. Default duration is **15 minutes**; allowed range is **1–60 minutes**.
- Adds `request_host_available()` for an explicit host action. The authenticated host can request Available from Offline, Away, or Available; the database rejects a request that would override Busy or Live.
- Adds `set_host_automatic_status(host_id, status)` for trusted backend transitions only (`offline`, `available`, `busy`, `live`).
- Extends `expire_away_hosts()` and its once-per-minute `pg_cron` job so stale Available rows become Offline after two minutes without a heartbeat. Expired Away becomes Live if `profiles.is_live` is true, Available only if the host heartbeat is recent, and Offline otherwise.
- Revokes all direct client-facing table privileges on `host_presence` from `PUBLIC`, `anon`, and `authenticated` (including DELETE, TRUNCATE, TRIGGER, and REFERENCES), then grants authenticated users SELECT and UPDATE of only `last_seen_at`. It also explicitly revokes existing column-level INSERT/UPDATE grants. The existing RLS policy must continue to restrict heartbeat updates to the caller's own row. Status changes should go through the RPCs.
- `request_host_away` only allows Away to be started or renewed from Available/Away; Offline, Busy, and Live are rejected. A host can renew Away immediately while already Away.
- `request_host_available` only changes the caller's own host row, accepts Offline/Away/Available, clears an Away expiry, and rejects Busy/Live. Both host request functions lock the presence row before the profile row to match the automatic transition path.

## Important limitations before applying

0. The host login flow no longer connects to LiveKit automatically. Sign-in now routes to the existing placeholder host screen; an explicit call/broadcast action and presence lifecycle still need to be implemented there.
1. Hosts must explicitly choose Available; sign-in alone does not change status. The host dashboard sends that request through the authenticated database function, which checks role and refuses to override Busy/Live.
2. Busy and Live still require trusted call/broadcast lifecycle events. The repository has no call/broadcast event handlers or tracked LiveKit token Edge Function source, so those transitions are not yet wired.
3. An Available host becomes Offline after the heartbeat is stale for two minutes. A suspended mobile app may stop heartbeats, so an Available host in the background can be marked Offline. Busy/Live are not expired by this rule.
4. Away expiry also depends on a recent `host_presence.last_seen_at` heartbeat. Without one, expiry chooses Offline rather than advertising the host as Available.
5. The guest app's `HostPresenceService` is read-only; its unused status upsert and heartbeat update methods were removed. The repository had no call sites for either method.
6. The migration enables `pg_cron`. The current live-project check reported it is not installed. Check `pg_available_extensions` to confirm it is offered by this project, then verify that the SQL Editor role can enable it and schedule a job. If extension creation or scheduling fails, the transaction should fail; do not remove the scheduler portion and assume expiry is running.
7. The confirmed policy is a 15-minute default Away duration and a one-hour maximum.

## Suggested preflight

Run these read-only checks before applying:

```sql
SELECT count(*) AS hosts_without_presence
FROM public.profiles p
LEFT JOIN public.host_presence hp ON hp.host_id = p.id
WHERE p.role = 'host' AND hp.host_id IS NULL;

SELECT status, count(*)
FROM public.host_presence
GROUP BY status
ORDER BY status;

-- Is pg_cron already installed?
SELECT extname, extversion
FROM pg_catalog.pg_extension
WHERE extname = 'pg_cron';

-- If the query above returns no rows, check whether this project offers it.
SELECT name, default_version, installed_version
FROM pg_catalog.pg_available_extensions
WHERE name = 'pg_cron';
```

## Post-migration verification

```sql
SELECT p.id, p.display_name, p.is_online, p.is_live,
       hp.status, hp.away_until, hp.last_seen_at
FROM public.profiles p
LEFT JOIN public.host_presence hp ON hp.host_id = p.id
WHERE p.role = 'host'
ORDER BY p.created_at;

SELECT jobid, jobname, schedule, command
FROM cron.job
WHERE jobname = 'expire-away-hosts-every-minute';

SELECT routine_name, privilege_type, grantee
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name IN (
    'request_host_away',
    'request_host_available',
    'set_host_automatic_status',
    'expire_away_hosts'
  )
ORDER BY routine_name, grantee, privilege_type;
```

## Rollback guidance

Do not automatically drop `away_until` or the functions after users have started setting Away. A rollback must first disable the cron job, restore the prior app/client write model or deploy a compatible client, reconcile Away rows, and only then reverse schema/function changes deliberately. Take a Supabase backup or create a recovery checkpoint before applying.
