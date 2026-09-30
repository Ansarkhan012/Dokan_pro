begin;

create extension if not exists pgcrypto;

create type public.shop_role as enum ('owner', 'cashier');
create type public.device_type as enum ('androidTablet', 'windowsDesktop', 'mobile', 'other');
create type public.payment_method as enum ('cash', 'digital', 'credit', 'other');
create type public.payment_status as enum ('unpaid', 'partiallyPaid', 'paid', 'refunded');
create type public.sale_status as enum ('completed', 'voided', 'partiallyReturned', 'returned');
create type public.inventory_movement_type as enum ('openingStock', 'purchase', 'sale', 'returnIn', 'damage', 'manualAdjustment', 'stockCorrection');
create type public.customer_ledger_type as enum ('openingBalance', 'creditSale', 'paymentReceived', 'refund', 'adjustment');
create type public.shift_status as enum ('open', 'closed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '', phone text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.shops (
  id uuid primary key default gen_random_uuid(), name text not null check (length(trim(name)) > 0),
  phone text not null default '', address text not null default '', currency text not null default 'PKR',
  timezone text not null default 'Asia/Karachi', subscription_plan text not null default 'trial',
  subscription_status text not null default 'trial', allow_negative_stock boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.shop_users (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, role public.shop_role not null,
  is_active boolean not null default true, created_at timestamptz not null default now(), unique(shop_id, user_id)
);
create table public.cashiers (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.shops(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) > 0), login_code text not null,
  pin_hash text not null, credential_version integer not null default 1 check (credential_version > 0),
  is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(shop_id, login_code), unique(id, shop_id)
);
create table public.devices (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.shops(id) on delete cascade,
  device_name text not null, device_type public.device_type not null, device_identifier uuid not null,
  is_active boolean not null default true, last_seen_at timestamptz, last_synced_at timestamptz,
  created_at timestamptz not null default now(), unique(shop_id, device_identifier), unique(id, shop_id)
);
create table public.categories (
  id uuid primary key, shop_id uuid references public.shops(id) on delete cascade, name text not null,
  is_active boolean not null default true, created_at timestamptz not null, updated_at timestamptz not null
);
create table public.master_products (
  id uuid primary key, barcode text not null unique, name text not null, brand text not null default '',
  category_id uuid references public.categories(id), default_image_path text, default_unit text not null,
  created_at timestamptz not null, updated_at timestamptz not null
);
create table public.shop_products (
  id uuid primary key, shop_id uuid not null references public.shops(id) on delete cascade,
  master_product_id uuid references public.master_products(id), custom_name text, barcode text,
  purchase_price bigint not null check (purchase_price >= 0), sale_price bigint not null check (sale_price >= 0),
  stock_tracking_enabled boolean not null default true, low_stock_level bigint,
  is_active boolean not null default true, created_at timestamptz not null, updated_at timestamptz not null,
  check (master_product_id is not null or length(trim(custom_name)) > 0), unique(id, shop_id)
);
create table public.customers (
  id uuid primary key, shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null, phone text, address text, credit_limit bigint check (credit_limit is null or credit_limit >= 0),
  is_active boolean not null default true, created_at timestamptz not null, updated_at timestamptz not null, unique(id, shop_id)
);
create table public.sales (
  id uuid primary key, shop_id uuid not null references public.shops(id), cashier_id uuid not null,
  customer_id uuid, device_id uuid not null, invoice_number text,
  subtotal bigint not null check (subtotal >= 0), discount_total bigint not null check (discount_total >= 0),
  tax_total bigint not null check (tax_total >= 0), grand_total bigint not null check (grand_total >= 0),
  payment_status public.payment_status not null, sale_status public.sale_status not null,
  created_at timestamptz not null, synced_at timestamptz,
  foreign key(customer_id, shop_id) references public.customers(id, shop_id),
  foreign key(device_id, shop_id) references public.devices(id, shop_id), unique(id, shop_id)
);
create table public.sale_items (
  id uuid primary key, shop_id uuid not null references public.shops(id), sale_id uuid not null, product_id uuid not null,
  product_name_snapshot text not null, barcode_snapshot text, quantity bigint not null check (quantity > 0),
  cost_price_snapshot bigint not null check (cost_price_snapshot >= 0), sale_price_snapshot bigint not null check (sale_price_snapshot >= 0),
  discount_amount bigint not null check (discount_amount >= 0), line_total bigint not null check (line_total >= 0), created_at timestamptz not null,
  foreign key(sale_id, shop_id) references public.sales(id, shop_id),
  foreign key(product_id, shop_id) references public.shop_products(id, shop_id)
);
create table public.sale_payments (
  id uuid primary key, shop_id uuid not null references public.shops(id), sale_id uuid not null,
  payment_method public.payment_method not null, amount bigint not null check (amount >= 0), reference text, created_at timestamptz not null,
  foreign key(sale_id, shop_id) references public.sales(id, shop_id)
);
create table public.inventory_movements (
  id uuid primary key, shop_id uuid not null references public.shops(id), product_id uuid not null,
  type public.inventory_movement_type not null, quantity bigint not null check (quantity <> 0),
  reference_type text, reference_id uuid, note text, created_by uuid not null, device_id uuid, created_at timestamptz not null,
  foreign key(product_id, shop_id) references public.shop_products(id, shop_id),
  foreign key(device_id, shop_id) references public.devices(id, shop_id)
);
create table public.customer_ledger_entries (
  id uuid primary key, shop_id uuid not null references public.shops(id), customer_id uuid not null,
  type public.customer_ledger_type not null, amount bigint not null check (amount >= 0), sale_id uuid,
  payment_reference text, note text, created_by uuid not null, created_at timestamptz not null,
  foreign key(customer_id, shop_id) references public.customers(id, shop_id),
  foreign key(sale_id, shop_id) references public.sales(id, shop_id)
);
create table public.cashier_shifts (
  id uuid primary key, shop_id uuid not null references public.shops(id), cashier_id uuid not null, device_id uuid not null,
  opened_at timestamptz not null, closed_at timestamptz, opening_cash bigint not null check(opening_cash >= 0),
  expected_cash bigint, actual_cash bigint, cash_difference bigint, status public.shift_status not null,
  foreign key(cashier_id, shop_id) references public.cashiers(id, shop_id),
  foreign key(device_id, shop_id) references public.devices(id, shop_id)
);
create table public.audit_logs (
  id uuid primary key, shop_id uuid not null references public.shops(id), user_id uuid not null,
  action text not null, entity_type text not null, entity_id uuid not null, old_value jsonb, new_value jsonb,
  device_id uuid, created_at timestamptz not null,
  foreign key(device_id, shop_id) references public.devices(id, shop_id)
);

create index shop_users_user on public.shop_users(user_id, is_active);
create index devices_shop on public.devices(shop_id);
create index categories_shop on public.categories(shop_id);
create index shop_products_shop_barcode on public.shop_products(shop_id, barcode);
create index customers_shop on public.customers(shop_id);
create index sales_shop_created on public.sales(shop_id, created_at desc);
create index sale_items_sale on public.sale_items(sale_id);
create index sale_payments_sale on public.sale_payments(sale_id);
create index inventory_product_created on public.inventory_movements(shop_id, product_id, created_at);
create index customer_ledger_lookup on public.customer_ledger_entries(shop_id, customer_id, created_at);
create index shifts_shop_cashier on public.cashier_shifts(shop_id, cashier_id, opened_at desc);
create index audit_shop_created on public.audit_logs(shop_id, created_at desc);

create or replace function public.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles(id, full_name) values(new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict(id) do nothing;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_auth_user();
revoke all on function public.handle_new_auth_user() from public;

create or replace function public.is_active_owner(p_shop_id uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.shop_users su where su.shop_id = p_shop_id and su.user_id = auth.uid() and su.role = 'owner' and su.is_active);
$$;
revoke all on function public.is_active_owner(uuid) from public;
grant execute on function public.is_active_owner(uuid) to authenticated;

create or replace function public.create_owner_shop(p_name text, p_phone text default '', p_address text default '')
returns table(shop_id uuid, shop_name text)
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_shop public.shops;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if length(trim(p_name)) = 0 then raise exception 'shop name required'; end if;
  insert into public.shops(name, phone, address, currency, timezone, allow_negative_stock)
    values(trim(p_name), coalesce(p_phone, ''), coalesce(p_address, ''), 'PKR', 'Asia/Karachi', true) returning * into v_shop;
  insert into public.shop_users(shop_id, user_id, role) values(v_shop.id, auth.uid(), 'owner');
  return query select v_shop.id, v_shop.name;
end; $$;
revoke all on function public.create_owner_shop(text,text,text) from public;
grant execute on function public.create_owner_shop(text,text,text) to authenticated;

create or replace function public.register_shop_device(p_shop_id uuid, p_device_name text, p_device_type public.device_type, p_device_identifier uuid)
returns table(device_id uuid, is_active boolean)
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_device public.devices;
begin
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode = '42501'; end if;
  insert into public.devices(shop_id, device_name, device_type, device_identifier, last_seen_at)
    values(p_shop_id, trim(p_device_name), p_device_type, p_device_identifier, now())
    on conflict(shop_id, device_identifier) do update set device_name = excluded.device_name, device_type = excluded.device_type, last_seen_at = now()
    returning * into v_device;
  return query select v_device.id, v_device.is_active;
end; $$;
revoke all on function public.register_shop_device(uuid,text,public.device_type,uuid) from public;
grant execute on function public.register_shop_device(uuid,text,public.device_type,uuid) to authenticated;

create or replace function public.create_cashier(p_shop_id uuid, p_display_name text, p_login_code text, p_pin text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode = '42501'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN must contain 4 to 8 digits'; end if;
  insert into public.cashiers(shop_id, display_name, login_code, pin_hash)
    values(p_shop_id, trim(p_display_name), trim(p_login_code), crypt(p_pin, gen_salt('bf', 12))) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.create_cashier(uuid,text,text,text) from public;
grant execute on function public.create_cashier(uuid,text,text,text) to authenticated;

create or replace function public.set_cashier_active(p_shop_id uuid, p_cashier_id uuid, p_is_active boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode = '42501'; end if;
  update public.cashiers set is_active = p_is_active, updated_at = now()
    where id = p_cashier_id and shop_id = p_shop_id;
  if not found then raise exception 'cashier not found'; end if;
end; $$;
revoke all on function public.set_cashier_active(uuid,uuid,boolean) from public;
grant execute on function public.set_cashier_active(uuid,uuid,boolean) to authenticated;

alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.shop_users enable row level security;
alter table public.cashiers enable row level security;
alter table public.devices enable row level security;
alter table public.categories enable row level security;
alter table public.master_products enable row level security;
alter table public.shop_products enable row level security;
alter table public.customers enable row level security;
alter table public.customer_ledger_entries enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.sale_payments enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.cashier_shifts enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_self_select on public.profiles for select to authenticated using(id = auth.uid());
create policy profiles_self_update on public.profiles for update to authenticated using(id = auth.uid()) with check(id = auth.uid());
create policy shops_owner_select on public.shops for select to authenticated using(public.is_active_owner(id));
create policy shop_users_visible_membership on public.shop_users for select to authenticated using(user_id = auth.uid() or public.is_active_owner(shop_id));
create policy master_products_authenticated_read on public.master_products for select to authenticated using(true);

create policy cashiers_owner_select on public.cashiers for select to authenticated using(public.is_active_owner(shop_id));

do $$ declare t text; begin
  foreach t in array array['devices','shop_products','customers','cashier_shifts'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_owner(shop_id))', t || '_owner_select', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.is_active_owner(shop_id))', t || '_owner_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.is_active_owner(shop_id)) with check (public.is_active_owner(shop_id))', t || '_owner_update', t);
  end loop;
  foreach t in array array['customer_ledger_entries','sales','sale_items','sale_payments','inventory_movements','audit_logs'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active_owner(shop_id))', t || '_owner_select', t);
  end loop;
end $$;
create policy categories_owner_or_global_read on public.categories for select to authenticated using(shop_id is null or public.is_active_owner(shop_id));
create policy categories_owner_insert on public.categories for insert to authenticated with check(shop_id is not null and public.is_active_owner(shop_id));
create policy categories_owner_update on public.categories for update to authenticated using(public.is_active_owner(shop_id)) with check(public.is_active_owner(shop_id));

commit;
