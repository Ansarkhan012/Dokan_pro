-- Grants for platform administration (migrations 202610140001, 202610160001). Behaviour is
-- covered by tests_raw/platform_admin_licensing_security.sql.
begin;
select plan(20);
select function_privs_are('public','create_owner_shop',array['text','text','text'],'authenticated',array[]::text[],'no self-service shop creation');
select function_privs_are('public','create_owner_shop',array['text','text','text'],'anon',array[]::text[],'no anonymous shop creation');
select function_privs_are('public','admin_create_shop',array['text','text','text','text'],'anon',array[]::text[],'anon cannot create shops');
select function_privs_are('public','admin_set_shop_status',array['uuid','text','text'],'anon',array[]::text[],'anon cannot activate');
select function_privs_are('public','admin_renew_subscription',array['uuid','text','integer'],'anon',array[]::text[],'anon cannot renew');
select function_privs_are('public','admin_approve_device',array['uuid','uuid','text'],'anon',array[]::text[],'anon cannot approve devices');
select function_privs_are('public','admin_list_audit',array['uuid','integer'],'anon',array[]::text[],'anon cannot read audit');
select function_privs_are('public','is_platform_admin',array[]::text[],'anon',array[]::text[],'anon cannot probe admin role');
select function_privs_are('public','platform_admin_access',array[]::text[],'anon',array[]::text[],'anon cannot probe admin access');
select function_privs_are('public','register_shop_device',array['uuid','text','device_type','uuid'],'anon',array[]::text[],'anon cannot register devices');
select function_privs_are('public','owner_activation_status',array['uuid','uuid'],'anon',array[]::text[],'anon cannot read activation');
select ok(not has_schema_privilege('anon','dukaan_private','USAGE'),'anon has no private schema usage');
select ok(not has_schema_privilege('authenticated','dukaan_private','USAGE'),'authenticated has no private schema usage');
select ok(not has_table_privilege('authenticated','dukaan_private.platform_admins','INSERT'),'admins table not client writable');
select ok(not has_table_privilege('authenticated','dukaan_private.platform_audit_log','SELECT'),'audit not directly readable');
select ok(not has_column_privilege('authenticated','public.devices','approval_status','UPDATE'),'approval not client writable');
select ok(not has_column_privilege('authenticated','public.devices','form_factor','UPDATE'),'form factor not client writable');
select ok(not has_column_privilege('authenticated','public.shops','license_status','UPDATE'),'licence not client writable');
select ok(not has_table_privilege('authenticated','public.shops','INSERT'),'shops not client insertable');
select ok(not has_table_privilege('authenticated','public.shop_users','INSERT'),'memberships not client insertable');
select * from finish();
rollback;
