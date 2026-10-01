-- R1.4 (findings O-2, T-1b): server-owned sync order.
--
-- Devices pulled by (created_at|updated_at, id). Those timestamps come from the
-- device clock (an offline sale uploaded late, or a device whose clock runs
-- ahead, sorts behind a cursor that has already moved past it, so other
-- devices never receive it), and the device stored its cursor with whole
-- seconds while the server keeps microseconds (rows inside one second were
-- fetched again forever).
--
-- Every pulled row now carries server_seq, assigned here and never by a
-- client: one value per transaction and shop, taken from a per-shop counter
-- row (global rows - master products and global categories - use one global
-- counter). The counter row stays locked until the transaction ends, so a
-- shop's writers obtain values in commit order and the committed values are
-- always a gap-free prefix: a cursor (server_seq, id) can never pass a row
-- that commits later. A rolled-back writer releases its number unused.
--
-- Additive only: existing rows get server_seq 0 and are delivered by a first
-- pull from the start. No existing migration, row or RPC is changed.
begin;

create table public.shop_sync_state(
  shop_id uuid primary key,
  last_seq bigint not null
);
create table public.global_sync_state(
  singleton boolean primary key default true check (singleton),
  last_seq bigint not null
);
insert into public.global_sync_state values (true, 0);
alter table public.shop_sync_state enable row level security;
alter table public.global_sync_state enable row level security;
revoke all on public.shop_sync_state, public.global_sync_state from public, anon, authenticated;

-- The sync position of the current transaction for one shop (null = global).
create function public.sync_begin(p_shop uuid) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  k text := 'dukaan.sync_seq_' || coalesce(replace(p_shop::text, '-', ''), 'global');
  cached text := current_setting(k, true);
  tx text := txid_current()::text;
  s bigint;
begin
  if cached is not null and cached <> '' and split_part(cached, ':', 1) = tx then
    return split_part(cached, ':', 2)::bigint;  -- same transaction: same position
  end if;
  if p_shop is null then
    update public.global_sync_state set last_seq = last_seq + 1 returning last_seq into s;
  else
    insert into public.shop_sync_state values (p_shop, 1)
      on conflict (shop_id) do update set last_seq = public.shop_sync_state.last_seq + 1
      returning last_seq into s;  -- the counter row stays locked until commit
  end if;
  perform set_config(k, tx || ':' || s, true);  -- transaction-local
  return s;
end $$;
revoke all on function public.sync_begin(uuid) from public, anon, authenticated;

-- Overwrites any client value on every insert and update.
create function public.assign_server_seq() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.server_seq := public.sync_begin(
    case when tg_table_name = 'shops' then new.id
         else (to_jsonb(new) ->> 'shop_id')::uuid end);
  return new;
end $$;
revoke all on function public.assign_server_seq() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'shops','devices','cashiers','categories','master_products','shop_products','customers',
    'customer_ledger_entries','suppliers','supplier_ledger_entries','purchases','purchase_items',
    'purchase_payments','expense_categories','expenses','inventory_movements','sales','sale_items',
    'sale_payments','sale_returns','sale_return_items','sale_voids'
  ] loop
    execute format('alter table public.%I add column server_seq bigint not null default 0', t);
    if t in ('shops', 'master_products') then
      execute format('create index %I on public.%I(server_seq, id)', t || '_sync_order', t);
    else
      execute format('create index %I on public.%I(shop_id, server_seq, id)', t || '_sync_order', t);
    end if;
    -- a00_ sorts first, so the shop counter is taken before any policy trigger.
    execute format(
      'create trigger a00_server_seq before insert or update on public.%I '
      'for each row execute function public.assign_server_seq()', t);
  end loop;
end $$;

-- cashiers is readable column by column (pin_hash is never exposed); the
-- pull also needs the new position column.
grant select(server_seq) on public.cashiers to authenticated;

commit;
