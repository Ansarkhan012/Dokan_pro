-- Behavioral inventory adjustment security and invariant verification.
begin;

insert into auth.users(id,email) values
 ('a1000000-0000-0000-0000-000000000001','inventory-owner-a@example.test'),
 ('a2000000-0000-0000-0000-000000000002','inventory-owner-b@example.test');
insert into public.shops(id,name,allow_negative_stock) values
 ('aa000000-0000-0000-0000-000000000001','Inventory Shop A',false),
 ('ab000000-0000-0000-0000-000000000002','Inventory Shop B',false);
insert into public.shop_users(shop_id,user_id,role) values
 ('aa000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','owner'),
 ('ab000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
 ('ad000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','Counter A','windowsDesktop','ac000000-0000-0000-0000-000000000001'),
 ('ad000000-0000-0000-0000-000000000002','ab000000-0000-0000-0000-000000000002','Counter B','windowsDesktop','ac000000-0000-0000-0000-000000000002');
insert into public.categories(id,shop_id,name,created_at,updated_at) values
 ('a3000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','Staples A',now(),now()),
 ('a3000000-0000-0000-0000-000000000002','ab000000-0000-0000-0000-000000000002','Staples B',now(),now());
insert into public.shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,created_at,updated_at) values
 ('ae000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','Rice','a3000000-0000-0000-0000-000000000001','kg',10000,12000,now(),now()),
 ('ae000000-0000-0000-0000-000000000002','ab000000-0000-0000-0000-000000000002','Flour','a3000000-0000-0000-0000-000000000002','kg',9000,11000,now(),now());

set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);

do $$
declare
  p jsonb;
  r jsonb;
begin
  p := jsonb_build_object(
    'version',1,
    'operation','sync_inventory_adjustment',
    'movement',jsonb_build_object(
      'id','af000000-0000-0000-0000-000000000001',
      'shop_id','aa000000-0000-0000-0000-000000000001',
      'product_id','ae000000-0000-0000-0000-000000000001',
      'type','openingStock','quantity',5000,
      'reference_type','manual_inventory',
      'reference_id','af000000-0000-0000-0000-000000000011',
      'note','Opening count',
      'created_by','a1000000-0000-0000-0000-000000000001',
      'device_id','ad000000-0000-0000-0000-000000000001',
      'created_at',now()),
    'audit',jsonb_build_object(
      'id','af000000-0000-0000-0000-000000000002',
      'created_at',now(),
      'new_value',jsonb_build_object('quantity',5000)));

  r := public.sync_inventory_adjustment(p,null);
  if r->>'status' <> 'inserted' then
    raise exception 'inventory adjustment insert failed: %',r;
  end if;
  r := public.sync_inventory_adjustment(p,null);
  if r->>'status' <> 'already_synced' then
    raise exception 'inventory adjustment replay was not idempotent: %',r;
  end if;
  if (select count(*) from public.inventory_movements where id='af000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'inventory replay duplicated movement';
  end if;
  if (select count(*) from public.audit_logs where entity_id='af000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'inventory replay duplicated audit';
  end if;

  begin
    perform public.sync_inventory_adjustment(jsonb_set(p,'{movement,quantity}','4000'::jsonb),null);
    raise exception 'conflicting inventory replay succeeded';
  exception when others then
    if sqlerrm='conflicting inventory replay succeeded' then raise; end if;
  end;

  begin
    perform public.sync_inventory_adjustment(
      jsonb_set(
        jsonb_set(
          jsonb_set(p,'{movement,id}','"af000000-0000-0000-0000-000000000003"'),
          '{movement,type}','"damage"'),
        '{movement,quantity}','-6000'::jsonb),null);
    raise exception 'negative-stock adjustment succeeded';
  exception when others then
    if sqlerrm='negative-stock adjustment succeeded' then raise; end if;
  end;

  begin
    perform public.sync_inventory_adjustment(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(p,'{movement,id}','"af000000-0000-0000-0000-000000000004"'),
            '{movement,shop_id}','"ab000000-0000-0000-0000-000000000002"'),
          '{movement,product_id}','"ae000000-0000-0000-0000-000000000002"'),
        '{movement,device_id}','"ad000000-0000-0000-0000-000000000002"'),null);
    raise exception 'cross-shop inventory adjustment succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.inventory_movements(
      id,shop_id,product_id,type,quantity,created_by,created_at
    ) values (
      gen_random_uuid(),'aa000000-0000-0000-0000-000000000001',
      'ae000000-0000-0000-0000-000000000001','manualAdjustment',1,
      'a1000000-0000-0000-0000-000000000001',now());
    raise exception 'direct append to inventory history succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  begin
    perform public.sync_inventory_adjustment('{}',null);
    raise exception 'anonymous inventory adjustment succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

rollback;
