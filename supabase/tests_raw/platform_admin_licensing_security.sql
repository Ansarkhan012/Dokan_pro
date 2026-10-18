-- Platform administration, licensing and the two-device rule
-- (migration 202610140001) and mandatory admin MFA (202610160001).
-- Executable regression test for an isolated local Supabase database;
-- everything is rolled back. Sessions carry aal2 unless a test says otherwise.
begin;

insert into auth.users(id, email) values
 ('a1000000-0000-0000-0000-0000000000ad','platform-admin@example.test'),
 ('a1000000-0000-0000-0000-0000000000a0','retired-admin@example.test'),
 ('a1000000-0000-0000-0000-00000000000a','legacy-owner@example.test'),
 ('a1000000-0000-0000-0000-00000000000b','new-owner@example.test'),
 ('a1000000-0000-0000-0000-0000000000ee','admin@dokanpro.example.test');
insert into dukaan_private.platform_admins(user_id, is_active) values
 ('a1000000-0000-0000-0000-0000000000ad', true),
 ('a1000000-0000-0000-0000-0000000000a0', false);

-- A legacy shop, created before licensing, with three devices (one inactive)
-- inserted directly: it must keep working exactly as before.
insert into public.shops(id,name) values ('a5000000-0000-0000-0000-00000000000a','Legacy A');
insert into public.shop_users(shop_id,user_id,role) values
 ('a5000000-0000-0000-0000-00000000000a','a1000000-0000-0000-0000-00000000000a','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier,is_active) values
 ('ad000000-0000-0000-0000-0000000000a1','a5000000-0000-0000-0000-00000000000a','Counter','androidTablet','ae000000-0000-0000-0000-0000000000a1',true),
 ('ad000000-0000-0000-0000-0000000000a2','a5000000-0000-0000-0000-00000000000a','Back','windowsDesktop','ae000000-0000-0000-0000-0000000000a2',true),
 ('ad000000-0000-0000-0000-0000000000a3','a5000000-0000-0000-0000-00000000000a','Phone','mobile','ae000000-0000-0000-0000-0000000000a3',true);

create function pg_temp.expect_state(p_sql text, p_state text, p_label text) returns void language plpgsql as $$
declare v_state text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state <> p_state then
      raise exception '%: expected SQLSTATE %, got % (%)', p_label, p_state, v_state, sqlerrm;
    end if;
    return;
  end;
  raise exception '%: expected SQLSTATE %, but it succeeded', p_label, p_state;
end $$;
create function pg_temp.as_user(p_user uuid, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true),
         set_config('request.jwt.claims',
           case when p_user is null then '' else
             jsonb_strip_nulls(jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal))::text end, true),
         set_config('request.headers', '{}', true);
$$;
create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'assertion failed: %', p_label; end if;
end $$;
create table pg_temp.ids(k text primary key, v uuid);
grant all on pg_temp.ids to anon, authenticated;

-- Existing data is preserved: legacy devices approved, licence active.
select pg_temp.check((select license_status from public.shops where id='a5000000-0000-0000-0000-00000000000a') = 'active', 'legacy shop active');
select pg_temp.check((select count(*) from public.devices where shop_id='a5000000-0000-0000-0000-00000000000a' and approval_status='approved' and is_active) = 3, 'legacy devices kept');
select pg_temp.check((select form_factor from public.devices where id='ad000000-0000-0000-0000-0000000000a3') = 'mobile', 'legacy mobile classified');

-- ANON: no shop creation of any kind.
set local role anon;
select pg_temp.as_user(null);
select pg_temp.expect_state($$select public.create_owner_shop('Rogue')$$,'42501','anon create_owner_shop');
select pg_temp.expect_state($$select public.admin_create_shop('Rogue','','','')$$,'42501','anon admin_create_shop');
select pg_temp.expect_state($$insert into public.shops(name) values('Rogue')$$,'42501','anon insert shop');
select pg_temp.expect_state($$select public.is_platform_admin()$$,'42501','anon is_platform_admin');
reset role;

-- OWNER (legacy shop): cannot self-provision, cannot act as admin, and an
-- admin-looking email is not admin.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000a');
select pg_temp.check(not public.is_platform_admin(), 'owner is not admin');
select pg_temp.expect_state($$select public.create_owner_shop('Second shop')$$,'42501','owner create_owner_shop');
select pg_temp.expect_state($$select public.admin_create_shop('Second shop','','','legacy-owner@example.test')$$,'42501','owner admin_create_shop');
select pg_temp.expect_state($$insert into public.shops(name) values('Second shop')$$,'42501','owner insert shop');
select pg_temp.expect_state($$insert into public.shop_users(shop_id,user_id,role) values('a5000000-0000-0000-0000-00000000000a',auth.uid(),'owner')$$,'42501','owner insert membership');
select pg_temp.expect_state($$select public.admin_set_shop_status('a5000000-0000-0000-0000-00000000000a','active','')$$,'42501','owner activate');
select pg_temp.expect_state($$select public.admin_renew_subscription('a5000000-0000-0000-0000-00000000000a','pro_annual',12)$$,'42501','owner renew');
select pg_temp.expect_state($$select public.admin_list_shops()$$,'42501','owner list shops');
select pg_temp.expect_state($$select public.admin_list_audit(null,10)$$,'42501','owner audit');
select pg_temp.expect_state($$insert into dukaan_private.platform_admins(user_id) values(auth.uid())$$,'42501','owner self-promotes');
select pg_temp.expect_state($$update public.shops set license_status='active'$$,'42501','owner edits licence');
select pg_temp.expect_state($$update public.shop_subscriptions set period_end=now()+interval '10 years'$$,'42501','owner edits subscription');
select pg_temp.expect_state($$update public.devices set approval_status='approved'$$,'42501','owner edits approval');
select pg_temp.expect_state($$update public.devices set form_factor='mobile'$$,'42501','owner edits form factor');
-- The legacy owner still gets entitlements and can still rename a device.
select public.entitlement_claims('a5000000-0000-0000-0000-00000000000a','ad000000-0000-0000-0000-0000000000a1');
update public.devices set device_name='Counter 1' where id='ad000000-0000-0000-0000-0000000000a1';
-- Grandfathered over the limit: a further device waits for an admin.
select pg_temp.check((select approval_status from public.register_shop_device('a5000000-0000-0000-0000-00000000000a','Extra','androidTablet','ae000000-0000-0000-0000-0000000000a9')) = 'pending', 'legacy shop over limit pends');
-- Re-registering a known device keeps it approved and its classification.
select pg_temp.check((select approval_status || '/' || form_factor from public.register_shop_device('a5000000-0000-0000-0000-00000000000a','Phone','androidTablet','ae000000-0000-0000-0000-0000000000a3')) = 'approved/mobile', 'relabel keeps mobile');
reset role;

-- Non-admin users with admin-like email or a retired admin row.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ee');
select pg_temp.check(not public.is_platform_admin(), 'email is not a role');
select pg_temp.expect_state($$select public.admin_list_shops()$$,'42501','admin-looking email');
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000a0');
select pg_temp.expect_state($$select public.admin_create_shop('X','','','')$$,'42501','retired admin');
reset role;

-- CASHIER: device credential of the legacy counter cannot provision anything.
insert into dukaan_private.device_credentials(device_id, shop_id, credential_hash)
values ('ad000000-0000-0000-0000-0000000000a1','a5000000-0000-0000-0000-00000000000a',
        extensions.digest(convert_to(repeat('ab',32),'UTF8'),'sha256'));
set local role anon;
select pg_temp.as_user(null);
select set_config('request.headers', json_build_object('x-dukaan-device','ad000000-0000-0000-0000-0000000000a1.' || repeat('ab',32))::text, true);
select pg_temp.expect_state($$select public.admin_set_shop_status('a5000000-0000-0000-0000-00000000000a','active','')$$,'42501','cashier activates');
select pg_temp.expect_state($$select public.admin_approve_device('ad000000-0000-0000-0000-0000000000a1',null,null)$$,'42501','cashier approves');
select pg_temp.expect_state($$select public.register_shop_device('a5000000-0000-0000-0000-00000000000a','X','androidTablet',gen_random_uuid())$$,'42501','cashier registers');
-- Its own claims only.
select public.entitlement_claims('a5000000-0000-0000-0000-00000000000a','ad000000-0000-0000-0000-0000000000a1');
select pg_temp.expect_state($$select public.entitlement_claims('a5000000-0000-0000-0000-00000000000a','ad000000-0000-0000-0000-0000000000a2')$$,'42501','cashier reads other device claims');
reset role;

-- PLATFORM ADMIN provisions a new shop for a new owner.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select pg_temp.check(public.is_platform_admin(), 'admin recognised');
insert into pg_temp.ids values ('shop', public.admin_create_shop('Karachi Kiryana','03001234567','Saddar','NEW-OWNER@example.test'));
select pg_temp.expect_state($$select public.admin_create_shop('  ','','','')$$,'22023','blank shop name');
select pg_temp.expect_state($$select public.admin_assign_owner((select v from pg_temp.ids where k='shop'),'nobody@example.test')$$,'P0002','unknown owner email');
select pg_temp.check((select count(*) from public.shops where id=(select v from pg_temp.ids where k='shop')) = 0, 'admin has no tenant row access');
select pg_temp.check((select e->>'license_status' from jsonb_array_elements(public.admin_list_shops()) e where e->>'id' = (select v from pg_temp.ids where k='shop')::text) = 'pending', 'new shop pending');
select pg_temp.check(jsonb_array_length(public.admin_list_shops()) >= 2, 'admin lists shops');
reset role;

-- MFA: a listed admin with a password-only (aal1) or claim-less session is
-- refused by every admin operation; an owner at aal2 is still not an admin.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad', 'aal1');
select pg_temp.check(not public.is_platform_admin(), 'aal1 admin not recognised');
select pg_temp.check(public.platform_admin_access() = 'mfa_required', 'aal1 admin told to verify MFA');
select pg_temp.expect_state($$select public.admin_list_shops()$$,'42501','aal1 list shops');
select pg_temp.expect_state($$select public.admin_create_shop('MFA','','','')$$,'42501','aal1 create shop');
select pg_temp.expect_state($$select public.admin_assign_owner((select v from pg_temp.ids where k='shop'),'new-owner@example.test')$$,'42501','aal1 assign owner');
select pg_temp.expect_state($$select public.admin_set_shop_status((select v from pg_temp.ids where k='shop'),'active','')$$,'42501','aal1 activate');
select pg_temp.expect_state($$select public.admin_renew_subscription((select v from pg_temp.ids where k='shop'),'pro_monthly',1)$$,'42501','aal1 renew');
select pg_temp.expect_state($$select public.admin_approve_device('ad000000-0000-0000-0000-0000000000a1',null,null)$$,'42501','aal1 approve');
select pg_temp.expect_state($$select public.admin_revoke_device('ad000000-0000-0000-0000-0000000000a1','')$$,'42501','aal1 revoke');
select pg_temp.expect_state($$select public.admin_reject_device('ad000000-0000-0000-0000-0000000000a1','')$$,'42501','aal1 reject');
select pg_temp.expect_state($$select public.admin_set_device_form_factor('ad000000-0000-0000-0000-0000000000a1','mobile')$$,'42501','aal1 reclassify');
select pg_temp.expect_state($$select public.admin_list_audit(null,10)$$,'42501','aal1 audit');
select pg_temp.expect_state($$select public.admin_record_owner_login_created('a1000000-0000-0000-0000-00000000000b')$$,'42501','aal1 audit owner login');
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad', null);
select pg_temp.check(not public.is_platform_admin(), 'no aal claim not recognised');
select pg_temp.expect_state($$select public.admin_list_shops()$$,'42501','no aal list shops');
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad', 'AAL2');
select pg_temp.check(not public.is_platform_admin(), 'aal claim is exact');
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000a', 'aal2');
select pg_temp.check(public.platform_admin_access() = 'none', 'owner with MFA is not an admin');
select pg_temp.expect_state($$select public.admin_list_shops()$$,'42501','owner aal2 list shops');
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000a0', 'aal2');
select pg_temp.check(public.platform_admin_access() = 'none', 'retired admin with MFA');
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad', 'aal2');
select pg_temp.check(public.platform_admin_access() = 'granted', 'aal2 admin granted');
reset role;
-- Nothing above changed the device it targeted.
select pg_temp.check((select approval_status || '/' || form_factor from public.devices where id='ad000000-0000-0000-0000-0000000000a1') = 'approved/tablet', 'aal1 attempts changed nothing');

-- New owner sees the shop, may register devices, but no entitlement until active.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000b');
select pg_temp.check((select count(*) from public.shop_users where shop_id=(select v from pg_temp.ids where k='shop') and role='owner') = 1, 'owner assigned');
insert into pg_temp.ids select 'tab1', device_id from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Counter tablet','androidTablet','af000000-0000-0000-0000-000000000001');
select pg_temp.expect_state($$select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab1'))$$,'42501','pending shop entitlement');
select pg_temp.check((public.owner_activation_status((select v from pg_temp.ids where k='shop'),'af000000-0000-0000-0000-000000000001')->>'license_status') = 'pending', 'owner sees pending');
-- Cross-shop: the new owner sees nothing of the legacy shop.
select pg_temp.check((select count(*) from public.devices where shop_id='a5000000-0000-0000-0000-00000000000a') = 0, 'cross-shop devices hidden');
select pg_temp.check((select count(*) from public.shops where id='a5000000-0000-0000-0000-00000000000a') = 0, 'cross-shop shop hidden');
select pg_temp.check((select count(*) from public.shop_subscriptions where shop_id='a5000000-0000-0000-0000-00000000000a') = 0, 'cross-shop subscription hidden');
select pg_temp.expect_state($$select public.owner_activation_status('a5000000-0000-0000-0000-00000000000a',gen_random_uuid())$$,'42501','cross-shop status');
select pg_temp.expect_state($$select public.register_shop_device('a5000000-0000-0000-0000-00000000000a','X','mobile',gen_random_uuid())$$,'42501','cross-shop register');
select pg_temp.expect_state($$select public.entitlement_claims('a5000000-0000-0000-0000-00000000000a','ad000000-0000-0000-0000-0000000000a1')$$,'42501','cross-shop claims');
reset role;

-- Admin activates and renews.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select public.admin_set_shop_status((select v from pg_temp.ids where k='shop'),'active','Paid cash');
select public.admin_renew_subscription((select v from pg_temp.ids where k='shop'),'pro_monthly',1);
reset role;
select pg_temp.check((select period_end from public.shop_subscriptions where shop_id=(select v from pg_temp.ids where k='shop')) > now() + interval '27 days', 'renewed one month');
select pg_temp.check((select status::text from public.shop_subscriptions where shop_id=(select v from pg_temp.ids where k='shop')) = 'active', 'subscription active');
create temp table first_end as select period_end from public.shop_subscriptions where shop_id=(select v from pg_temp.ids where k='shop');
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select public.admin_renew_subscription((select v from pg_temp.ids where k='shop'),'pro_monthly',1);
reset role;
select pg_temp.check((select period_end from public.shop_subscriptions where shop_id=(select v from pg_temp.ids where k='shop')) >= (select period_end from first_end) + interval '28 days', 'renewal is additive');
select pg_temp.check((select grace_until - period_end from public.shop_subscriptions where shop_id=(select v from pg_temp.ids where k='shop')) = interval '7 days', 'grace follows plan');
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select pg_temp.expect_state($$select public.admin_renew_subscription((select v from pg_temp.ids where k='shop'),'trial',1)$$,'22023','renew onto trial');
select pg_temp.expect_state($$select public.admin_renew_subscription((select v from pg_temp.ids where k='shop'),'pro_monthly',0)$$,'22023','renew zero months');
reset role;

-- Two-device rule, as the owner.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000b');
select pg_temp.check((select (payload->>'plan_id') from (select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab1')) payload) x) = 'pro_monthly', 'first tablet entitled');
select public.issue_device_credential((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab1'));
insert into pg_temp.ids select 'mob1', device_id from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Owner phone','mobile','af000000-0000-0000-0000-000000000002');
select pg_temp.check((select approval_status from public.devices where id=(select v from pg_temp.ids where k='mob1')) = 'approved', 'first mobile approved');
select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='mob1'));
insert into pg_temp.ids select 'tab2', device_id from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Second tablet','androidTablet','af000000-0000-0000-0000-000000000003');
insert into pg_temp.ids select 'mob2', device_id from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Second phone','mobile','af000000-0000-0000-0000-000000000004');
insert into pg_temp.ids select 'win3', device_id from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Third device','windowsDesktop','af000000-0000-0000-0000-000000000005');
select pg_temp.check((select bool_and(approval_status='pending' and not is_active) from public.devices where id in (select v from pg_temp.ids where k in ('tab2','mob2','win3'))), 'second tablet, second mobile and third device pending');
select pg_temp.check((select count(*) from public.devices where shop_id=(select v from pg_temp.ids where k='shop') and approval_status='approved') = 2, 'two approved devices only');
select pg_temp.expect_state($$select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab2'))$$,'42501','pending tablet entitlement');
select pg_temp.expect_state($$select public.issue_device_credential((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='mob2'))$$,'42501','pending mobile credential');
select pg_temp.expect_state($$update public.devices set is_active=true where id=(select v from pg_temp.ids where k='tab2')$$,'42501','owner activates pending device');
-- Copied local identity: the same identifier never becomes a second slot.
select pg_temp.check((select device_id from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Clone','androidTablet','af000000-0000-0000-0000-000000000001')) = (select v from pg_temp.ids where k='tab1'), 'copied identifier maps to same device');
-- Switching the first tablet off does not free its slot.
update public.devices set is_active=false where id=(select v from pg_temp.ids where k='tab1');
select pg_temp.check((select approval_status from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Sneaky','androidTablet','af000000-0000-0000-0000-000000000006')) = 'pending', 'deactivating does not free a slot');
update public.devices set is_active=true where id=(select v from pg_temp.ids where k='tab1');
-- Unauthorised replacement.
select pg_temp.expect_state($$select public.admin_approve_device((select v from pg_temp.ids where k='tab2'),(select v from pg_temp.ids where k='tab1'),null)$$,'42501','owner self-approves replacement');
reset role;

-- Admin decisions.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select pg_temp.check(jsonb_array_length(public.admin_list_devices((select v from pg_temp.ids where k='shop'))) = 6, 'admin sees devices');
select pg_temp.expect_state($$select public.admin_approve_device((select v from pg_temp.ids where k='tab2'),null,null)$$,'42501','approve over limit');
select pg_temp.expect_state($$select public.admin_approve_device((select v from pg_temp.ids where k='tab2'),'ad000000-0000-0000-0000-0000000000a1',null)$$,'22023','replace with another shop device');
select public.admin_approve_device((select v from pg_temp.ids where k='tab2'),(select v from pg_temp.ids where k='tab1'),null);
reset role;
select pg_temp.check((select approval_status from public.devices where id=(select v from pg_temp.ids where k='tab1')) = 'revoked', 'old tablet revoked');
select pg_temp.check((select approval_status from public.devices where id=(select v from pg_temp.ids where k='tab2')) = 'approved', 'replacement approved');
select pg_temp.check((select count(*) from dukaan_private.device_credentials where device_id=(select v from pg_temp.ids where k='tab1')) = 0, 'old credential removed');
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select public.admin_reject_device((select v from pg_temp.ids where k='mob2'),'Not ours');
select pg_temp.expect_state($$select public.admin_reject_device((select v from pg_temp.ids where k='tab2'),'')$$,'22023','reject approved device');
-- Reclassify: the pending "windows" third device is really a phone, still no slot.
select public.admin_set_device_form_factor((select v from pg_temp.ids where k='win3'),'mobile');
select pg_temp.expect_state($$select public.admin_approve_device((select v from pg_temp.ids where k='win3'),null,null)$$,'42501','third device approve');
reset role;

set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000b');
select pg_temp.expect_state($$select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab1'))$$,'42501','revoked tablet entitlement');
select pg_temp.expect_state($$update public.devices set is_active=true where id=(select v from pg_temp.ids where k='tab1')$$,'42501','owner reactivates revoked');
select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab2'));
select pg_temp.check((select approval_status from public.register_shop_device((select v from pg_temp.ids where k='shop'),'Again','mobile','af000000-0000-0000-0000-000000000004')) = 'rejected', 'rejected stays rejected');
reset role;

-- Suspension and reactivation.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select public.admin_set_shop_status((select v from pg_temp.ids where k='shop'),'suspended','Unpaid');
select pg_temp.expect_state($$select public.admin_set_shop_status((select v from pg_temp.ids where k='shop'),'pending','')$$,'22023','invalid status');
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000b');
select pg_temp.expect_state($$select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab2'))$$,'42501','suspended entitlement');
select pg_temp.expect_state($$select public.issue_device_credential((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab2'))$$,'42501','suspended credential');
select pg_temp.expect_state($$select public.register_shop_device((select v from pg_temp.ids where k='shop'),'X','mobile',gen_random_uuid())$$,'42501','suspended register');
select pg_temp.check((public.owner_activation_status((select v from pg_temp.ids where k='shop'),'af000000-0000-0000-0000-000000000003')->>'license_status') = 'suspended', 'owner sees suspended');
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select public.admin_set_shop_status((select v from pg_temp.ids where k='shop'),'active','Paid');
select pg_temp.as_user('a1000000-0000-0000-0000-00000000000b');
select public.entitlement_claims((select v from pg_temp.ids where k='shop'),(select v from pg_temp.ids where k='tab2'));
reset role;

-- Audit trail.
set local role authenticated;
select pg_temp.as_user('a1000000-0000-0000-0000-0000000000ad');
select pg_temp.check((select count(distinct e->>'action') from jsonb_array_elements(public.admin_list_audit((select v from pg_temp.ids where k='shop'),500)) e
  where e->>'action' in ('shop.created','shop.owner_assigned','shop.activated','shop.suspended','subscription.renewed',
                         'device.activated','device.approval_requested','device.replaced','device.rejected','device.reclassified')) = 10, 'audit covers every action');
reset role;
select pg_temp.check((select count(*) from dukaan_private.platform_audit_log where actor_kind='platform_admin' and actor_user_id='a1000000-0000-0000-0000-0000000000ad') >= 8, 'admin actor recorded');

rollback;
