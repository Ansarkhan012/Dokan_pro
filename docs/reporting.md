# Owner dashboard and reporting

The dashboard is owner-only and local-first. It reads the active shop's Drift
database, so it remains useful offline. A visible cached-data notice reminds the
owner that pending operations on other devices are absent until synchronization.

## Accounting definitions

- Sales include completed sales whose `created_at` is in the selected half-open
  range (`start <= time < end`). Voided and returned sales are excluded.
- COGS is the sum of each sale item's immutable `cost_price_snapshot × quantity
  / 1000`. Current product purchase prices and purchase totals are never used.
- Gross profit = sales - COGS.
- Net profit = gross profit - operating expenses. Inventory purchases are not
  subtracted again because their cost is recognized through COGS.
- Cash, digital, and credit are allocations from sale payment rows, not extra
  revenue.
- Customer receivables and supplier payables are current all-time ledger
  balances. They deliberately ignore the report date range.
- Money is integer paisa; quantities are integer thousandths.

Period boundaries use `Asia/Karachi` civil dates and are converted to UTC before
queries. The current implementation uses Pakistan's fixed UTC+05:00 offset
(Pakistan does not observe daylight saving time). Custom end dates are inclusive
in the UI and converted to an exclusive start of the following day.

## Cloud readiness and security

`owner_report_summary` is a stable, security-definer RPC with a controlled
`search_path`. It checks active owner membership before reading a shop and is
executable only by `authenticated`. The app dashboard currently uses Drift; the
RPC is intended for future cross-device reconciliation without exposing direct
financial writes or service-role credentials.

The existing `(shop_id, created_at)` and ledger/inventory indexes cover current
period and balance queries. No mutable summary table is introduced; reports can
always be rebuilt from append-only financial history.
