begin;

create unique index sale_items_id_shop_unique on public.sale_items(id,shop_id);

create table public.sale_returns(
  id uuid primary key,
  shop_id uuid not null references public.shops(id),
  original_sale_id uuid not null,
  customer_id uuid,
  device_id uuid not null,
  refund_method public.payment_method not null,
  refund_amount bigint not null check(refund_amount > 0),
  reason text not null check(length(trim(reason)) > 0),
  created_by uuid not null,
  created_at timestamptz not null,
  synced_at timestamptz,
  aggregate_hash bytea not null,
  unique(id,shop_id),
  foreign key(original_sale_id,shop_id) references public.sales(id,shop_id),
  foreign key(customer_id,shop_id) references public.customers(id,shop_id),
  foreign key(device_id,shop_id) references public.devices(id,shop_id)
);
create table public.sale_return_items(
  id uuid primary key,
  shop_id uuid not null references public.shops(id),
  return_id uuid not null,
  original_sale_item_id uuid not null,
  product_id uuid not null,
  product_name_snapshot text not null,
  quantity bigint not null check(quantity > 0),
  unit_price_snapshot bigint not null check(unit_price_snapshot >= 0),
  refund_amount bigint not null check(refund_amount >= 0),
  created_at timestamptz not null,
  unique(id,shop_id),
  foreign key(return_id,shop_id) references public.sale_returns(id,shop_id),
  foreign key(original_sale_item_id,shop_id) references public.sale_items(id,shop_id),
  foreign key(product_id,shop_id) references public.shop_products(id,shop_id)
);
create table public.sale_voids(
  id uuid primary key,
  shop_id uuid not null references public.shops(id),
  original_sale_id uuid not null,
  device_id uuid not null,
  amount bigint not null check(amount > 0),
  reason text not null check(length(trim(reason)) > 0),
  payment_breakdown jsonb not null,
  created_by uuid not null,
  created_at timestamptz not null,
  synced_at timestamptz,
  aggregate_hash bytea not null,
  unique(id,shop_id),
  unique(shop_id,original_sale_id),
  foreign key(original_sale_id,shop_id) references public.sales(id,shop_id),
  foreign key(device_id,shop_id) references public.devices(id,shop_id)
);
create index sale_returns_original on public.sale_returns(shop_id,original_sale_id,created_at);
create index sale_return_items_original on public.sale_return_items(shop_id,original_sale_item_id);

alter table public.sale_returns enable row level security;
alter table public.sale_return_items enable row level security;
alter table public.sale_voids enable row level security;
create policy sale_returns_owner_select on public.sale_returns for select to authenticated using(public.is_active_owner(shop_id));
create policy sale_return_items_owner_select on public.sale_return_items for select to authenticated using(public.is_active_owner(shop_id));
create policy sale_voids_owner_select on public.sale_voids for select to authenticated using(public.is_active_owner(shop_id));
revoke all on public.sale_returns,public.sale_return_items,public.sale_voids from public,anon,authenticated;
grant select on public.sale_returns,public.sale_return_items,public.sale_voids to authenticated;

create function public.sync_sale_return(p_payload jsonb,p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path=public,extensions,pg_temp as $$
declare
  h jsonb:=p_payload->'return';
  v_id uuid:=(h->>'id')::uuid;
  v_shop uuid:=(h->>'shop_id')::uuid;
  v_sale uuid:=(h->>'original_sale_id')::uuid;
  v_hash bytea:=extensions.digest(convert_to(p_payload::text,'UTF8'),'sha256');
  v_existing bytea;
  v_total bigint:=0;
  i jsonb;
  v_sold bigint;
  v_returned bigint;
  v_customer uuid;
  v_line_total bigint;
  v_expected_refund bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended(v_sale::text,0));
  if not public.is_active_owner(v_shop) then raise exception 'owner access required' using errcode='42501';end if;
  if (h->>'created_by')::uuid<>auth.uid() then raise exception 'owner actor mismatch' using errcode='42501';end if;
  select aggregate_hash into v_existing from public.sale_returns where id=v_id and shop_id=v_shop;
  if found then
    if v_existing<>v_hash then raise exception 'conflicting replay for immutable return';end if;
    return jsonb_build_object('return_id',v_id,'status','already_synced');
  end if;
  if p_payload->>'operation'<>'sync_sale_return' or jsonb_array_length(coalesce(p_payload->'items','[]'))=0 then raise exception 'invalid return payload';end if;
  if exists(select 1 from public.sale_voids where shop_id=v_shop and original_sale_id=v_sale) then raise exception 'voided sale cannot be returned';end if;
  select customer_id into v_customer from public.sales where id=v_sale and shop_id=v_shop;
  if not found then raise exception 'original sale required';end if;
  if not exists(select 1 from public.devices where id=(h->>'device_id')::uuid and shop_id=v_shop and is_active) then raise exception 'active device required' using errcode='42501';end if;
  for i in select value from jsonb_array_elements(p_payload->'items') loop
    select quantity,line_total into v_sold,v_line_total from public.sale_items where id=(i->>'original_sale_item_id')::uuid and sale_id=v_sale and shop_id=v_shop and product_id=(i->>'product_id')::uuid;
    if not found or (i->>'quantity')::bigint<=0 then raise exception 'invalid original sale item';end if;
    select coalesce(sum(ri.quantity),0) into v_returned from public.sale_return_items ri join public.sale_returns r on r.id=ri.return_id and r.shop_id=ri.shop_id where ri.shop_id=v_shop and r.original_sale_id=v_sale and ri.original_sale_item_id=(i->>'original_sale_item_id')::uuid;
    if v_returned+(i->>'quantity')::bigint>v_sold then raise exception 'return exceeds sold quantity';end if;
    v_expected_refund:=case when (i->>'quantity')::bigint=v_sold then v_line_total else (v_line_total*(i->>'quantity')::bigint+v_sold/2)/v_sold end;
    if (i->>'refund_amount')::bigint<>v_expected_refund then raise exception 'return item refund mismatch';end if;
    v_total:=v_total+(i->>'refund_amount')::bigint;
  end loop;
  if v_total<>(h->>'refund_amount')::bigint or v_total<=0 then raise exception 'return refund mismatch';end if;
  if exists(
    select 1 from (
      select x->>'product_id' product_id,sum((x->>'quantity')::bigint) quantity from jsonb_array_elements(p_payload->'items') x group by 1
    ) x full join (
      select m->>'product_id' product_id,sum((m->>'quantity')::bigint) quantity from jsonb_array_elements(coalesce(p_payload->'inventory_movements','[]')) m where m->>'type'='returnIn' group by 1
    ) m using(product_id)
    where x.product_id is null or m.product_id is null or x.quantity<>m.quantity
  ) then raise exception 'return inventory does not match items';end if;
  if h->>'refund_method'='credit' and v_customer is null then raise exception 'credit refund requires customer';end if;
  insert into public.sale_returns(id,shop_id,original_sale_id,customer_id,device_id,refund_method,refund_amount,reason,created_by,created_at,synced_at,aggregate_hash)
  values(v_id,v_shop,v_sale,v_customer,(h->>'device_id')::uuid,(h->>'refund_method')::public.payment_method,v_total,trim(h->>'reason'),auth.uid(),(h->>'created_at')::timestamptz,now(),v_hash);
  for i in select value from jsonb_array_elements(p_payload->'items') loop
    insert into public.sale_return_items(id,shop_id,return_id,original_sale_item_id,product_id,product_name_snapshot,quantity,unit_price_snapshot,refund_amount,created_at)
    values((i->>'id')::uuid,v_shop,v_id,(i->>'original_sale_item_id')::uuid,(i->>'product_id')::uuid,i->>'product_name_snapshot',(i->>'quantity')::bigint,(i->>'unit_price_snapshot')::bigint,(i->>'refund_amount')::bigint,(h->>'created_at')::timestamptz);
  end loop;
  for i in select value from jsonb_array_elements(p_payload->'inventory_movements') loop
    if i->>'type'<>'returnIn' or (i->>'quantity')::bigint<=0 then raise exception 'invalid return inventory movement';end if;
    insert into public.inventory_movements(id,shop_id,product_id,type,quantity,reference_type,reference_id,note,created_by,device_id,created_at)
    values((i->>'id')::uuid,v_shop,(i->>'product_id')::uuid,'returnIn',(i->>'quantity')::bigint,'sale_return',v_id,h->>'reason',auth.uid(),(h->>'device_id')::uuid,(h->>'created_at')::timestamptz);
  end loop;
  if h->>'refund_method'='credit' then
    insert into public.customer_ledger_entries(id,shop_id,customer_id,type,amount,sale_id,note,created_by,created_at)
    values((p_payload->>'ledger_id')::uuid,v_shop,v_customer,'refund',v_total,v_sale,h->>'reason',auth.uid(),(h->>'created_at')::timestamptz);
  end if;
  insert into public.audit_logs(id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at)
  values((p_payload->>'audit_id')::uuid,v_shop,auth.uid(),'sale.returned','sale_return',v_id,jsonb_build_object('sale_id',v_sale,'amount',v_total),(h->>'device_id')::uuid,(h->>'created_at')::timestamptz);
  return jsonb_build_object('return_id',v_id,'status','inserted');
end $$;

create function public.sync_sale_void(p_payload jsonb,p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path=public,extensions,pg_temp as $$
declare h jsonb:=p_payload->'void';v_id uuid:=(h->>'id')::uuid;v_shop uuid:=(h->>'shop_id')::uuid;v_sale uuid:=(h->>'original_sale_id')::uuid;v_hash bytea:=extensions.digest(convert_to(p_payload::text,'UTF8'),'sha256');v_old bytea;s public.sales%rowtype;i record;p record;
begin
  perform pg_advisory_xact_lock(hashtextextended(v_sale::text,0));
  if not public.is_active_owner(v_shop) then raise exception 'owner access required' using errcode='42501';end if;
  if (h->>'created_by')::uuid<>auth.uid() then raise exception 'owner actor mismatch' using errcode='42501';end if;
  select aggregate_hash into v_old from public.sale_voids where id=v_id and shop_id=v_shop;
  if found then if v_old<>v_hash then raise exception 'conflicting replay for immutable void';end if;return jsonb_build_object('void_id',v_id,'status','already_synced');end if;
  select * into s from public.sales where id=v_sale and shop_id=v_shop;
  if not found then raise exception 'original sale required';end if;
  if not exists(select 1 from public.devices where id=(h->>'device_id')::uuid and shop_id=v_shop and is_active) then raise exception 'active device required' using errcode='42501';end if;
  if (h->>'created_at')::timestamptz<s.created_at or (h->>'created_at')::timestamptz>s.created_at+interval '15 minutes' then raise exception 'void correction window expired';end if;
  if exists(select 1 from public.sale_returns where shop_id=v_shop and original_sale_id=v_sale) then raise exception 'sale with returns cannot be voided';end if;
  if exists(select 1 from public.sale_voids where shop_id=v_shop and original_sale_id=v_sale) then raise exception 'sale already voided';end if;
  if (h->>'amount')::bigint<>s.grand_total then raise exception 'void amount mismatch';end if;
  insert into public.sale_voids(id,shop_id,original_sale_id,device_id,amount,reason,payment_breakdown,created_by,created_at,synced_at,aggregate_hash)
  values(v_id,v_shop,v_sale,(h->>'device_id')::uuid,s.grand_total,trim(h->>'reason'),h->'payment_breakdown',auth.uid(),(h->>'created_at')::timestamptz,now(),v_hash);
  for i in select * from public.sale_items where sale_id=v_sale and shop_id=v_shop loop
    insert into public.inventory_movements(id,shop_id,product_id,type,quantity,reference_type,reference_id,note,created_by,device_id,created_at)
    values(extensions.gen_random_uuid(),v_shop,i.product_id,'returnIn',i.quantity,'sale_void',v_id,h->>'reason',auth.uid(),(h->>'device_id')::uuid,(h->>'created_at')::timestamptz);
  end loop;
  select * into p from public.sale_payments where sale_id=v_sale and shop_id=v_shop and payment_method='credit';
  if found then insert into public.customer_ledger_entries(id,shop_id,customer_id,type,amount,sale_id,note,created_by,created_at) values(extensions.gen_random_uuid(),v_shop,s.customer_id,'refund',p.amount,v_sale,h->>'reason',auth.uid(),(h->>'created_at')::timestamptz);end if;
  insert into public.audit_logs(id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at) values((p_payload->>'audit_id')::uuid,v_shop,auth.uid(),'sale.voided','sale_void',v_id,jsonb_build_object('sale_id',v_sale,'amount',s.grand_total),(h->>'device_id')::uuid,(h->>'created_at')::timestamptz);
  return jsonb_build_object('void_id',v_id,'status','inserted');
end $$;

revoke all on function public.sync_sale_return(jsonb,text),public.sync_sale_void(jsonb,text) from public,anon,authenticated;
grant execute on function public.sync_sale_return(jsonb,text),public.sync_sale_void(jsonb,text) to authenticated;
commit;
