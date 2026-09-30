begin;

-- Remote reporting contract. The Flutter dashboard remains local-first, while
-- this owner-only RPC provides the same immutable accounting basis for future
-- cross-device reconciliation. End is exclusive to avoid boundary duplicates.
create or replace function public.owner_report_summary(
  p_shop_id uuid,
  p_start timestamptz,
  p_end timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  if p_start is null or p_end is null or p_start >= p_end then
    raise exception 'invalid report range';
  end if;
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'shop_id', p_shop_id,
    'start', p_start,
    'end', p_end,
    'sales', coalesce((select sum(s.grand_total) from public.sales s
      where s.shop_id=p_shop_id and s.sale_status='completed'
        and s.created_at>=p_start and s.created_at<p_end), 0),
    'bill_count', (select count(*) from public.sales s
      where s.shop_id=p_shop_id and s.sale_status='completed'
        and s.created_at>=p_start and s.created_at<p_end),
    'cogs', coalesce((select sum((si.cost_price_snapshot*si.quantity+500)/1000)
      from public.sale_items si join public.sales s
        on s.id=si.sale_id and s.shop_id=si.shop_id
      where s.shop_id=p_shop_id and s.sale_status='completed'
        and s.created_at>=p_start and s.created_at<p_end), 0),
    'purchases', coalesce((select sum(p.total) from public.purchases p
      where p.shop_id=p_shop_id and p.created_at>=p_start and p.created_at<p_end), 0),
    'purchase_paid', coalesce((select sum(p.paid_amount) from public.purchases p
      where p.shop_id=p_shop_id and p.created_at>=p_start and p.created_at<p_end), 0),
    'expenses', coalesce((select sum(e.amount) from public.expenses e
      where e.shop_id=p_shop_id and e.expense_at>=p_start and e.expense_at<p_end), 0),
    'receivables', coalesce((select sum(case when l.type in ('openingBalance','creditSale','adjustment') then l.amount else -l.amount end)
      from public.customer_ledger_entries l where l.shop_id=p_shop_id), 0),
    'payables', coalesce((select sum(case when l.type in ('openingBalance','purchase','adjustment') then l.amount else -l.amount end)
      from public.supplier_ledger_entries l where l.shop_id=p_shop_id), 0)
  ) into result;
  return result;
end
$$;

revoke all on function public.owner_report_summary(uuid,timestamptz,timestamptz)
  from public, anon, authenticated;
grant execute on function public.owner_report_summary(uuid,timestamptz,timestamptz)
  to authenticated;

commit;
