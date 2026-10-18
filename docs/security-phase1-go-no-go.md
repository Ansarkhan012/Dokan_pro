# Security Phase 1 — go / no-go (2026-10-15)

**Status: NO-GO until the unverified items below are closed.** Nothing has been
deployed or changed in production. Detailed steps: `docs/security-phase1-rollout.md`.
Preflight query: `docs/security-phase1-preflight.sql` (one read-only SELECT).

> **Superseded order (2026-10-16):** a fourth migration, `202610160001_platform_admin_mfa`
> (admin RPCs and `admin-create-owner` require a verified-TOTP AAL2 session), was
> added after this note. Pending migrations are now **four**: 202610130001,
> 202610140001, 202610150001, 202610160001. Use `docs/security-phase1-deploy-runbook.md`
> for the order and `docs/security-phase1-final-preflight.sql` (covers all four)
> for the preflight. Sign-up is disabled only after the runbook's section D passes,
> with its own approval.

## Compatibility findings (local evidence)

| Item | Finding |
|---|---|
| Key in local APKs (`app-release.apk` 2026-10-13 15:04, `app-debug.apk` 2026-10-13 14:26) | Legacy **anon JWT** (role `anon`, ref `uioaaoacxlslffgmjqio`, expires 2036). No publishable or secret key embedded (only the SDK's prefix literals). |
| Hosted `verify_jwt` (default on; `config.toml` sets nothing) | Owner calls send the user JWT, cashier mode sends the anon JWT, the admin panel sends the admin JWT: all pass the gateway **while legacy JWT API keys are enabled** on the project. A missing token gets 401 from the gateway before the function runs. |
| Old app vs new `issue-entitlement` | Old client treats any non-2xx as an outage (keeps its cached token until grace ends). New client records DPL01/02/03 as a revocation and **blocks billing at once**. |
| Subscription | Billing is blocked when the cached token passes `grace_until` (= `period_end` + 7 days). A shop whose subscription is `expired`, or missing, gets DPL03; a new APK then blocks immediately. |
| Migrations order | 202610130001 (index only, `if not exists`) → 202610140001 (needs 202609200003, 202610070001, 202610080001 already applied) → 202610150001 (needs 140001) → 202610160001 (needs 140001; replaces `is_platform_admin()` and adds `platform_admin_access()`). Each is a single transaction; failure leaves the DB unchanged. 140001 and 150001 are deliberately not re-runnable (plain `create`/`add column`), which is fine because the migration history tracks them. |
| Existing devices | Active → `approved` + `legacy_grandfathered`, kept even above two. **Inactive → `revoked`** (only an admin can re-approve). A device that re-registers with its **same identifier** keeps its status; a **new identifier** (reinstall / cleared data) becomes `pending` if the shop already has a device of that type or two in total. |
| Existing shops | All set `active`. Owners keep access. Self-sign-up and `create_owner_shop` stop working (by design). |

## Confirmed blockers

None in code. The local Edge Function suite (13/13) and the sign-up-disabled probe passed.

## Unverified (each is a STOP until checked)

1. **Production state.** No production credentials are available on this machine; run `security-phase1-preflight.sql`.
2. **Installed tablet build.** The release APK above is a local build. Which build is on Ali_shop's tablet, and which key and signer it has, is unknown. Check Settings → App info and record the version and install date.
3. **Hosted auth configuration.** Dashboard → Settings → API Keys: legacy anon/service_role keys must be **enabled** (the APK and both functions depend on them). Dashboard → Edge Functions: current `issue-entitlement` version and its verify_jwt setting.
4. **Entitlement secrets.** `ENTITLEMENT_PRIVATE_JWK` / `ENTITLEMENT_KEY_ID` must be set and match the public JWK compiled into the installed APK.
5. **Hosted gateway behaviour.** Not testable locally. This is covered by smoke tests 1–2 below.

## Read the preflight output — STOP if any of these are true

- `migrations_applied_latest` lacks `202610080001`, or already contains `202610140001`.
- Any `prerequisites` flag is false: everything `*_absent` / `*_present` / `expected_sig` must be true, `register_shop_device_overloads` = 1, `devices_columns` includes `last_seen_at` and `last_synced_at`, `device_entitlements_columns` has 4 entries.
- `auth_users_triggers` contains anything besides `on_auth_user_created`.
- **Ali_shop:**
  - `entitlement_issuable` is false;
  - `in_offline_grace` is false;
  - `active_owners` = 0;
  - `inactive_will_be_revoked` > 0 for a device still in use;
  - `active_total` ≠ the number of devices physically in use.
- Any operating shop appears in `shops_not_issuable_DPL03` or `shops_past_offline_grace`. Renew it **after** migrating, through `admin_renew_subscription`, before releasing a new APK.

## Backup and recovery prerequisites

1. Fresh `supabase db dump --linked` (schema) and `--data-only` dump, stored off the laptop. Note the latest platform backup or PITR timestamp.
2. Save the current `issue-entitlement` source (`git show HEAD:supabase/functions/issue-entitlement/index.ts`) and the deployed version number.
3. Keep the currently installed APK file, if available, as the tablet rollback.
4. Ali_shop: the sync chip shows **Synced** on every device before you start (no pending queue).
5. Plan a quiet window. The migration takes short locks on `shops`, `devices` and `customer_ledger_entries`.

## Authorized deployment order (each step needs explicit approval)

1. Preflight SQL. Review it against the STOP list.
2. Backups (above).
3. `supabase db push --linked --dry-run`. It must list exactly 202610130001, 202610140001, 202610150001 and 202610160001. Then `supabase db push --linked`.
4. Re-run the preflight. Expect `shops_license_status_absent` = false and Ali_shop unchanged.
5. `supabase functions deploy issue-entitlement`, then `supabase functions deploy admin-create-owner`. Leave verify_jwt on.
6. Bootstrap the platform admin (Auth user + `platform_admins` row + TOTP enrolment in the panel; TOTP must be enabled under Auth → MFA).
7. Smoke tests 1–7.
8. Only then: Dashboard → disable "Allow new users to sign up". Then smoke test 8.
9. New APK to the tablet, separately and later. Not part of this rollout.

## Post-deployment smoke tests

1. Run `curl` against `admin-create-owner` without a token. Expect 401, from the gateway.
2. Sign in to the admin panel with an owner account. Expect it to be refused. Then sign in with the admin account. Expect the shop list to show Ali_shop as `active` with its device count.
3. Ali_shop tablet, online: open the app, make one sale, and sync. Confirm no "not approved" or "not active" banner, and that the entitlement refreshed (owner settings → licence `active`, device `approved`).
4. Cashier login on the tablet. Make one cashier sale and sync it.
5. In the admin panel, create a test shop (it stays `pending`). The audit log shows `shop.created`, `owner.login_created` and `shop.owner_assigned`, with the admin as actor. Then suspend the test shop.
6. Sign in as the test shop's owner. An entitlement request is refused with DPL01.
7. Call `admin_list_shops` with an owner token. Expect 403.
8. After disabling sign-up, these must all still work: an existing owner signs in, a password reset email arrives, and the admin creates a login.

## Rollback

- **Migrations:** forward-only. Rollback means restoring the dump (which loses later writes) or writing a corrective migration. Devices that were made `revoked` need an admin re-approval per device.
- **Functions:** redeploy the saved source. Cashier-mode entitlement refresh then stops working again (it is owner-only in the old function).
- **Sign-up toggle:** reversible instantly, with no effect on data.
- **STOP and roll back the function first** if smoke test 3 or 4 fails on Ali_shop. If DPL01/DPL02 refusals appear for Ali_shop, fix the record through the admin RPCs. Do not restore the database unless data is wrong.
