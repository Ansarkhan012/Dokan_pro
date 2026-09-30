-- Design-validation prototype for the R1 server_seq mechanism (scratch DB only).
create table shops(id uuid primary key);
create table shop_sync_state(shop_id uuid primary key references shops(id), last_seq bigint not null);
alter table shop_sync_state enable row level security;           -- no policies, no grants: server-only

-- Allocates ONE order value per (transaction, shop); cached in a
-- transaction-local setting bound to the current transaction id so that a
-- stale or forged setting can never be reused.
create function sync_begin(p_shop uuid) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  k text := 'dukaan.sync_seq_' || replace(p_shop::text, '-', '');
  cached text := current_setting(k, true);
  tx text := txid_current()::text;
  s bigint;
begin
  if cached is not null and cached <> '' and split_part(cached, ':', 1) = tx then
    return split_part(cached, ':', 2)::bigint;
  end if;
  insert into shop_sync_state(shop_id, last_seq) values (p_shop, 1)
    on conflict (shop_id) do update set last_seq = shop_sync_state.last_seq + 1
    returning last_seq into s;                         -- row lock held until commit/rollback
  perform set_config(k, tx || ':' || s, true);
  return s;
end $$;

-- Every pulled table: the trigger ALWAYS overwrites the client value.
create function assign_server_seq() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.server_seq := sync_begin(new.shop_id);
  return new;
end $$;

create table sales(id uuid primary key, shop_id uuid not null references shops(id), total bigint, server_seq bigint not null);
create table sale_items(id uuid primary key, shop_id uuid not null references shops(id), sale_id uuid, server_seq bigint not null);
create table inventory_movements(id uuid primary key, shop_id uuid not null references shops(id), qty bigint, server_seq bigint not null);
create trigger a00_server_seq before insert or update on sales for each row execute function assign_server_seq();
create trigger a00_server_seq before insert or update on sale_items for each row execute function assign_server_seq();
create trigger a00_server_seq before insert or update on inventory_movements for each row execute function assign_server_seq();
create index on sales(shop_id, server_seq, id);
create index on sale_items(shop_id, server_seq, id);
create index on inventory_movements(shop_id, server_seq, id);

-- Checkout-shaped aggregate write, idempotent on sale id.
create function sync_sale(p_shop uuid, p_sale uuid, p_hold_ms int default 0) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_sale::text, 0));   -- 1. entity lock
  if exists(select 1 from sales where id = p_sale) then return 'already_synced'; end if;  -- replay: no seq
  perform sync_begin(p_shop);                                           -- 2. shop order lock
  insert into sales values (p_sale, p_shop, 100, -1);                   -- -1 = forged client value
  insert into sale_items values (gen_random_uuid(), p_shop, p_sale, 999999);
  insert into inventory_movements values (gen_random_uuid(), p_shop, -1, 0);
  perform pg_sleep(p_hold_ms / 1000.0);
  return 'inserted';
end $$;

insert into shops values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');
