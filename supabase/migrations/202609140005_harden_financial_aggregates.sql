begin;

alter function public.sync_sale_transaction(jsonb,text)
  rename to sync_sale_transaction_authorized_legacy;
revoke all on function public.sync_sale_transaction_authorized_legacy(jsonb,text)
  from public,anon,authenticated;

create function public.sync_sale_transaction(p_payload jsonb,p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path=public,extensions,pg_temp as $$
declare
  s jsonb:=p_payload->'sale';
  item jsonb;
  v_subtotal bigint:=0;
  v_discount bigint:=0;
  v_gross bigint;
  v_credit bigint:=0;
begin
  if p_payload->>'version'<>'1' or p_payload->>'operation'<>'sync_sale_transaction' then
    raise exception 'unsupported sale payload';
  end if;
  if jsonb_array_length(coalesce(p_payload->'sale_items','[]'))=0 then
    raise exception 'sale requires items';
  end if;
  for item in select value from jsonb_array_elements(p_payload->'sale_items') loop
    if (item->>'quantity')::bigint<=0 or (item->>'salePriceSnapshot')::bigint<0
       or (item->>'costPriceSnapshot')::bigint<0 or (item->>'discountAmount')::bigint<0 then
      raise exception 'invalid sale item';
    end if;
    v_gross:=((item->>'salePriceSnapshot')::bigint*(item->>'quantity')::bigint+500)/1000;
    if (item->>'discountAmount')::bigint>v_gross
       or (item->>'lineTotal')::bigint<>v_gross-(item->>'discountAmount')::bigint then
      raise exception 'sale item total mismatch';
    end if;
    v_subtotal:=v_subtotal+v_gross;
    v_discount:=v_discount+(item->>'discountAmount')::bigint;
  end loop;
  if (s->>'subtotal')::bigint<>v_subtotal or (s->>'discountTotal')::bigint<>v_discount
     or (s->>'taxTotal')::bigint<0
     or (s->>'grandTotal')::bigint<>v_subtotal-v_discount+(s->>'taxTotal')::bigint
     or s->>'saleStatus'<>'completed' or s->>'paymentStatus'<>'paid' then
    raise exception 'sale header total mismatch';
  end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_payload->'payments','[]')) p
    where (p->>'amount')::bigint<=0 or p->>'paymentMethod' not in('cash','digital','credit')) then
    raise exception 'invalid sale payment';
  end if;
  select coalesce(sum((p->>'amount')::bigint) filter(where p->>'paymentMethod'='credit'),0)
    into v_credit from jsonb_array_elements(coalesce(p_payload->'payments','[]')) p;
  if exists(
    select 1 from (
      select i->>'productId' product_id,sum((i->>'quantity')::bigint) quantity
        from jsonb_array_elements(p_payload->'sale_items') i group by 1
    ) i full join (
      select m->>'productId' product_id,-sum((m->>'quantity')::bigint) quantity
        from jsonb_array_elements(coalesce(p_payload->'inventory_movements','[]')) m
        where m->>'type'='sale' group by 1
    ) m using(product_id)
    where i.product_id is null or m.product_id is null or i.quantity<>m.quantity
  ) then raise exception 'sale inventory does not match items'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_payload->'inventory_movements','[]')) m
    where m->>'type'<>'sale' or (m->>'quantity')::bigint>=0) then
    raise exception 'invalid sale inventory movement';
  end if;
  if v_credit=0 and jsonb_array_length(coalesce(p_payload->'customer_ledger_entries','[]'))<>0 then
    raise exception 'unexpected credit ledger';
  elsif v_credit>0 and (
    nullif(s->>'customerId','') is null
    or jsonb_array_length(coalesce(p_payload->'customer_ledger_entries','[]'))<>1
    or ((p_payload->'customer_ledger_entries'->0)->>'amount')::bigint<>v_credit
    or (p_payload->'customer_ledger_entries'->0)->>'customerId'<>s->>'customerId'
  ) then raise exception 'credit ledger mismatch'; end if;
  return public.sync_sale_transaction_authorized_legacy(p_payload,p_cashier_token);
end $$;

alter function public.sync_purchase_transaction(jsonb,text)
  rename to sync_purchase_transaction_authorized_legacy;
revoke all on function public.sync_purchase_transaction_authorized_legacy(jsonb,text)
  from public,anon,authenticated;

create function public.sync_purchase_transaction(p_payload jsonb,p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path=public,extensions,pg_temp as $$
declare p jsonb:=p_payload->'purchase';i jsonb;v_subtotal bigint:=0;v_line bigint;
begin
  if p_payload->>'operation'<>'sync_purchase_transaction'
     or jsonb_array_length(coalesce(p_payload->'purchase_items','[]'))=0 then
    raise exception 'unsupported purchase payload';
  end if;
  for i in select value from jsonb_array_elements(p_payload->'purchase_items') loop
    if (i->>'quantity')::bigint<=0 or (i->>'unitCost')::bigint<0 then raise exception 'invalid purchase item';end if;
    v_line:=((i->>'unitCost')::bigint*(i->>'quantity')::bigint+500)/1000;
    if (i->>'lineTotal')::bigint<>v_line then raise exception 'purchase item total mismatch';end if;
    v_subtotal:=v_subtotal+v_line;
  end loop;
  if (p->>'subtotal')::bigint<>v_subtotal or (p->>'discountTotal')::bigint<0
     or (p->>'discountTotal')::bigint>v_subtotal
     or (p->>'total')::bigint<>v_subtotal-(p->>'discountTotal')::bigint then
    raise exception 'purchase header total mismatch';
  end if;
  if exists(
    select 1 from (
      select x->>'productId' product_id,sum((x->>'quantity')::bigint) quantity
      from jsonb_array_elements(p_payload->'purchase_items') x group by 1
    ) x full join (
      select m->>'productId' product_id,sum((m->>'quantity')::bigint) quantity
      from jsonb_array_elements(coalesce(p_payload->'inventory_movements','[]')) m
      where m->>'type'='purchase' group by 1
    ) m using(product_id)
    where x.product_id is null or m.product_id is null or x.quantity<>m.quantity
  ) then raise exception 'purchase inventory does not match items';end if;
  return public.sync_purchase_transaction_authorized_legacy(p_payload,p_cashier_token);
end $$;

revoke all on function public.sync_sale_transaction(jsonb,text),
  public.sync_purchase_transaction(jsonb,text) from public,anon,authenticated;
grant execute on function public.sync_sale_transaction(jsonb,text) to anon,authenticated;
grant execute on function public.sync_purchase_transaction(jsonb,text) to authenticated;
commit;
