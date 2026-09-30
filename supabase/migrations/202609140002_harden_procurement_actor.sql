begin;
create function public.enforce_owner_procurement_actor() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or new.created_by <> auth.uid() or not public.is_active_owner(new.shop_id) then
    raise exception 'active owner actor required' using errcode='42501';
  end if;
  return new;
end $$;
create trigger purchases_owner_actor before insert on public.purchases for each row execute function public.enforce_owner_procurement_actor();
create trigger supplier_ledger_owner_actor before insert on public.supplier_ledger_entries for each row execute function public.enforce_owner_procurement_actor();
revoke all on function public.enforce_owner_procurement_actor() from public,anon,authenticated;
commit;
