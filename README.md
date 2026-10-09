# Video Chat MVP implementation patch

## Contents
- `database/20261009_host_referral_and_usernames.sql`: schema migration for generated usernames, server-side host referral validation, permanent attribution, profile identity protection, and narrowed client table permissions.
- `apps/guest_app/lib/services/profile_service.dart`: profile updates no longer send a username.
- `apps/guest_app/lib/screens/edit_profile_screen.dart`: username is displayed as read-only; display name and bio remain editable.
- `apps/host_app/lib/screens/host_auth_screen.dart`: host login/signup UI; signup sends account type and referral code, but never assigns a role client-side.

## Apply in this order
1. Back up the Supabase project or create a migration checkpoint.
2. Review and run the SQL in the Supabase SQL Editor as a trusted database administrator.
3. Copy the two Dart files over the matching files in your local repository.
4. Run `flutter analyze` from `apps/guest_app` and test profile read/edit/save.
5. Wire `HostAuthScreen` into the host app startup/router, then run `flutter analyze` from `apps/host_app`.
6. Before host signup is enabled, add active codes to `public.agent_referral_codes` using trusted SQL. `agent_id` is an external agent UUID and does not need to be an app account.

The SQL intentionally preserves existing nonblank usernames; only missing/blank usernames are backfilled. New signups receive generated 8-digit numeric usernames. Guest signups remain guests by default. Host signups must send `account_type: host` and a valid `referral_code` in Auth signup metadata; the database trigger validates the code and records attribution. The client must not send or control `role`.
