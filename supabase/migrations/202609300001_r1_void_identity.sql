-- R1.3 (finding F-2): void contract v2 with client compensation identities.
--
-- v1 voids carried only the void header; the server generated its own ids for
-- the stock and Udhaar compensation rows while the device kept the ones it had
-- written locally, so every pull added a second compensation on the device.
--
-- v2 carries the device's ids: movement_ids maps each original sale item id to
-- the id of its returnIn movement, and refund_ledger_id is the id of the Udhaar
-- refund (null when the sale had no Udhaar). The server stores exactly those
-- rows. Quantities, products and the refund amount are still derived from the
-- server's own sale rows; the client ids and totals are validated against them.
--
-- Any payload that is not version 2 is refused with SQLSTATE DPV01 before any
-- read or write (decision D5). Voids accepted before this migration are not
-- replayed, rewritten or repaired. Only sync_sale_void changes.
begin;

create or replace function public.sync_sale_void(p_payload jsonb,p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path=public,extensions,pg_temp as $$
declare
  h jsonb:=p_payload->'void';
  v_ids jsonb:=p_payload->'movement_ids';
  v_id uuid;v_shop uuid;v_sale uuid;v_refund_id uuid;
  v_hash bytea:=extensions.digest(convert_to(p_payload::text,'UTF8'),'sha256');
  v_old bytea;v_credit bigint;v_breakdown jsonb;v_items int;
  s public.sales%rowtype;i record;
begin
  if p_payload->>'version' is distinct from '2' then
    raise exception 'DPV01: void payload version % is not supported; void contract v2 is required',
      coalesce(p_payload->>'version','(none)') using errcode='DPV01';
  end if;
  v_id:=(h->>'id')::uuid;v_shop:=(h->>'shop_id')::uuid;v_sale:=(h->>'original_sale_id')::uuid;
  perform pg_advisory_xact_lock(hashtextextended(v_sale::text,0));
  if not public.is_active_owner(v_shop) then raise exception 'owner access required' using errcode='42501';end if;
  if (h->>'created_by')::uuid<>auth.uid() then raise exception 'owner actor mismatch' using errcode='42501';end if;
  select aggregate_hash into v_old from public.sale_voids where id=v_id and shop_id=v_shop;
  if found then
    if v_old<>v_hash then raise exception 'conflicting replay for immutable void';end if;
    return jsonb_build_object('void_id',v_id,'status','already_synced');
  end if;
  select * into s from public.sales where id=v_sale and shop_id=v_shop;
  if not found then raise exception 'original sale required';end if;
  if not exists(select 1 from public.devices where id=(h->>'device_id')::uuid and shop_id=v_shop and is_active) then
    raise exception 'active device required' using errcode='42501';
  end if;
  if (h->>'created_at')::timestamptz<s.created_at or (h->>'created_at')::timestamptz>s.created_at+interval '15 minutes' then
    raise exception 'void correction window expired';
  end if;
  if exists(select 1 from public.sale_returns where shop_id=v_shop and original_sale_id=v_sale) then raise exception 'sale with returns cannot be voided';end if;
  if exists(select 1 from public.sale_voids where shop_id=v_shop and original_sale_id=v_sale) then raise exception 'sale already voided';end if;
  if (h->>'amount')::bigint<>s.grand_total then raise exception 'void amount mismatch';end if;

  select coalesce(jsonb_object_agg(method,amount),'{}'::jsonb) into v_breakdown from (
    select payment_method::text method,sum(amount) amount from public.sale_payments
    where sale_id=v_sale and shop_id=v_shop group by 1) x;
  if coalesce(h->'payment_breakdown','{}'::jsonb)<>v_breakdown then raise exception 'void payment breakdown mismatch';end if;

  select count(*) into v_items from public.sale_items where sale_id=v_sale and shop_id=v_shop;
  if jsonb_typeof(v_ids) is distinct from 'object' then
    raise exception 'void compensation ids do not match the sale items';
  end if;
  if (select count(*) from jsonb_object_keys(v_ids))<>v_items
     or exists(select 1 from public.sale_items it where it.sale_id=v_sale and it.shop_id=v_shop and not v_ids ? it.id::text)
     or exists(select 1 from jsonb_each(v_ids) e where jsonb_typeof(e.value)<>'string')
     or (select count(distinct value) from jsonb_each_text(v_ids))<>v_items then
    raise exception 'void compensation ids do not match the sale items';
  end if;
  select coalesce(sum(amount),0) into v_credit from public.sale_payments
    where sale_id=v_sale and shop_id=v_shop and payment_method='credit';
  v_refund_id:=nullif(p_payload->>'refund_ledger_id','')::uuid;
  if (v_credit>0)<>(v_refund_id is not null) then raise exception 'void refund ledger id mismatch';end if;

  insert into public.sale_voids(id,shop_id,original_sale_id,device_id,amount,reason,payment_breakdown,created_by,created_at,synced_at,aggregate_hash)
  values(v_id,v_shop,v_sale,(h->>'device_id')::uuid,s.grand_total,trim(h->>'reason'),v_breakdown,auth.uid(),(h->>'created_at')::timestamptz,now(),v_hash);
  for i in select * from public.sale_items where sale_id=v_sale and shop_id=v_shop loop
    insert into public.inventory_movements(id,shop_id,product_id,type,quantity,reference_type,reference_id,note,created_by,device_id,created_at)
    values((v_ids->>i.id::text)::uuid,v_shop,i.product_id,'returnIn',i.quantity,'sale_void',v_id,h->>'reason',auth.uid(),(h->>'device_id')::uuid,(h->>'created_at')::timestamptz);
  end loop;
  if v_credit>0 then
    insert into public.customer_ledger_entries(id,shop_id,customer_id,type,amount,sale_id,note,created_by,created_at)
    values(v_refund_id,v_shop,s.customer_id,'refund',v_credit,v_sale,h->>'reason',auth.uid(),(h->>'created_at')::timestamptz);
  end if;
  insert into public.audit_logs(id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at)
  values((p_payload->>'audit_id')::uuid,v_shop,auth.uid(),'sale.voided','sale_void',v_id,
    jsonb_build_object('sale_id',v_sale,'amount',s.grand_total),(h->>'device_id')::uuid,(h->>'created_at')::timestamptz);
  return jsonb_build_object('void_id',v_id,'status','inserted');
end $$;

revoke all on function public.sync_sale_void(jsonb,text) from public,anon,authenticated;
grant execute on function public.sync_sale_void(jsonb,text) to authenticated;
commit;
