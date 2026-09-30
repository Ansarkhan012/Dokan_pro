begin;

alter table public.shop_products drop constraint if exists shop_products_supported_unit;
alter table public.shop_products add constraint shop_products_supported_unit check (
  unit is null or lower(unit) in
  ('piece','pack','kg','gram','liter','bottle','carton','dozen','bag','unit')
);

create or replace function public.sync_inventory_adjustment(
  p_payload jsonb,
  p_cashier_token text default null
) returns jsonb
language plpgsql security definer
set search_path = public, extensions, pg_temp as $$
declare
  m jsonb := p_payload->'movement';
  a jsonb := p_payload->'audit';
  v_id uuid := (m->>'id')::uuid;
  v_shop uuid := (m->>'shop_id')::uuid;
  v_product uuid := (m->>'product_id')::uuid;
  v_quantity bigint := (m->>'quantity')::bigint;
  v_existing public.inventory_movements%rowtype;
  v_stock bigint;
  v_allow_negative boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended(v_id::text, 0));
  if not public.is_active_owner(v_shop) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if (m->>'created_by')::uuid <> auth.uid() then
    raise exception 'owner actor mismatch' using errcode = '42501';
  end if;
  if m->>'type' not in ('openingStock','manualAdjustment','damage') or v_quantity = 0 then
    raise exception 'invalid inventory adjustment';
  end if;
  if m->>'type' = 'damage' and v_quantity >= 0 then
    raise exception 'damage quantity must reduce stock';
  end if;
  if m->>'type' = 'openingStock' and v_quantity <= 0 then
    raise exception 'opening stock must be positive';
  end if;
  if length(trim(coalesce(m->>'note',''))) = 0 then
    raise exception 'adjustment reason required';
  end if;
  if not exists(select 1 from public.shop_products where id=v_product and shop_id=v_shop) then
    raise exception 'shop product required';
  end if;
  if not exists(select 1 from public.devices where id=(m->>'device_id')::uuid and shop_id=v_shop and is_active) then
    raise exception 'active shop device required' using errcode = '42501';
  end if;

  select * into v_existing from public.inventory_movements where id=v_id;
  if found then
    if v_existing.shop_id<>v_shop or v_existing.product_id<>v_product or
       v_existing.type::text<>(m->>'type') or v_existing.quantity<>v_quantity or
       coalesce(v_existing.note,'')<>coalesce(m->>'note','') then
      raise exception 'conflicting replay for immutable inventory movement';
    end if;
    return jsonb_build_object('movement_id',v_id,'status','already_synced');
  end if;

  select allow_negative_stock into v_allow_negative from public.shops where id=v_shop for update;
  select coalesce(sum(quantity),0) into v_stock from public.inventory_movements
    where shop_id=v_shop and product_id=v_product;
  if not v_allow_negative and v_stock + v_quantity < 0 then
    raise exception 'adjustment would make stock negative';
  end if;

  insert into public.inventory_movements(
    id,shop_id,product_id,type,quantity,reference_type,reference_id,note,created_by,device_id,created_at
  ) values (
    v_id,v_shop,v_product,(m->>'type')::public.inventory_movement_type,v_quantity,
    m->>'reference_type',(m->>'reference_id')::uuid,trim(m->>'note'),auth.uid(),
    (m->>'device_id')::uuid,(m->>'created_at')::timestamptz
  );
  insert into public.audit_logs(id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at)
  values((a->>'id')::uuid,v_shop,auth.uid(),'inventory.adjusted','inventory_movement',v_id,
    a->'new_value',(m->>'device_id')::uuid,(a->>'created_at')::timestamptz);
  return jsonb_build_object('movement_id',v_id,'status','inserted');
end;
$$;

revoke all on function public.sync_inventory_adjustment(jsonb,text) from public, anon, authenticated;
grant execute on function public.sync_inventory_adjustment(jsonb,text) to authenticated;

commit;

