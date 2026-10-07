-- U1: product units and pack variants foundation.
--
-- One shop_products row stays one sellable item. Quantities stay integer
-- thousandths of the product's unit (1 piece = 1000, 1 kg = 1000, 2.5 kg =
-- 2500, 750 ml = 750 of a liter product) and money stays integer paisa; every
-- line is (price * quantity + 500) / 1000 as before.
--
--   sell_mode             'piece' (default, every existing product) or
--                         'measured' (unit kg or liter). Fixed at creation.
--   family_id             groups pack variants of one product. Grouping only:
--                         never a sellable row, never shared across shops.
--   measure_presets       quick quantities in thousandths (measured only).
--   allow_custom_quantity measured products may take a typed quantity.
--   sale_items.measure_unit_snapshot
--                         'kg' / 'liter' for a measured line, null for a count.
--
-- Invariants enforced in the database, not only in the app:
--   * a piece line syncs only in whole units (quantity divisible by 1000);
--   * sell_mode, and the unit of a measured product, cannot change, so stock
--     and history are never reinterpreted;
--   * a family stays inside one shop; grouping changes no stock and no id;
--   * a barcode is unique per shop, across custom barcodes and the barcodes of
--     master products the shop has added;
--   * a piece return is in whole units; cumulative returns of a sale item
--     never exceed its sold quantity or refund more than its line total, and
--     the final remainder refunds exactly the rest.
--
-- Forward-only and additive. No historical financial row is rewritten. Old
-- queued sale payloads (no measureUnitSnapshot) and old return payloads stay
-- valid. Existing RPC signatures are unchanged; inner functions are replaced
-- in place with the same signature and privileges.
begin;

-- 0. Preflight (read-only). The per-shop barcode index below cannot be built
-- over duplicates; refuse to continue instead of merging or deleting rows.
-- scripts/u1_duplicate_barcode_check.sql lists the offending rows.
do $$
declare v_groups bigint;
begin
  select count(*) into v_groups from (
    select 1 from public.shop_products where barcode is not null
    group by shop_id, barcode having count(*) > 1) d;
  if v_groups > 0 then
    raise exception 'U1 preflight: % duplicate (shop_id, barcode) group(s) in shop_products; resolve them before applying this migration', v_groups;
  end if;
end $$;

-- 1. Product selling fields. Every existing row becomes a piece product.
alter table public.shop_products
  add column sell_mode text not null default 'piece',
  add column family_id uuid,
  add column measure_presets bigint[],
  add column allow_custom_quantity boolean not null default true,
  add constraint shop_products_sell_mode check (sell_mode in ('piece','measured')),
  add constraint shop_products_measured_unit check (sell_mode = 'piece' or unit in ('kg','liter')),
  add constraint shop_products_measure_presets check (
    measure_presets is null or (
      sell_mode = 'measured'
      and cardinality(measure_presets) between 1 and 8
      and array_position(measure_presets, null) is null
      and 0 < all(measure_presets) and 1000000 >= all(measure_presets))),
  add constraint shop_products_family_not_self check (family_id is null or family_id <> id);

-- The Dart unit list has always offered 'bag'; the server now accepts it.
-- 'unit' stays accepted for existing rows. Every existing value still passes.
alter table public.shop_products drop constraint shop_products_supported_unit;
alter table public.shop_products add constraint shop_products_supported_unit
  check (unit is null or lower(unit) in
    ('piece','pack','kg','gram','liter','bottle','carton','dozen','unit','bag'));

create index shop_products_family on public.shop_products(shop_id, family_id)
  where family_id is not null;
create unique index shop_products_unique_barcode on public.shop_products(shop_id, barcode)
  where barcode is not null;

alter table public.sale_items
  add column measure_unit_snapshot text,
  add constraint sale_items_measure_unit_snapshot
    check (measure_unit_snapshot is null or measure_unit_snapshot in ('kg','liter'));

-- Owners may tune quick quantities directly; selling mode and family are
-- changed only at creation or through set_product_family.
grant update(measure_presets, allow_custom_quantity) on table public.shop_products to authenticated;

-- 2. Identity guard. SECURITY DEFINER so the family and barcode checks see
-- every shop's rows, not only the caller's (RLS would hide them).
create function public.enforce_shop_product_identity() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_master_barcode text;
begin
  if tg_op = 'UPDATE' then
    if new.sell_mode is distinct from old.sell_mode then
      raise exception 'sell mode cannot change after product creation' using errcode = '22023';
    end if;
    if old.sell_mode = 'measured' and new.unit is distinct from old.unit then
      raise exception 'measured unit cannot change after product creation' using errcode = '22023';
    end if;
  end if;

  if new.family_id is not null
     and (tg_op = 'INSERT' or new.family_id is distinct from old.family_id) then
    perform pg_advisory_xact_lock(hashtextextended('family:' || new.family_id::text, 0));
    if exists(select 1 from public.shop_products
              where family_id = new.family_id and shop_id <> new.shop_id) then
      raise exception 'product family belongs to another shop' using errcode = '42501';
    end if;
    if exists(select 1 from public.shop_products where id = new.family_id) then
      raise exception 'product family cannot be a sellable product' using errcode = '22023';
    end if;
  end if;
  if tg_op = 'INSERT' and exists(select 1 from public.shop_products where family_id = new.id) then
    raise exception 'product family cannot be a sellable product' using errcode = '22023';
  end if;

  -- Effective barcode: a custom barcode, or the master barcode of an added
  -- master product. The unique index covers custom against custom.
  if tg_op = 'INSERT' or new.barcode is distinct from old.barcode
     or new.master_product_id is distinct from old.master_product_id then
    if new.barcode is not null then
      perform pg_advisory_xact_lock(hashtextextended('barcode:' || new.shop_id::text || ':' || new.barcode, 0));
      if exists(select 1 from public.shop_products sp
                join public.master_products mp on mp.id = sp.master_product_id
                where sp.shop_id = new.shop_id and sp.id <> new.id
                  and sp.barcode is null and mp.barcode = new.barcode) then
        raise exception 'barcode already exists in shop' using errcode = '23505';
      end if;
    elsif new.master_product_id is not null then
      select barcode into v_master_barcode from public.master_products where id = new.master_product_id;
      if v_master_barcode is not null then
        perform pg_advisory_xact_lock(hashtextextended('barcode:' || new.shop_id::text || ':' || v_master_barcode, 0));
        if exists(select 1 from public.shop_products
                  where shop_id = new.shop_id and id <> new.id and barcode = v_master_barcode) then
          raise exception 'barcode already exists in shop' using errcode = '23505';
        end if;
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.enforce_shop_product_identity() from public, anon, authenticated;
-- a00_server_seq still fires first (R1.4 lock order).
create trigger b10_shop_product_identity before insert or update on public.shop_products
  for each row execute function public.enforce_shop_product_identity();

-- 3. Sale sync. Same signature, same checks, plus the selling-mode rules.
-- A replay of an already stored sale skips the new rules and is answered by
-- the fingerprint check exactly as before, so nothing already accepted can
-- turn into a rejection. 'invalid sale item' maps to DPV01 (R1.5).
create or replace function public.sync_sale_transaction_validated_legacy(p_payload jsonb,p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path=public,extensions,pg_temp as $$
declare
  s jsonb:=p_payload->'sale';
  item jsonb;
  v_subtotal bigint:=0;
  v_discount bigint:=0;
  v_gross bigint;
  v_credit bigint:=0;
  v_mode text;
  v_unit text;
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
  -- U1 selling-mode rules, for a sale not stored yet. sell_mode and a
  -- measured unit are immutable, so the product's current values are the ones
  -- the device sold under. An unknown product is left to the insert below.
  if not exists(select 1 from public.sales
                where id=(s->>'id')::uuid and shop_id=(s->>'shopId')::uuid) then
    for item in select value from jsonb_array_elements(p_payload->'sale_items') loop
      select sp.sell_mode, sp.unit into v_mode, v_unit from public.shop_products sp
        where sp.id=(item->>'productId')::uuid and sp.shop_id=(s->>'shopId')::uuid;
      if found then
        if v_mode='piece' and (item->>'quantity')::bigint%1000<>0 then
          raise exception 'invalid sale item';
        end if;
        if nullif(item->>'measureUnitSnapshot','') is not null
           and (v_mode<>'measured' or item->>'measureUnitSnapshot'<>v_unit) then
          raise exception 'invalid sale item';
        end if;
      end if;
    end loop;
  end if;
  return public.sync_sale_transaction_authorized_legacy(p_payload,p_cashier_token);
end $$;

-- The row insert, unchanged except measure_unit_snapshot. The snapshot is
-- derived from the (immutable) selling mode, so a payload without the key
-- (queued before U1, or sent by an older app) still records the right unit.
create or replace function public.sync_sale_transaction_owner_legacy(p_payload jsonb)
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
    insert into public.sale_items(id, shop_id, sale_id, product_id, product_name_snapshot, barcode_snapshot, quantity, cost_price_snapshot, sale_price_snapshot, discount_amount, line_total, created_at, measure_unit_snapshot)
    values((r ->> 'id')::uuid, v_shop_id, v_sale_id, (r ->> 'productId')::uuid, r ->> 'productNameSnapshot', nullif(r ->> 'barcodeSnapshot', ''),
      (r ->> 'quantity')::bigint, (r ->> 'costPriceSnapshot')::bigint, (r ->> 'salePriceSnapshot')::bigint,
      (r ->> 'discountAmount')::bigint, (r ->> 'lineTotal')::bigint, (r ->> 'createdAt')::timestamptz,
      (select case when sp.sell_mode = 'measured' then sp.unit end from public.shop_products sp
        where sp.id = (r ->> 'productId')::uuid and sp.shop_id = v_shop_id));
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

-- 4. Returns. Same signature and checks; the per-item refund now follows the
-- cumulative rule, so a series of partial returns converges on the line total:
--   target(Q) = Q = sold ? line_total : (line_total*Q + sold/2) / sold
--   refund    = max(target(prior_qty + qty) - prior_refund, 0)
-- A first return equals the previous formula exactly. A payload computed with
-- the previous per-return formula (queued before U1) is still accepted while
-- it keeps the item's cumulative refund within its line total; otherwise it is
-- rejected (DPV01, needs attention), never over-refunded. An item may appear
-- once per return, and a piece product is returned in whole units only.
create or replace function public.sync_sale_return_validated_legacy(p_payload jsonb,p_cashier_token text default null)
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
  v_refunded bigint;
  v_customer uuid;
  v_line_total bigint;
  v_qty bigint;
  v_refund bigint;
  v_cumulative bigint;
  v_target bigint;
  v_expected_refund bigint;
  v_legacy_refund bigint;
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
  if exists(select 1 from jsonb_array_elements(p_payload->'items') x
            group by x->>'original_sale_item_id' having count(*)>1) then
    raise exception 'invalid return payload';
  end if;
  if exists(select 1 from public.sale_voids where shop_id=v_shop and original_sale_id=v_sale) then raise exception 'voided sale cannot be returned';end if;
  select customer_id into v_customer from public.sales where id=v_sale and shop_id=v_shop;
  if not found then raise exception 'original sale required';end if;
  if not exists(select 1 from public.devices where id=(h->>'device_id')::uuid and shop_id=v_shop and is_active) then raise exception 'active device required' using errcode='42501';end if;
  for i in select value from jsonb_array_elements(p_payload->'items') loop
    select quantity,line_total into v_sold,v_line_total from public.sale_items where id=(i->>'original_sale_item_id')::uuid and sale_id=v_sale and shop_id=v_shop and product_id=(i->>'product_id')::uuid;
    if not found or (i->>'quantity')::bigint<=0 then raise exception 'invalid original sale item';end if;
    v_qty:=(i->>'quantity')::bigint;
    -- A piece product is returned in whole units only; sell_mode is
    -- immutable, so the product's mode is the one it was sold under.
    if v_qty%1000<>0 and exists(select 1 from public.shop_products
        where id=(i->>'product_id')::uuid and shop_id=v_shop and sell_mode='piece') then
      raise exception 'invalid return payload';
    end if;
    select coalesce(sum(ri.quantity),0),coalesce(sum(ri.refund_amount),0) into v_returned,v_refunded
      from public.sale_return_items ri join public.sale_returns r on r.id=ri.return_id and r.shop_id=ri.shop_id
      where ri.shop_id=v_shop and r.original_sale_id=v_sale and ri.original_sale_item_id=(i->>'original_sale_item_id')::uuid;
    if v_returned+v_qty>v_sold then raise exception 'return exceeds sold quantity';end if;
    v_refund:=(i->>'refund_amount')::bigint;
    v_cumulative:=v_returned+v_qty;
    v_target:=case when v_cumulative=v_sold then v_line_total else (v_line_total*v_cumulative+v_sold/2)/v_sold end;
    v_expected_refund:=greatest(v_target-v_refunded,0);
    v_legacy_refund:=case when v_qty=v_sold then v_line_total else (v_line_total*v_qty+v_sold/2)/v_sold end;
    if v_refund<>v_expected_refund
       and not (v_refund=v_legacy_refund and v_refunded+v_refund<=v_line_total) then
      raise exception 'return item refund mismatch';
    end if;
    v_total:=v_total+v_refund;
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

-- 5. Custom product RPC: unchanged except that 'bag' is accepted.
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
  if lower(trim(p_unit)) not in ('piece','pack','kg','gram','liter','bottle','carton','dozen','unit','bag') then
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

-- 6. Owner product foundation (no UI yet). create_shop_product creates one
-- sellable row with its selling mode, optional family and opening stock in one
-- transaction; a retry with the same id answers already_exists.
create function public.create_shop_product(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_shop uuid;
  v_device uuid;
  v_id uuid;
  v_movement uuid;
  v_name text;
  v_category uuid;
  v_barcode text;
  v_unit text;
  v_mode text;
  v_family uuid;
  v_presets bigint[];
  v_purchase bigint;
  v_sale bigint;
  v_opening bigint;
  v_low bigint;
begin
  begin
    v_shop := (p_payload->>'shop_id')::uuid;
    v_device := (p_payload->>'device_id')::uuid;
    v_id := (p_payload->>'product_id')::uuid;
    v_movement := (p_payload->>'movement_id')::uuid;
    v_category := (p_payload->>'category_id')::uuid;
    v_family := nullif(p_payload->>'family_id','')::uuid;
    v_purchase := (p_payload->>'purchase_price')::bigint;
    v_sale := (p_payload->>'sale_price')::bigint;
    v_opening := coalesce((p_payload->>'opening_quantity')::bigint, 0);
    v_low := coalesce((p_payload->>'low_stock_level')::bigint, 0);
    if jsonb_typeof(p_payload->'measure_presets') = 'array' then
      select array_agg(value::bigint order by ordinality) into v_presets
        from jsonb_array_elements_text(p_payload->'measure_presets') with ordinality;
    end if;
  exception when others then
    raise exception 'invalid product payload' using errcode = '22023';
  end;
  v_name := trim(coalesce(p_payload->>'name',''));
  v_barcode := nullif(trim(coalesce(p_payload->>'barcode','')),'');
  v_unit := lower(trim(coalesce(p_payload->>'unit','')));
  v_mode := coalesce(p_payload->>'sell_mode','piece');

  if not public.is_active_owner(v_shop) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if v_id is null or v_movement is null or length(v_name) = 0 then
    raise exception 'product name required' using errcode = '22023';
  end if;
  if v_mode not in ('piece','measured') then
    raise exception 'unsupported sell mode' using errcode = '22023';
  end if;
  if (v_mode = 'measured' and v_unit not in ('kg','liter'))
     or v_unit not in ('piece','pack','kg','gram','liter','bottle','carton','dozen','unit','bag') then
    raise exception 'unsupported unit' using errcode = '22023';
  end if;
  if v_purchase is null or v_sale is null or v_purchase < 0 or v_sale < 0
     or v_opening < 0 or v_low < 0 then
    raise exception 'prices and quantities must be non-negative' using errcode = '22023';
  end if;
  if v_mode = 'piece' and (v_opening % 1000 <> 0 or v_low % 1000 <> 0) then
    raise exception 'piece stock must be whole units' using errcode = '22023';
  end if;
  if v_presets is not null and v_mode <> 'measured' then
    raise exception 'quick quantities are for measured products' using errcode = '22023';
  end if;
  if not exists(select 1 from public.devices where id=v_device and shop_id=v_shop and is_active) then
    raise exception 'active shop device required' using errcode = '42501';
  end if;
  if not exists(select 1 from public.categories
                where id=v_category and is_active and (shop_id is null or shop_id=v_shop)) then
    raise exception 'active category required' using errcode = '22023';
  end if;

  if exists(select 1 from public.shop_products where id=v_id and shop_id=v_shop) then
    return jsonb_build_object('product_id',v_id,'status','already_exists');
  end if;
  if v_barcode is not null and exists(
    select 1 from public.shop_products where shop_id=v_shop and barcode=v_barcode
  ) then raise exception 'barcode already exists in shop' using errcode = '23505'; end if;

  insert into public.shop_products(
    id,shop_id,custom_name,barcode,category_id,unit,pack_label,image_path,
    purchase_price,sale_price,stock_tracking_enabled,low_stock_level,is_active,
    sell_mode,family_id,measure_presets,allow_custom_quantity,created_at,updated_at
  ) values (
    v_id,v_shop,v_name,v_barcode,v_category,v_unit,
    nullif(trim(coalesce(p_payload->>'pack_label','')),''),
    nullif(trim(coalesce(p_payload->>'image_path','')),''),
    v_purchase,v_sale,true,v_low,true,
    v_mode,v_family,v_presets,coalesce((p_payload->>'allow_custom_quantity')::boolean,true),now(),now()
  );
  if v_opening > 0 then
    insert into public.inventory_movements(
      id,shop_id,product_id,type,quantity,reference_type,note,created_by,device_id,created_at
    ) values (
      v_movement,v_shop,v_id,'openingStock',v_opening,
      'product_setup','Opening stock',auth.uid(),v_device,now()
    ) on conflict(id) do nothing;
  end if;
  insert into public.audit_logs(
    id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at
  ) values (
    gen_random_uuid(),v_shop,auth.uid(),'product.created','shop_product',v_id,
    jsonb_build_object('name',v_name,'sell_mode',v_mode,'family_id',v_family),v_device,now()
  );
  return jsonb_build_object('product_id',v_id,'status','inserted');
end $$;

-- Groups (or, with a null family, ungroups) existing products of one shop.
-- Only family_id changes: ids, selling mode, unit and stock stay as they are.
create function public.set_product_family(p_shop_id uuid, p_family_id uuid, p_product_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_count integer;
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_product_ids),0) = 0 then
    raise exception 'products required' using errcode = '22023';
  end if;
  select count(*) into v_count from public.shop_products
    where shop_id = p_shop_id and id = any(p_product_ids);
  if v_count <> (select count(distinct x) from unnest(p_product_ids) x) then
    raise exception 'products must belong to the shop' using errcode = '42501';
  end if;
  update public.shop_products set family_id = p_family_id, updated_at = now()
    where shop_id = p_shop_id and id = any(p_product_ids)
      and family_id is distinct from p_family_id;
  insert into public.audit_logs(id,shop_id,user_id,action,entity_type,entity_id,new_value,created_at)
  values (gen_random_uuid(),p_shop_id,auth.uid(),'product.family_set','shop_product_family',
    coalesce(p_family_id, p_product_ids[1]),
    jsonb_build_object('family_id',p_family_id,'product_ids',to_jsonb(p_product_ids)),now());
  return jsonb_build_object('family_id',p_family_id,'products',v_count);
end $$;

revoke all on function public.create_shop_product(jsonb),
  public.set_product_family(uuid,uuid,uuid[]) from public, anon, authenticated;
grant execute on function public.create_shop_product(jsonb),
  public.set_product_family(uuid,uuid,uuid[]) to authenticated;

-- 7. Cashier pull: same contract (migration 22), with the new product and
-- sale-item columns.
create or replace function public.device_pull(
  p_entity text, p_after_seq bigint default null, p_after_id uuid default null,
  p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_device record;
  v_table text;
  v_columns text;
  v_filter text;
  v_rows jsonb;
begin
  select * into v_device from dukaan_private.request_device();
  if v_device.shop_id is null then
    raise exception 'device credential required' using errcode = '42501';
  end if;
  case p_entity
    when 'shops' then
      v_table := 'shops'; v_filter := 'id = $1';
      v_columns := 'id,name,phone,address,currency,timezone,subscription_plan,subscription_status,'
        'allow_negative_stock,created_at,updated_at,default_low_stock_level,receipt_footer,'
        'receipt_paper_width,receipt_show_phone,receipt_show_address,notifications_enabled,server_seq';
    when 'devices' then
      v_table := 'devices'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,device_name,device_type,device_identifier,is_active,last_seen_at,'
        'last_synced_at,created_at,updated_at,server_seq';
    when 'cashiers' then
      v_table := 'cashiers'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,display_name,login_code,credential_version,is_active,created_at,'
        'updated_at,server_seq';
    when 'categories' then
      v_table := 'categories'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,name,is_active,created_at,updated_at,server_seq';
    when 'globalCategories' then
      v_table := 'categories'; v_filter := 'shop_id is null and $1 is not null';
      v_columns := 'id,shop_id,name,is_active,created_at,updated_at,server_seq';
    when 'masterProducts' then
      v_table := 'master_products'; v_filter := '$1 is not null';
      v_columns := 'id,barcode,name,brand,category_id,default_image_path,default_unit,created_at,'
        'updated_at,is_active,pack_label,server_seq';
    when 'shopProducts' then
      v_table := 'shop_products'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,master_product_id,custom_name,barcode,purchase_price,sale_price,'
        'stock_tracking_enabled,low_stock_level,is_active,created_at,updated_at,category_id,unit,'
        'pack_label,image_path,sell_mode,family_id,measure_presets,allow_custom_quantity,server_seq';
    when 'customers' then
      v_table := 'customers'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,name,phone,address,credit_limit,is_active,created_at,updated_at,'
        'notes,server_seq';
    when 'customerLedgerEntries' then
      v_table := 'customer_ledger_entries'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,customer_id,type,amount,sale_id,payment_reference,note,created_by,'
        'created_at,payment_method,server_seq';
    when 'inventoryMovements' then
      v_table := 'inventory_movements'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,product_id,type,quantity,reference_type,reference_id,note,'
        'created_by,device_id,created_at,server_seq';
    when 'sales' then
      v_table := 'sales'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,cashier_id,customer_id,device_id,invoice_number,subtotal,'
        'discount_total,tax_total,grand_total,payment_status,sale_status,created_at,synced_at,'
        'server_seq';
    when 'saleItems' then
      v_table := 'sale_items'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,sale_id,product_id,product_name_snapshot,barcode_snapshot,quantity,'
        'cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at,'
        'measure_unit_snapshot,server_seq';
    when 'salePayments' then
      v_table := 'sale_payments'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,sale_id,payment_method,amount,reference,created_at,server_seq';
    when 'saleReturns' then
      v_table := 'sale_returns'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,original_sale_id,customer_id,device_id,refund_method,refund_amount,'
        'reason,created_by,created_at,synced_at,server_seq';
    when 'saleReturnItems' then
      v_table := 'sale_return_items'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,return_id,original_sale_item_id,product_id,product_name_snapshot,'
        'quantity,unit_price_snapshot,refund_amount,created_at,server_seq';
    when 'saleVoids' then
      v_table := 'sale_voids'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,original_sale_id,device_id,amount,reason,payment_breakdown,'
        'created_by,created_at,synced_at,server_seq';
    else
      raise exception 'unsupported pull entity' using errcode = '22023';
  end case;
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t) order by t.server_seq, t.id), ''[]''::jsonb) from ('
    'select %s from public.%I where %s and ($2::bigint is null or server_seq > $2 '
    'or ($3::uuid is not null and server_seq = $2 and id > $3)) '
    'order by server_seq, id limit $4) t',
    v_columns, v_table, v_filter)
  into v_rows
  using v_device.shop_id, p_after_seq, p_after_id, least(greatest(coalesce(p_limit, 100), 1), 500);
  return v_rows;
end $$;

commit;
