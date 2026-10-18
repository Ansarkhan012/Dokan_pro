# Security Phase 1 — production rollout checklist

Scope: migrations `202610130001_customer_ledger_sale_index`,
`202610140001_platform_admin_licensing`, `202610150001_audit_owner_login_creation`,
`202610160001_platform_admin_mfa` (added 2026-10-16; order and STOP list in
`docs/security-phase1-deploy-runbook.md`, which supersedes this file);
Edge Functions `issue-entitlement` (updated) and `admin-create-owner` (new);
disabling public Auth sign-up. Nothing below has been run against production.

Local evidence: `tool/edge_functions/run_local.sh` (13/13 pass, 2026-10-15),
`supabase/tests_raw/platform_admin_licensing_security.sql`, and a GoTrue probe
with `GOTRUE_DISABLE_SIGNUP=true` (see "Sign-up disable" below).

## 0. Preparation (no writes)

1. Record the project ref (`uioaaoacxlslffgmjqio`) and confirm you are linked
   to production, not a dev project.
2. Backup: take a fresh logical dump **and** note the latest platform backup /
   PITR point. Store the dump off the laptop.
   ```bash
   supabase db dump --linked -f prod_schema_before_phase1.sql
   ```
   ```bash
   supabase db dump --linked --data-only -f prod_data_before_phase1.sql
   ```
3. Record the deployed function versions (`supabase functions list`) and keep
   the current `issue-entitlement` source (`git show HEAD:supabase/functions/issue-entitlement/index.ts`).
4. Confirm `ENTITLEMENT_PRIVATE_JWK` / `ENTITLEMENT_KEY_ID` secrets exist
   (`supabase secrets list`). Do **not** rotate them: rotating invalidates every
   cached offline entitlement.
5. Confirm which API key the shipped APK uses. Cashier-mode entitlement
   refresh sends `Authorization: Bearer <anon key>`; with `verify_jwt = true`
   (the default, `config.toml` sets nothing) that works only with the legacy
   JWT anon key, not an `sb_publishable_…` key.

## 1. Migration preflight (read-only SQL, SQL editor or `psql` as read-only)

No owner PII is selected.

```sql
-- a. Migration history: which of the four are already applied
select version from supabase_migrations.schema_migrations order by version desc limit 6;

-- b. Shop count and licence-relevant subscription state
select count(*) as shops from public.shops;
select x.status, (x.period_end > now()) as in_period, (x.grace_until > now()) as in_grace, count(*)
  from public.shops s left join public.shop_subscriptions x on x.shop_id = s.id
 group by 1, 2, 3 order by 1;

-- c. Devices per shop (active / inactive / by type)
select s.id as shop_id,
       count(d.id) filter (where d.is_active) as active,
       count(d.id) filter (where not d.is_active) as inactive,
       count(d.id) filter (where d.is_active and d.device_type = 'mobile') as active_mobile,
       count(d.id) filter (where d.is_active and d.device_type <> 'mobile') as active_tablet_like
  from public.shops s left join public.devices d on d.shop_id = s.id
 group by s.id order by active desc;

-- d. Shops above the new limit (kept, grandfathered; new devices go pending)
select d.shop_id, count(*) as active_devices
  from public.devices d where d.is_active group by d.shop_id having count(*) > 2;

-- e. Ali_shop compatibility (no owner columns)
select s.id, s.name, s.created_at, x.plan_id, x.status, x.period_end, x.grace_until,
       (select count(*) from public.devices d where d.shop_id = s.id and d.is_active) as active_devices,
       (select count(*) from public.devices d where d.shop_id = s.id and not d.is_active) as inactive_devices,
       (select count(*) from public.shop_users u where u.shop_id = s.id and u.role = 'owner' and u.is_active) as owners
  from public.shops s left join public.shop_subscriptions x on x.shop_id = s.id
 where s.name ilike '%ali%';

-- f. Rows the new rules will change or refuse
select count(*) as inactive_devices_becoming_revoked from public.devices where not is_active;
select count(*) as shops_without_usable_subscription  -- would get DPL03
  from public.shops s where not exists(select 1 from public.shop_subscriptions x
   where x.shop_id = s.id and x.status in ('trialing','active','cancelled'));

-- g. Name collisions / prerequisites the migration assumes
select to_regclass('dukaan_private.platform_admins') as admins_table,       -- must be null
       to_regprocedure('public.is_platform_admin()') as is_admin_fn,         -- must be null
       to_regclass('dukaan_private.device_credentials') as device_creds,     -- must exist
       to_regprocedure('dukaan_private.request_device()') as request_device; -- must exist
select column_name from information_schema.columns
 where table_schema = 'public' and table_name = 'devices'
   and column_name in ('last_seen_at','last_synced_at','updated_at');    -- first two required
select tgname from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;
```

**Go / no-go:** (g) must match; every shop in (b) that sells today should have a
usable subscription; Ali_shop's active devices in (e) must be the ones in
use — any inactive Ali_shop device becomes `revoked` and only an admin can
re-approve it.

## 2. Apply migrations

```bash
supabase db push --linked --dry-run
```
Check the list is exactly the pending four (130001, 140001, 150001, 160001), then `supabase db push --linked`.
Each migration is one transaction; a failure leaves the database unchanged.

Post-check: rerun (c)/(e) plus
`select approval_status, legacy_grandfathered, count(*) from public.devices group by 1,2;`
and `select license_status, count(*) from public.shops group by 1;` (all `active`).

## 3. Deploy Edge Functions

`issue-entitlement` first (works with old and new APKs), then `admin-create-owner`:
```bash
supabase functions deploy issue-entitlement
```
```bash
supabase functions deploy admin-create-owner
```
Keep `verify_jwt` enabled for both (see 0.5).

## 4. Bootstrap the platform admin

Create the admin login (Dashboard → Authentication → Add user), enable MFA,
then add the row as in `docs/platform-admin.md`. Verify with the admin panel:
sign-in succeeds, shop list loads. Sign in with an owner account: the panel
must refuse it.

## 5. Disable public sign-up

Dashboard → Authentication → Sign In / Providers → turn off "Allow new users
to sign up". Effect (verified on local GoTrue with sign-up disabled):

| Flow | Result |
|---|---|
| Existing owner sign-in | works (200) |
| Existing session / token refresh | works (200), sessions are not revoked |
| Password reset (`resetPasswordForEmail`) | works for existing accounts (200) |
| Admin provisioning (`admin-create-owner`, service-role `admin.createUser`) | works (200) |
| Public `signUp` / OTP for an unknown email | refused (422 `signup_disabled`) |
| Cashier creation (`create_cashier`) | unaffected: cashiers are PIN records, not Auth users |

The app has no sign-up or self-onboarding call left (`create_owner_shop` raises
DPL00 since 202610140001), so no client change is needed.

## 6. Authorization smoke tests (production, harmless)

1. No token → `admin-create-owner` 401; owner token → 403.
2. Owner token → `rpc/admin_list_shops` → 403.
3. Admin: create a test shop (stays `pending`), create its owner login, check
   `admin_list_audit` shows `shop.created`, `owner.login_created`,
   `shop.owner_assigned` with the admin as actor. Leave it pending or suspend it.
4. Owner of an active shop: `issue-entitlement` for its own device → 200 with
   signature; for another shop's device → 403.
5. Cashier device (anon key + `x-dukaan-device`) → 200 for its own device.

## 7. Ali_shop verification

On Ali_shop's devices: open the app online → entitlement refresh succeeds,
owner settings show licence `active` and device `approved`; one sale and one
sync round-trip; cashier login on the tablet still works. In the admin panel
the shop shows its device count with `legacy` flags.

## Rollback limitations

* Migrations are forward-only. Rollback = restore from the backup in step 0
  (loses everything written since) or a new corrective migration. There is no
  down script.
* Inactive devices become `revoked`; restoring them needs `admin_approve_device`
  per device (slot rules apply).
* Removing the licensing would re-open shop self-creation; do not re-grant
  `create_owner_shop` without also re-enabling sign-up deliberately.
* Edge Functions: redeploy the previous source from git; the old
  `issue-entitlement` still works with the new `entitlement_claims` (owner path),
  but cashier-mode refresh needs the new one.
* Sign-up toggle is instantly reversible and has no data effect.
* Old APKs: device registration keeps working; a third device is recorded
  `pending` and appears deactivated in the old app; new-owner self-sign-up and
  shop creation in old APKs fail by design.
