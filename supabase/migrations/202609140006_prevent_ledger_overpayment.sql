begin;
create function public.prevent_customer_overpayment() returns trigger language plpgsql set search_path=public,pg_temp as $$declare balance bigint;begin
if new.type<>'paymentReceived' then return new;end if;
perform pg_advisory_xact_lock(hashtextextended(new.shop_id::text||':customer:'||new.customer_id::text,0));
select coalesce(sum(case when type in('openingBalance','creditSale','adjustment')then amount else -amount end),0) into balance from public.customer_ledger_entries where shop_id=new.shop_id and customer_id=new.customer_id;
if new.amount>balance then raise exception 'payment exceeds customer balance' using errcode='23514';end if;return new;end$$;
create function public.prevent_supplier_overpayment() returns trigger language plpgsql set search_path=public,pg_temp as $$declare balance bigint;begin
if new.type<>'paymentMade' then return new;end if;
perform pg_advisory_xact_lock(hashtextextended(new.shop_id::text||':supplier:'||new.supplier_id::text,0));
select coalesce(sum(case when type in('openingBalance','purchase','adjustment')then amount else -amount end),0) into balance from public.supplier_ledger_entries where shop_id=new.shop_id and supplier_id=new.supplier_id;
if new.amount>balance then raise exception 'payment exceeds supplier payable' using errcode='23514';end if;return new;end$$;
create trigger customer_overpayment_guard before insert on public.customer_ledger_entries for each row execute function public.prevent_customer_overpayment();
create trigger supplier_overpayment_guard before insert on public.supplier_ledger_entries for each row execute function public.prevent_supplier_overpayment();
revoke all on function public.prevent_customer_overpayment(),public.prevent_supplier_overpayment() from public,anon,authenticated;
commit;
