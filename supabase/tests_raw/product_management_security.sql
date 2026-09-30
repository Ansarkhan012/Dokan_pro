-- Owner product-management RPC, atomic opening stock and isolation regression.
begin;

insert into auth.users(id,email) values
 ('31000000-0000-0000-0000-000000000001','product-owner-a@example.test'),
 ('32000000-0000-0000-0000-000000000002','product-owner-b@example.test');
insert into public.shops(id,name) values
 ('3a000000-0000-0000-0000-000000000001','Product Shop A'),
 ('3b000000-0000-0000-0000-000000000002','Product Shop B');
insert into public.shop_users(shop_id,user_id,role) values
 ('3a000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001','owner'),
 ('3b000000-0000-0000-0000-000000000002','32000000-0000-0000-0000-000000000002','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
 ('3d000000-0000-0000-0000-000000000001','3a000000-0000-0000-0000-000000000001','Counter','windowsDesktop','3e000000-0000-0000-0000-000000000001');
insert into public.categories(id,shop_id,name,is_active,created_at,updated_at) values
 ('3c000000-0000-0000-0000-000000000001',null,'Test Staples',true,now(),now());
insert into public.master_products(id,barcode,name,brand,category_id,default_unit,pack_label,is_active,created_at,updated_at) values
 ('3f000000-0000-0000-0000-000000000001','TEST-PRODUCT-001','Test Rice','Test Brand','3c000000-0000-0000-0000-000000000001','kg','1 kg',true,now(),now());

set local role authenticated;
select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);

do $$
declare result jsonb; existing jsonb;
begin
  result := public.add_master_product_to_shop(
    '3a000000-0000-0000-0000-000000000001','3d000000-0000-0000-0000-000000000001',
    '41000000-0000-0000-0000-000000000001','3f000000-0000-0000-0000-000000000001',
    30000,34000,25000,5000,'42000000-0000-0000-0000-000000000001'
  );
  if result->>'status' <> 'inserted' then raise exception 'master add failed: %',result; end if;
  if (select count(*) from public.inventory_movements where product_id='41000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'opening movement missing';
  end if;
  existing := public.add_master_product_to_shop(
    '3a000000-0000-0000-0000-000000000001','3d000000-0000-0000-0000-000000000001',
    '41000000-0000-0000-0000-000000000002','3f000000-0000-0000-0000-000000000001',
    30000,34000,25000,5000,'42000000-0000-0000-0000-000000000002'
  );
  if existing->>'status' <> 'already_exists' then raise exception 'duplicate master not rejected'; end if;
  if (select count(*) from public.shop_products where shop_id='3a000000-0000-0000-0000-000000000001' and master_product_id='3f000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'duplicate master inserted';
  end if;

  result := public.create_custom_shop_product(
    '3a000000-0000-0000-0000-000000000001','3d000000-0000-0000-0000-000000000001',
    '43000000-0000-0000-0000-000000000001','Local Atta','3c000000-0000-0000-0000-000000000001',
    null,'kg','5 kg',null,65000,72000,12000,3000,'44000000-0000-0000-0000-000000000001'
  );
  if result->>'status' <> 'inserted' then raise exception 'custom product failed'; end if;

  begin
    perform public.add_master_product_to_shop(
      '3b000000-0000-0000-0000-000000000002','3d000000-0000-0000-0000-000000000001',
      gen_random_uuid(),'3f000000-0000-0000-0000-000000000001',0,0,0,0,gen_random_uuid()
    );
    raise exception 'cross-shop product add succeeded';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  begin
    perform public.add_master_product_to_shop(
      '3a000000-0000-0000-0000-000000000001','3d000000-0000-0000-0000-000000000001',
      gen_random_uuid(),'3f000000-0000-0000-0000-000000000001',0,0,0,0,gen_random_uuid()
    );
    raise exception 'anonymous product add succeeded';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
