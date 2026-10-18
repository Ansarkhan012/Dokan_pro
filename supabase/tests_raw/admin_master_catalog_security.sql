-- Global catalog management (migration 202610180002): only a platform admin
-- with an MFA (aal2) session writes master_products, every change is audited,
-- and a row may only point at an uploaded catalog photo. Executable
-- regression test for an isolated local Supabase database; everything is
-- rolled back.
begin;

insert into auth.users(id, email) values
 ('e1000000-0000-0000-0000-0000000000ad','catalog-admin@example.test'),
 ('e1000000-0000-0000-0000-00000000000a','catalog-owner@example.test');
insert into dukaan_private.platform_admins(user_id) values
 ('e1000000-0000-0000-0000-0000000000ad');
insert into public.shops(id,name) values ('e5000000-0000-0000-0000-00000000000a','Catalog A');
insert into public.shop_users(shop_id,user_id,role) values
 ('e5000000-0000-0000-0000-00000000000a','e1000000-0000-0000-0000-00000000000a','owner');
insert into public.categories(id, shop_id, name, is_active, created_at, updated_at) values
 ('e6000000-0000-0000-0000-0000000000c1', null, 'Catalog Global', true, now(), now()),
 ('e6000000-0000-0000-0000-0000000000c2', 'e5000000-0000-0000-0000-00000000000a', 'Shop Only', true, now(), now());
insert into public.master_products(id, barcode, name, brand, default_unit, created_at, updated_at) values
 ('e7000000-0000-0000-0000-000000000001', 'cat-test-0001', 'Existing Soap', '', 'piece', now(), now());

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
             jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text end, true);
$$;
create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'assertion failed: %', p_label; end if;
end $$;

-- Clients never write the table directly.
do $$ begin
  if has_table_privilege('authenticated', 'public.master_products', 'INSERT')
     or has_table_privilege('authenticated', 'public.master_products', 'UPDATE')
     or has_table_privilege('authenticated', 'public.master_products', 'DELETE') then
    raise exception 'authenticated can write master_products directly';
  end if;
  if has_function_privilege('anon', 'public.admin_upsert_master_product(uuid,text,text,text,uuid,text,text,boolean)', 'EXECUTE')
     or has_function_privilege('anon', 'public.admin_set_master_product_image(uuid,text)', 'EXECUTE') then
    raise exception 'anon can execute catalog admin functions';
  end if;
end $$;

-- ANON.
set local role anon;
select pg_temp.as_user(null);
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(null,'Rogue','','rogue-1',null,'piece',null,true)$$,
  '42501','anon upsert');
reset role;

-- OWNER: refused by the function and by the table grants.
set local role authenticated;
select pg_temp.as_user('e1000000-0000-0000-0000-00000000000a');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(null,'Rogue','','rogue-1',null,'piece',null,true)$$,
  '42501','owner creates catalog product');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product('e7000000-0000-0000-0000-000000000001','Renamed','','cat-test-0001',null,'piece',null,true)$$,
  '42501','owner edits catalog product');
select pg_temp.expect_state(
  $$select public.admin_set_master_product_image('e7000000-0000-0000-0000-000000000001',null)$$,
  '42501','owner sets catalog image');
select pg_temp.expect_state(
  $$insert into public.master_products(id,barcode,name,default_unit,created_at,updated_at)
    values (gen_random_uuid(),'rogue-2','Rogue','piece',now(),now())$$,
  '42501','owner inserts master_products');
select pg_temp.expect_state(
  $$update public.master_products set name = 'Rogue' where id = 'e7000000-0000-0000-0000-000000000001'$$,
  '42501','owner updates master_products');

-- ADMIN WITHOUT MFA (aal1): refused everywhere.
select pg_temp.as_user('e1000000-0000-0000-0000-0000000000ad', 'aal1');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(null,'Rogue','','rogue-1',null,'piece',null,true)$$,
  '42501','aal1 admin creates catalog product');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product('e7000000-0000-0000-0000-000000000001','Renamed','','cat-test-0001',null,'piece',null,true)$$,
  '42501','aal1 admin edits catalog product');
select pg_temp.expect_state(
  $$select public.admin_set_master_product_image('e7000000-0000-0000-0000-000000000001',null)$$,
  '42501','aal1 admin sets catalog image');
reset role;
select pg_temp.check((select name from public.master_products where id = 'e7000000-0000-0000-0000-000000000001') = 'Existing Soap',
  'refused callers changed nothing');
select pg_temp.check(not exists(select 1 from public.master_products where barcode like 'rogue-%'),
  'refused callers created nothing');

-- ADMIN with aal2: create, edit, attach a photo; each step is audited.
set local role authenticated;
select pg_temp.as_user('e1000000-0000-0000-0000-0000000000ad');
create temp table created(id uuid);
grant all on created to authenticated;
insert into created
select public.admin_upsert_master_product(null,'  Lemon Max Bar  ','Lemon Max',' cat-test-0002 ',
  'e6000000-0000-0000-0000-0000000000c1','Piece','200 g',true);
select pg_temp.check((select m.name = 'Lemon Max Bar' and m.barcode = 'cat-test-0002' and m.default_unit = 'piece'
                         and m.pack_label = '200 g' and m.is_active and m.created_at is not null
                         and m.category_id = 'e6000000-0000-0000-0000-0000000000c1'
                        from public.master_products m join created c on c.id = m.id), 'admin created product');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(null,'Dup','','cat-test-0001',null,'piece',null,true)$$,
  '23505','duplicate barcode');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(null,'Shop cat','','cat-test-0003','e6000000-0000-0000-0000-0000000000c2','piece',null,true)$$,
  '22023','shop category on catalog product');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(null,'Bad unit','','cat-test-0004',null,'barrel',null,true)$$,
  '22023','unsupported unit');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(null,'   ','','cat-test-0005',null,'piece',null,true)$$,
  '22023','blank name');
select pg_temp.expect_state(
  $$select public.admin_upsert_master_product(gen_random_uuid(),'Ghost','','cat-test-0006',null,'piece',null,true)$$,
  'P0002','edit of missing product');

select public.admin_upsert_master_product('e7000000-0000-0000-0000-000000000001','Existing Soap 100g','Brand',
  'cat-test-0001',null,'piece','',false);
select pg_temp.check((select m.name = 'Existing Soap 100g' and not m.is_active and m.pack_label is null
                        from public.master_products m where m.id = 'e7000000-0000-0000-0000-000000000001'),
  'admin edited and deactivated product');

-- Photo: key must be a catalog hash key that has been uploaded.
select pg_temp.expect_state(
  $$select public.admin_set_master_product_image('e7000000-0000-0000-0000-000000000001','catalog/' || repeat('a',64) || '.jpg')$$,
  'P0002','attach before upload');
select pg_temp.expect_state(
  $$select public.admin_set_master_product_image('e7000000-0000-0000-0000-000000000001','shops/e5000000-0000-0000-0000-00000000000a/' || repeat('a',64) || '.jpg')$$,
  '22023','attach a shop photo key');
insert into storage.objects(bucket_id,name) values ('product-images','catalog/' || repeat('a',64) || '.jpg');
select public.admin_set_master_product_image('e7000000-0000-0000-0000-000000000001','catalog/' || repeat('a',64) || '.jpg');
select pg_temp.check((select default_image_path from public.master_products where id = 'e7000000-0000-0000-0000-000000000001')
  = 'catalog/' || repeat('a',64) || '.jpg', 'admin attached photo');
select public.admin_set_master_product_image('e7000000-0000-0000-0000-000000000001',null);
select pg_temp.check((select default_image_path is null from public.master_products where id = 'e7000000-0000-0000-0000-000000000001'),
  'admin cleared photo');
reset role;

select pg_temp.check((select array_agg(action order by id) from dukaan_private.platform_audit_log
                       where actor_user_id = 'e1000000-0000-0000-0000-0000000000ad')
  = array['catalog.product_created','catalog.product_updated','catalog.image_set','catalog.image_cleared'],
  'catalog changes audited');
select pg_temp.check((select bool_and(actor_kind = 'platform_admin' and details ? 'product_id')
                        from dukaan_private.platform_audit_log
                       where actor_user_id = 'e1000000-0000-0000-0000-0000000000ad'),
  'catalog audit entries name the product');

rollback;
