begin;

alter table public.shops
  add column default_low_stock_level bigint not null default 0 check(default_low_stock_level >= 0),
  add column receipt_footer text not null default '',
  add column receipt_paper_width text not null default '80mm' check(receipt_paper_width in ('58mm','80mm')),
  add column receipt_show_phone boolean not null default true,
  add column receipt_show_address boolean not null default true,
  add column notifications_enabled boolean not null default false;

create or replace function public.update_shop_settings(
  p_shop_id uuid, p_name text, p_phone text, p_address text,
  p_allow_negative_stock boolean, p_default_low_stock_level bigint,
  p_receipt_footer text, p_receipt_paper_width text,
  p_receipt_show_phone boolean, p_receipt_show_address boolean,
  p_notifications_enabled boolean)
returns public.shops
language plpgsql security definer set search_path=public,pg_temp as $$
declare result public.shops;
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode='42501';
  end if;
  if length(trim(p_name))=0 then raise exception 'shop name required'; end if;
  if p_default_low_stock_level < 0 then raise exception 'low stock threshold must be non-negative'; end if;
  if p_receipt_paper_width not in ('58mm','80mm') then raise exception 'invalid paper width'; end if;
  update public.shops set name=trim(p_name),phone=trim(coalesce(p_phone,'')),
    address=trim(coalesce(p_address,'')),currency='PKR',timezone='Asia/Karachi',
    allow_negative_stock=p_allow_negative_stock,
    default_low_stock_level=p_default_low_stock_level,
    receipt_footer=coalesce(p_receipt_footer,''),receipt_paper_width=p_receipt_paper_width,
    receipt_show_phone=p_receipt_show_phone,receipt_show_address=p_receipt_show_address,
    notifications_enabled=p_notifications_enabled,updated_at=now()
  where id=p_shop_id returning * into result;
  return result;
end $$;
revoke all on function public.update_shop_settings(uuid,text,text,text,boolean,bigint,text,text,boolean,boolean,boolean) from public;
grant execute on function public.update_shop_settings(uuid,text,text,text,boolean,bigint,text,text,boolean,boolean,boolean) to authenticated;

-- Keep the remote reconciliation contract on the same activity-date basis as
-- the local dashboard: sales are gross on sale date; returns/voids reduce net
-- on their own immutable posting date; returned cost reverses snapshot COGS.
create or replace function public.owner_report_summary(
  p_shop_id uuid,p_start timestamptz,p_end timestamptz) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb; gross bigint; refunds bigint; net_cogs bigint;
begin
  if p_start is null or p_end is null or p_start>=p_end then raise exception 'invalid report range'; end if;
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode='42501'; end if;
  select coalesce(sum(grand_total),0) into gross from public.sales
    where shop_id=p_shop_id and sale_status='completed' and created_at>=p_start and created_at<p_end;
  select coalesce((select sum(refund_amount) from public.sale_returns where shop_id=p_shop_id and created_at>=p_start and created_at<p_end),0)
    +coalesce((select sum(amount) from public.sale_voids where shop_id=p_shop_id and created_at>=p_start and created_at<p_end),0) into refunds;
  select
    coalesce((select sum((si.cost_price_snapshot*si.quantity+500)/1000) from public.sale_items si join public.sales s on s.id=si.sale_id and s.shop_id=si.shop_id where s.shop_id=p_shop_id and s.created_at>=p_start and s.created_at<p_end),0)
    -coalesce((select sum((si.cost_price_snapshot*ri.quantity+500)/1000) from public.sale_return_items ri join public.sale_returns r on r.id=ri.return_id and r.shop_id=ri.shop_id join public.sale_items si on si.id=ri.original_sale_item_id and si.shop_id=ri.shop_id where r.shop_id=p_shop_id and r.created_at>=p_start and r.created_at<p_end),0)
    -coalesce((select sum((si.cost_price_snapshot*si.quantity+500)/1000) from public.sale_items si join public.sale_voids v on v.original_sale_id=si.sale_id and v.shop_id=si.shop_id where v.shop_id=p_shop_id and v.created_at>=p_start and v.created_at<p_end),0) into net_cogs;
  select jsonb_build_object(
    'shop_id',p_shop_id,'start',p_start,'end',p_end,
    'gross_sales',gross,'returns',refunds,'net_sales',gross-refunds,'sales',gross-refunds,
    'bill_count',(select count(*) from public.sales where shop_id=p_shop_id and created_at>=p_start and created_at<p_end),
    'cogs',net_cogs,
    'estimated_gross_profit',gross-refunds-net_cogs,
    'purchases',coalesce((select sum(total) from public.purchases where shop_id=p_shop_id and created_at>=p_start and created_at<p_end),0),
    'purchase_paid',coalesce((select sum(paid_amount) from public.purchases where shop_id=p_shop_id and created_at>=p_start and created_at<p_end),0),
    'expenses',coalesce((select sum(amount) from public.expenses where shop_id=p_shop_id and expense_at>=p_start and expense_at<p_end),0),
    'receivables',coalesce((select sum(case when type in('openingBalance','creditSale','adjustment') then amount else -amount end) from public.customer_ledger_entries where shop_id=p_shop_id),0),
    'payables',coalesce((select sum(case when type in('openingBalance','purchase','adjustment') then amount else -amount end) from public.supplier_ledger_entries where shop_id=p_shop_id),0)
  ) into result;
  return result;
end $$;
revoke all on function public.owner_report_summary(uuid,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.owner_report_summary(uuid,timestamptz,timestamptz) to authenticated;

commit;
