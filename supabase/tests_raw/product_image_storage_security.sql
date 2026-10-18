-- Product photo storage: owners write only their own shop's content-hash
-- keys, only platform admins write catalog photos, nobody overwrites or
-- deletes. Executable regression test for an isolated local Supabase
-- database.
begin;

insert into auth.users(id, email) values
 ('c1000000-0000-0000-0000-00000000000a','images-a@example.test'),
 ('c1000000-0000-0000-0000-00000000000b','images-b@example.test'),
 ('c1000000-0000-0000-0000-0000000000ad','images-admin@example.test');
insert into dukaan_private.platform_admins(user_id) values
 ('c1000000-0000-0000-0000-0000000000ad');
insert into public.shops(id,name) values
 ('c5000000-0000-0000-0000-00000000000a','Images A'),
 ('c5000000-0000-0000-0000-00000000000b','Images B');
insert into public.shop_users(shop_id,user_id,role) values
 ('c5000000-0000-0000-0000-00000000000a','c1000000-0000-0000-0000-00000000000a','owner'),
 ('c5000000-0000-0000-0000-00000000000b','c1000000-0000-0000-0000-00000000000b','owner');

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

do $$ begin
  if not exists(select 1 from storage.buckets where id = 'product-images' and public
                and file_size_limit = 524288 and allowed_mime_types = array['image/jpeg']) then
    raise exception 'product-images bucket is missing or misconfigured';
  end if;
  if public.product_image_shop_id('shops/c5000000-0000-0000-0000-00000000000a/' || repeat('a',64) || '.jpg')
       is distinct from 'c5000000-0000-0000-0000-00000000000a'::uuid
     or public.product_image_shop_id('shops/not-a-uuid/' || repeat('a',64) || '.jpg') is not null
     or public.product_image_shop_id('shops/c5000000-0000-0000-0000-00000000000a/x.jpg') is not null
     or public.product_image_shop_id('catalog/' || repeat('a',64) || '.jpg') is not null then
    raise exception 'product_image_shop_id parses keys wrongly';
  end if;
  -- Insert only: no client may update or delete a stored photo (deletes
  -- go through the Storage API, which applies these policies).
  if exists(select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
            and policyname like 'product_images_%' and cmd <> 'INSERT') then
    raise exception 'product-images allows more than insert';
  end if;
end $$;

-- Owner A: own shop folder only, content-hash JPEG names only.
set local role authenticated;
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000a',true);
insert into storage.objects(bucket_id,name,owner_id)
values ('product-images','shops/c5000000-0000-0000-0000-00000000000a/' || repeat('a',64) || '.jpg',
        'c1000000-0000-0000-0000-00000000000a');
select pg_temp.expect_state(
  $$insert into storage.objects(bucket_id,name) values ('product-images','shops/c5000000-0000-0000-0000-00000000000b/' || repeat('a',64) || '.jpg')$$,
  '42501','owner A writes into shop B');
select pg_temp.expect_state(
  $$insert into storage.objects(bucket_id,name) values ('product-images','shops/c5000000-0000-0000-0000-00000000000a/photo.jpg')$$,
  '42501','owner writes a non-hash name');
select pg_temp.expect_state(
  $$insert into storage.objects(bucket_id,name) values ('product-images','catalog/' || repeat('b',64) || '.jpg')$$,
  '42501','owner writes a catalog photo');
do $$ begin
  update storage.objects set name = name where bucket_id = 'product-images';
  if found then raise exception 'owner overwrote a stored photo'; end if;
end $$;

-- Owner B and anonymous callers cannot write into shop A either.
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-00000000000b',true);
select pg_temp.expect_state(
  $$insert into storage.objects(bucket_id,name) values ('product-images','shops/c5000000-0000-0000-0000-00000000000a/' || repeat('c',64) || '.jpg')$$,
  '42501','owner B writes into shop A');
-- Platform admin with an MFA (aal2) session: catalog photos only.
select set_config('request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-0000000000ad","aal":"aal2"}',true);
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-0000000000ad',true);
insert into storage.objects(bucket_id,name) values ('product-images','catalog/' || repeat('e',64) || '.jpg');
select pg_temp.expect_state(
  $$insert into storage.objects(bucket_id,name) values ('product-images','catalog/logo.jpg')$$,
  '42501','admin writes a non-hash catalog name');
select set_config('request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-0000000000ad","aal":"aal1"}',true);
select pg_temp.expect_state(
  $$insert into storage.objects(bucket_id,name) values ('product-images','catalog/' || repeat('f',64) || '.jpg')$$,
  '42501','admin without MFA writes a catalog photo');
select set_config('request.jwt.claims','',true);

set local role anon;
select pg_temp.expect_state(
  $$insert into storage.objects(bucket_id,name) values ('product-images','shops/c5000000-0000-0000-0000-00000000000a/' || repeat('d',64) || '.jpg')$$,
  '42501','anonymous upload');

rollback;
