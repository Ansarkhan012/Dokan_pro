begin;

alter table public.master_products
  add column pack_label text;

alter table public.shop_products
  add column category_id uuid references public.categories(id),
  add column unit text,
  add column pack_label text,
  add column image_path text,
  add constraint shop_products_low_stock_nonnegative
    check (low_stock_level is null or low_stock_level >= 0),
  add constraint shop_products_custom_fields
    check (
      master_product_id is not null or
      (length(trim(custom_name)) > 0 and category_id is not null and length(trim(unit)) > 0)
    ),
  add constraint shop_products_supported_unit
    check (
      unit is null or lower(unit) in
      ('piece','pack','kg','gram','liter','bottle','carton','dozen','unit')
    );

create unique index shop_products_unique_master
  on public.shop_products(shop_id, master_product_id)
  where master_product_id is not null;

grant update(category_id, unit, pack_label, image_path)
  on table public.shop_products to authenticated;

create or replace function public.add_master_product_to_shop(
  p_shop_id uuid,
  p_device_id uuid,
  p_shop_product_id uuid,
  p_master_product_id uuid,
  p_purchase_price bigint,
  p_sale_price bigint,
  p_opening_quantity bigint,
  p_low_stock_level bigint,
  p_movement_id uuid
) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_existing uuid;
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if p_purchase_price < 0 or p_sale_price < 0 or p_opening_quantity < 0 or p_low_stock_level < 0 then
    raise exception 'prices and quantities must be non-negative';
  end if;
  if not exists(select 1 from public.devices where id=p_device_id and shop_id=p_shop_id and is_active) then
    raise exception 'active shop device required' using errcode = '42501';
  end if;
  if not exists(select 1 from public.master_products where id=p_master_product_id and is_active) then
    raise exception 'active master product required';
  end if;

  select id into v_existing from public.shop_products
    where shop_id=p_shop_id and master_product_id=p_master_product_id;
  if v_existing is not null then
    return jsonb_build_object('product_id', v_existing, 'status', 'already_exists');
  end if;

  insert into public.shop_products(
    id,shop_id,master_product_id,purchase_price,sale_price,
    stock_tracking_enabled,low_stock_level,is_active,created_at,updated_at
  ) values (
    p_shop_product_id,p_shop_id,p_master_product_id,p_purchase_price,p_sale_price,
    true,p_low_stock_level,true,now(),now()
  );
  if p_opening_quantity > 0 then
    insert into public.inventory_movements(
      id,shop_id,product_id,type,quantity,reference_type,note,created_by,device_id,created_at
    ) values (
      p_movement_id,p_shop_id,p_shop_product_id,'openingStock',p_opening_quantity,
      'product_setup','Opening stock',auth.uid(),p_device_id,now()
    ) on conflict(id) do nothing;
  end if;
  insert into public.audit_logs(
    id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at
  ) values (
    gen_random_uuid(),p_shop_id,auth.uid(),'product.added','shop_product',p_shop_product_id,
    jsonb_build_object('master_product_id',p_master_product_id),p_device_id,now()
  );
  return jsonb_build_object('product_id', p_shop_product_id, 'status', 'inserted');
end; $$;

create or replace function public.create_custom_shop_product(
  p_shop_id uuid,
  p_device_id uuid,
  p_shop_product_id uuid,
  p_name text,
  p_category_id uuid,
  p_barcode text,
  p_unit text,
  p_pack_label text,
  p_image_path text,
  p_purchase_price bigint,
  p_sale_price bigint,
  p_opening_quantity bigint,
  p_low_stock_level bigint,
  p_movement_id uuid
) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if length(trim(p_name)) = 0 then raise exception 'product name required'; end if;
  if lower(trim(p_unit)) not in ('piece','pack','kg','gram','liter','bottle','carton','dozen','unit') then
    raise exception 'unsupported unit';
  end if;
  if p_purchase_price < 0 or p_sale_price < 0 or p_opening_quantity < 0 or p_low_stock_level < 0 then
    raise exception 'prices and quantities must be non-negative';
  end if;
  if not exists(select 1 from public.devices where id=p_device_id and shop_id=p_shop_id and is_active) then
    raise exception 'active shop device required' using errcode = '42501';
  end if;
  if not exists(
    select 1 from public.categories
    where id=p_category_id and is_active and (shop_id is null or shop_id=p_shop_id)
  ) then raise exception 'active category required'; end if;

  if exists(select 1 from public.shop_products where id=p_shop_product_id and shop_id=p_shop_id) then
    return jsonb_build_object('product_id',p_shop_product_id,'status','already_exists');
  end if;
  if nullif(trim(coalesce(p_barcode,'')),'') is not null and exists(
    select 1 from public.shop_products where shop_id=p_shop_id and barcode=trim(p_barcode)
  ) then raise exception 'barcode already exists in shop'; end if;

  insert into public.shop_products(
    id,shop_id,custom_name,barcode,category_id,unit,pack_label,image_path,
    purchase_price,sale_price,stock_tracking_enabled,low_stock_level,is_active,created_at,updated_at
  ) values (
    p_shop_product_id,p_shop_id,trim(p_name),nullif(trim(coalesce(p_barcode,'')),''),
    p_category_id,lower(trim(p_unit)),nullif(trim(coalesce(p_pack_label,'')),''),
    nullif(trim(coalesce(p_image_path,'')),''),p_purchase_price,p_sale_price,true,
    p_low_stock_level,true,now(),now()
  );
  if p_opening_quantity > 0 then
    insert into public.inventory_movements(
      id,shop_id,product_id,type,quantity,reference_type,note,created_by,device_id,created_at
    ) values (
      p_movement_id,p_shop_id,p_shop_product_id,'openingStock',p_opening_quantity,
      'product_setup','Opening stock',auth.uid(),p_device_id,now()
    ) on conflict(id) do nothing;
  end if;
  insert into public.audit_logs(
    id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at
  ) values (
    gen_random_uuid(),p_shop_id,auth.uid(),'product.custom_created','shop_product',p_shop_product_id,
    jsonb_build_object('name',trim(p_name)),p_device_id,now()
  );
  return jsonb_build_object('product_id',p_shop_product_id,'status','inserted');
end; $$;

revoke all on function public.add_master_product_to_shop(uuid,uuid,uuid,uuid,bigint,bigint,bigint,bigint,uuid) from public;
grant execute on function public.add_master_product_to_shop(uuid,uuid,uuid,uuid,bigint,bigint,bigint,bigint,uuid) to authenticated;
revoke all on function public.create_custom_shop_product(uuid,uuid,uuid,text,uuid,text,text,text,text,bigint,bigint,bigint,bigint,uuid) from public;
grant execute on function public.create_custom_shop_product(uuid,uuid,uuid,text,uuid,text,text,text,text,bigint,bigint,bigint,bigint,uuid) to authenticated;

commit;
