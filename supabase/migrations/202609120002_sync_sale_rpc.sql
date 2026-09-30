begin;

create or replace function public.sync_sale_transaction(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_sale jsonb := p_payload -> 'sale';
  v_sale_id uuid := (v_sale ->> 'id')::uuid;
  v_shop_id uuid := (v_sale ->> 'shopId')::uuid;
  v_cashier_id uuid := (v_sale ->> 'cashierId')::uuid;
  v_device_id uuid := (v_sale ->> 'deviceId')::uuid;
  v_customer_id uuid := nullif(v_sale ->> 'customerId', '')::uuid;
  v_payment_sum bigint;
  v_credit_sum bigint;
  v_existing_shop uuid;
  r jsonb;
begin
  if p_payload ->> 'version' <> '1' or p_payload ->> 'operation' <> 'sync_sale_transaction' then
    raise exception 'unsupported sale payload';
  end if;
  if not public.is_active_owner(v_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  select shop_id into v_existing_shop from public.sales where id = v_sale_id;
  if found then
    if v_existing_shop <> v_shop_id then raise exception 'sale id belongs to another shop' using errcode = '42501'; end if;
    return jsonb_build_object('sale_id', v_sale_id, 'status', 'already_synced');
  end if;
  if not exists(select 1 from public.devices where id = v_device_id and shop_id = v_shop_id and is_active) then
    raise exception 'inactive or foreign device';
  end if;
  if not exists(select 1 from public.shop_users where shop_id = v_shop_id and user_id = v_cashier_id and is_active)
     and not exists(select 1 from public.cashiers where shop_id = v_shop_id and id = v_cashier_id and is_active) then
    raise exception 'inactive or foreign cashier';
  end if;
  if jsonb_array_length(coalesce(p_payload -> 'sale_items', '[]'::jsonb)) = 0 then raise exception 'sale requires items'; end if;
  select coalesce(sum((x ->> 'amount')::bigint), 0),
         coalesce(sum((x ->> 'amount')::bigint) filter(where x ->> 'paymentMethod' = 'credit'), 0)
    into v_payment_sum, v_credit_sum from jsonb_array_elements(coalesce(p_payload -> 'payments', '[]'::jsonb)) x;
  if v_payment_sum <> (v_sale ->> 'grandTotal')::bigint then raise exception 'payment total mismatch'; end if;
  if v_credit_sum > 0 and v_customer_id is null then raise exception 'credit requires customer'; end if;

  insert into public.sales(id, shop_id, cashier_id, customer_id, device_id, invoice_number, subtotal, discount_total, tax_total, grand_total, payment_status, sale_status, created_at, synced_at)
  values(v_sale_id, v_shop_id, v_cashier_id, v_customer_id, v_device_id, nullif(v_sale ->> 'invoiceNumber', ''),
    (v_sale ->> 'subtotal')::bigint, (v_sale ->> 'discountTotal')::bigint, (v_sale ->> 'taxTotal')::bigint,
    (v_sale ->> 'grandTotal')::bigint, (v_sale ->> 'paymentStatus')::public.payment_status,
    (v_sale ->> 'saleStatus')::public.sale_status, (v_sale ->> 'createdAt')::timestamptz, now());

  for r in select value from jsonb_array_elements(p_payload -> 'sale_items') loop
    insert into public.sale_items(id, shop_id, sale_id, product_id, product_name_snapshot, barcode_snapshot, quantity, cost_price_snapshot, sale_price_snapshot, discount_amount, line_total, created_at)
    values((r ->> 'id')::uuid, v_shop_id, v_sale_id, (r ->> 'productId')::uuid, r ->> 'productNameSnapshot', nullif(r ->> 'barcodeSnapshot', ''),
      (r ->> 'quantity')::bigint, (r ->> 'costPriceSnapshot')::bigint, (r ->> 'salePriceSnapshot')::bigint,
      (r ->> 'discountAmount')::bigint, (r ->> 'lineTotal')::bigint, (r ->> 'createdAt')::timestamptz);
  end loop;
  for r in select value from jsonb_array_elements(p_payload -> 'payments') loop
    insert into public.sale_payments(id, shop_id, sale_id, payment_method, amount, reference, created_at)
    values((r ->> 'id')::uuid, v_shop_id, v_sale_id, (r ->> 'paymentMethod')::public.payment_method,
      (r ->> 'amount')::bigint, nullif(r ->> 'reference', ''), (r ->> 'createdAt')::timestamptz);
  end loop;
  for r in select value from jsonb_array_elements(p_payload -> 'inventory_movements') loop
    if (r ->> 'type') <> 'sale' or (r ->> 'quantity')::bigint >= 0 then raise exception 'invalid sale inventory movement'; end if;
    insert into public.inventory_movements(id, shop_id, product_id, type, quantity, reference_type, reference_id, note, created_by, device_id, created_at)
    values((r ->> 'id')::uuid, v_shop_id, (r ->> 'productId')::uuid, 'sale', (r ->> 'quantity')::bigint,
      'sale', v_sale_id, nullif(r ->> 'note', ''), v_cashier_id, v_device_id, (r ->> 'createdAt')::timestamptz);
  end loop;
  for r in select value from jsonb_array_elements(coalesce(p_payload -> 'customer_ledger_entries', '[]'::jsonb)) loop
    insert into public.customer_ledger_entries(id, shop_id, customer_id, type, amount, sale_id, payment_reference, note, created_by, created_at)
    values((r ->> 'id')::uuid, v_shop_id, (r ->> 'customerId')::uuid, 'creditSale', (r ->> 'amount')::bigint,
      v_sale_id, null, nullif(r ->> 'note', ''), v_cashier_id, (r ->> 'createdAt')::timestamptz);
  end loop;
  if v_credit_sum <> coalesce((select sum(amount) from public.customer_ledger_entries where sale_id = v_sale_id and type = 'creditSale'), 0) then
    raise exception 'credit ledger mismatch';
  end if;
  insert into public.audit_logs(id, shop_id, user_id, action, entity_type, entity_id, new_value, device_id, created_at)
  values((p_payload ->> 'audit_id')::uuid, v_shop_id, v_cashier_id, 'sale.synced', 'sale', v_sale_id,
    jsonb_build_object('grand_total', (v_sale ->> 'grandTotal')::bigint), v_device_id, now());
  return jsonb_build_object('sale_id', v_sale_id, 'status', 'inserted');
end; $$;

revoke all on function public.sync_sale_transaction(jsonb) from public;
grant execute on function public.sync_sale_transaction(jsonb) to authenticated;

commit;
