# Security Phase 1 — production deployment runbook (for approval)

Project ref `uioaaoacxlslffgmjqio`. Pending migrations, exactly four:
`202610130001_customer_ledger_sale_index`, `202610140001_platform_admin_licensing`,
`202610150001_audit_owner_login_creation`, `202610160001_platform_admin_mfa`
(admin RPCs and `admin-create-owner` require a verified-TOTP, AAL2 session).
Each needs explicit approval.
Supersedes the order in `security-phase1-rollout.md` / `security-phase1-go-no-go.md`.

## A. Pre-checks (Dashboard, read-only)

| # | Check | Where | STOP if |
|---|---|---|---|
| A1 | Legacy API keys enabled | Settings → API Keys → "Legacy API keys" tab | Disabled. Every APK and both functions use the legacy anon JWT |
| A2 | Current functions | Edge Functions list | `issue-entitlement` missing, or its "Verify JWT" off (record the current state either way) |
| A3 | Entitlement secrets present | Edge Functions → Secrets: `ENTITLEMENT_PRIVATE_JWK`, `ENTITLEMENT_KEY_ID` | Either missing. Do **not** rotate |
| A4 | Signing key matches APK | Ali_shop tablet, online, today: no "subscription proof invalid" / "verification required" banner | Banner present (the private key does not match public key fingerprint `d3efaecff570`) |
| A5 | Ali_shop is synced | Tablet sync chip shows **Synced** | Pending or failed uploads |
| A6 | Rerun `docs/security-phase1-preflight.sql` | SQL Editor | Anything changed since the last run (shops, Ali_shop's 4 rows, trial dates, applied migrations) |
| A7 | TOTP MFA enabled | Authentication → Multi-Factor (Sign In / Providers → MFA): "Authenticator app (TOTP)" enrol + verify allowed | Disabled: the first admin could never reach AAL2 |
| A8 | Admin has an authenticator app ready | Phone with Google/Microsoft Authenticator, phone clock automatic | Not available |

## B. Backup (required evidence before C)

Read-only check on 2026-10-15: `supabase backups list` shows **no physical
backups** for this project and **PITR off**. So there is no platform restore
point: a logical dump, proven restorable, is mandatory.

1. Dumps (read-only on production; write to an encrypted folder outside the
   repository, e.g. `C:\Users\ansar\.dukaan\backups\`, never to D:\POS_store):
   ```bash
   npx supabase@2.113.0 db dump --linked -f C:/Users/ansar/.dukaan/backups/prod_roles_2026-10-XX.sql --role-only
   ```
   ```bash
   npx supabase@2.113.0 db dump --linked -f C:/Users/ansar/.dukaan/backups/prod_schema_2026-10-XX.sql
   ```
   ```bash
   npx supabase@2.113.0 db dump --linked -f C:/Users/ansar/.dukaan/backups/prod_data_2026-10-XX.sql --data-only --use-copy
   ```
   Check the data dump also contains `auth.users` and `dukaan_private`
   rows (owner logins, device credentials); if not, repeat it with
   `--schema public,auth,dukaan_private`. The data dump contains customer data: keep it encrypted, never share it,
   delete it once the rollout is accepted and a newer backup exists.
2. Prove it restores: load roles, schema and data into a **local throwaway**
   database (never production), then compare row counts with production
   (`shops` 3, `devices` 4, plus `sales`, `customer_ledger_entries`,
   `shop_subscriptions`). Same `ali_devices_fingerprint` from
   `docs/security-phase1-final-preflight.sql` run on the restored copy.
3. Save the deployed function as the rollback source (read-only download):
   ```bash
   npx supabase@2.113.0 functions download issue-entitlement --project-ref uioaaoacxlslffgmjqio
   ```
   Deployed today: `issue-entitlement` v1, verify_jwt on; `admin-create-owner`
   not deployed. Copy the downloaded folder out of the repo before deploying.

**Evidence required (STOP without it):** dump files with timestamps and
sizes; restore log without errors; row-count and fingerprint match; the
downloaded v1 function source.

Recovery: the migrations are forward-only. If a migration fails, its
transaction rolls back and production is unchanged. If one succeeds but
breaks shops: redeploy the saved v1 function, then a corrective migration.
Restore the dump only for data damage (it loses every sale since the dump).

## C. Deployment commands (in order, one approval each)

Already linked to `uioaaoacxlslffgmjqio` (`supabase/.temp/project-ref`); do not re-link.
```bash
npx supabase@2.113.0 migration list --linked
```
STOP unless the remote column ends at `202610080001` and exactly the four above are local-only.
```bash
npx supabase@2.113.0 db push --linked --dry-run
```
STOP unless it lists exactly those four.
```bash
npx supabase@2.113.0 db push --linked
```
Rerun the preflight query. STOP unless Ali_shop still shows 4 active registrations and the trial ends 2026-10-24.
```bash
npx supabase@2.113.0 functions deploy issue-entitlement --project-ref uioaaoacxlslffgmjqio
```
```bash
npx supabase@2.113.0 functions deploy admin-create-owner --project-ref uioaaoacxlslffgmjqio
```
Verify JWT stays **on** for both (the default).

Platform-admin bootstrap (Dashboard):
1. Authentication → Users → Add user → Create new user, with a dedicated email, a strong unique password and "Auto confirm" ticked.
2. SQL Editor (the only write by hand):
   ```sql
   insert into dukaan_private.platform_admins(user_id, note)
   select id, 'Dokan Pro operator' from auth.users where email = '<admin email>';
   ```
3. Enrol MFA: run the admin panel, sign in with the password. It must show
   *Set up two-step verification* (not the shop list). Add the setup key to
   the authenticator app, enter the 6-digit code. Details and the
   lost-authenticator procedure: `docs/platform-admin.md`.
4. Verify AAL2: the shop list then shows 3 shops. Sign out and in again: it
   asks for a code before any admin page. SQL Editor (read-only):
   `select factor_type, status from auth.mfa_factors f join auth.users u on u.id = f.user_id where u.email = '<admin email>';`
   → `totp | verified`.
5. Verify refusal: an owner account is refused ("not a platform
   administrator"); the admin's password-only session cannot list shops
   (smoke test D11).

Disable public sign-up: **not in this rollout**. Do it only after section D passes and with separate approval (Authentication → Sign In / Providers → turn off "Allow new users to sign up").

## D. Post-deployment verification

Ali_shop's four registrations, its subscription and its devices are observed only, never changed.

| # | Test | Expected | STOP / roll back function if |
|---|---|---|---|
| D1 | Ali_shop owner signs in on the tablet (no reinstall, no clear data) | Opens normally. Owner settings: licence **active**, device **approved** | Any "not approved" / "not active" / pending screen |
| D2 | Cashier login on the tablet, one cashier sale, sync | Login works, sale syncs | Login refused or the sale stuck in sync issues |
| D3 | Valid offline billing: Wi-Fi off, one sale, Wi-Fi on | Sale allowed offline (trial valid until 24 Oct), uploads on reconnect | Billing blocked while offline |
| D4 | Entitlement refreshed | Preflight / `device_entitlements` or activation status shows a refresh for the tablet's row | DPL01/02/03 for Ali_shop |
| D5 | Existing registrations preserved (SQL, read-only) | `select approval_status, legacy_grandfathered, is_active, count(*) from public.devices where shop_id = '<ali id>' group by 1,2,3;` → `approved / true / true / 4` | Any other result |
| D6 | Admin creates a test shop "QA Test Shop" with a new owner login | Shop **pending**. Audit: `shop.created`, `owner.login_created`, `shop.owner_assigned`, actor = admin | Failure, or a missing audit row |
| D7 | Unauthorized shop creation | Ali_shop owner token → `rpc/admin_create_shop` → 403. `rpc/create_owner_shop` → error DPL00. `admin-create-owner` without a token → 401 | Any success |
| D8 | Device approval/replacement (test shop only) | Test owner registers 2 devices (approved), a 3rd is **pending** with a device code. Admin approves with Replace → old one revoked. Audit `device.replaced` | Third auto-approved, or Ali_shop rows touched |
| D9 | Subscription renewal (test shop only) | Activate the test shop, Renew 1 month on a paid plan → `period_end` ≈ +1 month, audit `subscription.renewed` | Error, or renewal applied to another shop |
| D10 | Clean-up | Suspend the test shop (audited). Entitlement for its device → DPL01 | Not refused |
| D11 | Admin MFA enforced | Panel: password sign-in stops at the code screen. REST: get a password-only token for the admin (`/auth/v1/token?grant_type=password`, no code) → `rpc/admin_list_shops` 403, `admin-create-owner` 403, `rpc/platform_admin_access` = `mfa_required`. After entering the code in the panel, the shop list loads | Any admin data before the code |
| D12 | Owner not elevated by MFA | An owner account (even one with an authenticator) → `rpc/platform_admin_access` → `none` | Anything else |

Ali_shop renewal before 24 Oct (grace ends 31 Oct) is a **separate, explicitly approved** admin action after D passes.

## STOP conditions (any of these: halt, do not continue to the next step)

- A1–A8 fail.
- Section B evidence missing: no dump, a restore error, or a row-count /
  `ali_devices_fingerprint` mismatch.
- `docs/security-phase1-final-preflight.sql` has any `expectations` item
  `false`, or `ali_devices_fingerprint` differs from `22184a29933a4189f744fb143cac9626`
  (recorded 2026-10-15) before the push, or differs after it.
- `migration list` / `--dry-run` shows anything but the four pending migrations.
- A7/A8 fail, or the admin cannot complete TOTP enrolment (do not work around
  it: no bypass exists; fix the Auth MFA setting).
- D11/D12 fail: admin data reachable without the code, or an owner granted.
- Any migration error. Production stays unchanged; investigate before retrying.
- After `db push`, Ali_shop is not exactly 4 × approved/legacy/active, or the licence is not `active`.
- D1–D5 fail. Redeploy the saved `issue-entitlement` first; do not revoke or reinstall anything on the tablet.
- Anyone proposes uninstalling the app on the tablet.
