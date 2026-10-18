-- Security Phase 1 — final production preflight. ONE read-only SELECT:
-- no writes, no RPC, no volatile functions. Returns no customer data and no
-- owner email/phone/name; shops by id and shop name only.
--
-- Expected before migrating (2026-10-15): 3 shops; Ali_shop trialing until
-- 2026-10-24 (grace 2026-10-31); 4 active androidTablet registrations, 0
-- inactive; migrations up to 202610080001; none of the new objects present.
-- `ali_devices_fingerprint` hashes Ali_shop's stable device fields: record it
-- now and compare after `db push` (it must not change; the migration only
-- adds columns, which the hash ignores).
with
ali as (
  select s.id, s.name from public.shops s where s.name ilike '%ali%'
),
ali_dev as (
  select d.* from public.devices d join ali on ali.id = d.shop_id
),
checks as (
  select
    (select count(*) from public.shops)                                          as shops,
    (select count(*) from ali)                                                   as ali_matches,
    (select x.status::text from public.shop_subscriptions x join ali on ali.id = x.shop_id) as ali_sub_status,
    (select x.plan_id from public.shop_subscriptions x join ali on ali.id = x.shop_id)      as ali_plan,
    (select x.period_end from public.shop_subscriptions x join ali on ali.id = x.shop_id)   as ali_period_end,
    (select x.grace_until from public.shop_subscriptions x join ali on ali.id = x.shop_id)  as ali_grace_until,
    (select count(*) from ali_dev)                                               as ali_devices_total,
    (select count(*) from ali_dev where is_active)                               as ali_devices_active,
    (select count(*) from ali_dev where is_active and device_type::text = 'androidTablet') as ali_active_tablets,
    (select count(*) from ali_dev where not is_active)                           as ali_devices_inactive,
    (select count(*) from public.shop_users u join ali on ali.id = u.shop_id
      where u.role = 'owner' and u.is_active)                                    as ali_active_owners,
    (select md5(string_agg(d.id::text || '|' || d.is_active || '|' || d.device_type::text || '|'
                           || d.device_identifier::text || '|' || d.created_at::text, ',' order by d.id))
       from ali_dev d)                                                           as ali_devices_fingerprint,
    (select string_agg(left(d.id::text, 8), ' ' order by d.created_at) from ali_dev d) as ali_device_codes,
    (select count(*) from public.devices)                                        as devices_all_shops,
    (select count(*) from public.devices where is_active)                        as devices_active_all_shops,
    (select count(*) from public.devices where not is_active)                    as devices_inactive_all_shops,
    (select count(*) from public.shops s where not exists(select 1 from public.shop_subscriptions x
       where x.shop_id = s.id and x.status::text in ('trialing','active','cancelled'))) as shops_without_issuable_sub,
    (select max(version) from supabase_migrations.schema_migrations)            as latest_applied_migration,
    (select count(*) from supabase_migrations.schema_migrations
      where version in ('202610130001','202610140001','202610150001','202610160001')) as new_migrations_applied,
    to_regclass('dukaan_private.platform_admins') is null                        as platform_admins_absent,
    not exists(select 1 from information_schema.columns where table_schema = 'public'
      and table_name = 'shops' and column_name = 'license_status')               as license_status_absent,
    not exists(select 1 from information_schema.columns where table_schema = 'public'
      and table_name = 'devices' and column_name = 'approval_status')            as approval_status_absent,
    to_regprocedure('public.is_platform_admin()') is null                        as is_platform_admin_absent,
    to_regprocedure('public.platform_admin_access()') is null                    as platform_admin_access_absent,
    to_regprocedure('public.admin_record_owner_login_created(uuid)') is null     as audit_owner_rpc_absent,
    to_regclass('public.customer_ledger_entries_sale') is null                   as ledger_sale_index_absent,
    to_regclass('dukaan_private.device_credentials') is not null                 as device_credentials_present,
    to_regprocedure('dukaan_private.request_device()') is not null               as request_device_present,
    to_regprocedure('public.register_shop_device(uuid,text,public.device_type,uuid)') is not null as register_sig_present,
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'register_shop_device')         as register_overloads,
    to_regprocedure('public.create_owner_shop(text,text,text)') is not null      as create_owner_shop_present,
    exists(select 1 from information_schema.columns where table_schema = 'public'
      and table_name = 'devices' and column_name = 'last_synced_at')             as devices_last_synced_present,
    exists(select 1 from information_schema.columns where table_schema = 'public'
      and table_name = 'shops' and column_name = 'updated_at')                   as shops_updated_at_present,
    (select count(*) from information_schema.columns where table_schema = 'public'
      and table_name = 'device_entitlements' and column_name in ('revoked_at','updated_at')) as entitlement_cols,
    to_regclass('auth.mfa_factors') is not null                                  as auth_mfa_factors_present,
    (select string_agg(tgname, ',' order by tgname) from pg_trigger
      where tgrelid = 'auth.users'::regclass and not tgisinternal)               as auth_users_triggers,
    (select count(*) from public.customer_ledger_entries)                        as ledger_rows
)
select c.*,
  -- Every expectation in one flag; any false item is a STOP.
  jsonb_build_object(
    'three_shops', c.shops = 3,
    'ali_found_once', c.ali_matches = 1,
    'ali_trialing', c.ali_sub_status = 'trialing',
    'ali_period_end_2026_10_24', c.ali_period_end::date = date '2026-10-24',
    'ali_grace_2026_10_31', c.ali_grace_until::date = date '2026-10-31',
    'ali_in_period_now', c.ali_period_end > now(),
    'ali_four_active_tablets', c.ali_devices_total = 4 and c.ali_active_tablets = 4,
    'ali_no_inactive', c.ali_devices_inactive = 0,
    'ali_has_owner', c.ali_active_owners >= 1,
    'no_inactive_devices_anywhere', c.devices_inactive_all_shops = 0,
    'all_shops_issuable', c.shops_without_issuable_sub = 0,
    'remote_at_202610080001', c.latest_applied_migration = '202610080001',
    'none_of_new_applied', c.new_migrations_applied = 0,
    'new_objects_absent', c.platform_admins_absent and c.license_status_absent and c.approval_status_absent
                          and c.is_platform_admin_absent and c.platform_admin_access_absent and c.audit_owner_rpc_absent,
    'prerequisites_present', c.device_credentials_present and c.request_device_present and c.register_sig_present
                          and c.register_overloads = 1 and c.create_owner_shop_present and c.devices_last_synced_present
                          and c.shops_updated_at_present and c.entitlement_cols = 2 and c.auth_mfa_factors_present,
    'auth_trigger_only_expected', c.auth_users_triggers = 'on_auth_user_created'
  ) as expectations
from checks c;
