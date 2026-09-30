begin;

create type public.billing_cycle as enum ('trial','monthly','annual');
create type public.subscription_status_v2 as enum ('trialing','active','cancelled','expired');

create table public.subscription_plans(
  id text primary key, name text not null, billing_cycle public.billing_cycle not null,
  price_pkr_minor bigint not null check(price_pkr_minor>=0), trial_days integer not null default 0,
  offline_grace_days integer not null default 7 check(offline_grace_days between 0 and 30),
  feature_limits jsonb not null default '{}'::jsonb, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.shop_subscriptions(
  id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.shops(id),
  plan_id text not null references public.subscription_plans(id), status public.subscription_status_v2 not null,
  period_start timestamptz not null, period_end timestamptz not null,
  grace_until timestamptz not null, cancel_at_period_end boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(shop_id), check(period_end>period_start), check(grace_until>=period_end)
);
create table public.device_entitlements(
  id uuid primary key default gen_random_uuid(), entitlement_version integer not null default 1,
  shop_id uuid not null references public.shops(id), device_id uuid not null,
  subscription_id uuid not null references public.shop_subscriptions(id), plan_id text not null references public.subscription_plans(id),
  issued_at timestamptz not null, valid_until timestamptz not null, offline_grace_until timestamptz not null,
  payload_hash text not null, key_id text not null, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  foreign key(device_id,shop_id) references public.devices(id,shop_id), unique(shop_id,device_id,payload_hash)
);

insert into public.subscription_plans(id,name,billing_cycle,price_pkr_minor,trial_days,offline_grace_days,feature_limits) values
('trial','Trial','trial',0,14,7,'{}'),
('starter_monthly','Starter','monthly',199900,0,7,'{}'),
('starter_annual','Starter','annual',1999000,0,7,'{}'),
('pro_monthly','Pro','monthly',299900,0,7,'{}'),
('pro_annual','Pro','annual',2999000,0,7,'{}');

alter table public.subscription_plans enable row level security;
alter table public.shop_subscriptions enable row level security;
alter table public.device_entitlements enable row level security;
create policy subscription_plans_read on public.subscription_plans for select to authenticated using(true);
create policy shop_subscriptions_owner_read on public.shop_subscriptions for select to authenticated using(public.is_active_owner(shop_id));
create policy device_entitlements_owner_read on public.device_entitlements for select to authenticated using(public.is_active_owner(shop_id));
revoke all on public.subscription_plans,public.shop_subscriptions,public.device_entitlements from public,anon,authenticated;
grant select on public.subscription_plans,public.shop_subscriptions,public.device_entitlements to authenticated;

create function public.provision_trial_subscription() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  insert into public.shop_subscriptions(shop_id,plan_id,status,period_start,period_end,grace_until)
  values(new.id,'trial','trialing',now(),now()+interval '14 days',now()+interval '21 days') on conflict(shop_id) do nothing;
  return new;
end $$;
revoke all on function public.provision_trial_subscription() from public;
create trigger shops_provision_trial after insert on public.shops for each row execute function public.provision_trial_subscription();
insert into public.shop_subscriptions(shop_id,plan_id,status,period_start,period_end,grace_until)
select id,'trial','trialing',created_at,created_at+interval '14 days',created_at+interval '21 days' from public.shops on conflict(shop_id) do nothing;

create or replace function public.entitlement_claims(p_shop_id uuid,p_device_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.shop_subscriptions; d public.devices; issued timestamptz:=clock_timestamp(); eid uuid:=gen_random_uuid();
begin
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode='42501'; end if;
  select * into d from public.devices where id=p_device_id and shop_id=p_shop_id and is_active;
  if not found then raise exception 'active device required' using errcode='42501'; end if;
  select * into s from public.shop_subscriptions where shop_id=p_shop_id and status in('trialing','active','cancelled');
  if not found then raise exception 'subscription unavailable' using errcode='42501'; end if;
  return jsonb_build_object('entitlement_version',1,'entitlement_id',eid,'shop_id',p_shop_id,'device_id',p_device_id,
    'subscription_id',s.id,'plan_id',s.plan_id,'issued_at',issued,'valid_until',s.period_end,
    'offline_grace_until',s.grace_until,'server_time',issued);
end $$;
revoke all on function public.entitlement_claims(uuid,uuid) from public,anon;
grant execute on function public.entitlement_claims(uuid,uuid) to authenticated;

commit;
