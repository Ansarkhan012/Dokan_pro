-- B-1 (PROJECT_AUDIT.md): index customer_ledger_entries by sale.
--
-- Every sale upload runs, in sync_sale_transaction_owner_legacy
-- (migration 202610080001, line 310):
--   select sum(amount) from public.customer_ledger_entries
--    where sale_id = v_sale_id and type = 'creditSale'
-- The table had indexes only on (shop_id, customer_id, created_at) and
-- (shop_id, server_seq, id), so that check was a sequential scan of every
-- shop's ledger, once per uploaded sale. Most ledger rows of a sale carry
-- sale_id; payments and opening balances do not, hence the partial index.
--
-- Additive and data-preserving: no row, function or privilege changes.
--
-- Deployment on a large production table: build it first without blocking
-- writes, outside any transaction, then apply this migration (a no-op):
--   create index concurrently if not exists customer_ledger_entries_sale
--     on public.customer_ledger_entries (sale_id) where sale_id is not null;
-- A plain CREATE INDEX (below) takes a SHARE lock and blocks ledger writes
-- for the length of the build; at pilot size that is milliseconds.
begin;

create index if not exists customer_ledger_entries_sale
  on public.customer_ledger_entries (sale_id)
  where sale_id is not null;

commit;
