# Local database

## Migration baseline and release policy

Versions 1–6 were development-only iterations. No repository release artifact,
external-shop distribution record, historical schema export, or old database
fixture exists showing that those builds were distributed. They must not be
reconstructed from memory. The authentic committed v7 export
`drift_schemas/drift_schema_v7.json` is therefore the first supported migration
baseline.

Every schema version after v7 must be captured before release with
`dart run drift_dev schema dump lib/database/app_database.dart
drift_schemas/drift_schema_vN.json`, followed by `dart run drift_dev schema
generate drift_schemas test/generated_migrations`. The schema snapshot guard
test fails when `schemaVersion` changes without the matching committed snapshot
and generated schema. Migration tests must upgrade every previously released
snapshot to the new version and verify IDs, row counts, money, quantities, and
financial child rows. Never fabricate a missing historical schema.

Schema version 7 uses Drift over SQLite with foreign keys enabled on every open. UUID strings are primary keys and timestamps are UTC `DateTime` values. Upgrades are explicit and incremental; destructive recreate migrations are not acceptable for production data.

## Tables

- Organization: `shops`, `shop_users`, `cashiers`, `devices`
- Catalogue: `categories`, `master_products`, `shop_products`
- Parties: `customers`, `customer_ledger_entries`, `suppliers`, `supplier_ledger_entries`
- Sales and stock: `sales`, `sale_items`, `sale_payments`, `inventory_movements`
- Procurement: `purchases`, `purchase_items`
- Operations: `expenses`, `cashier_shifts`, `audit_logs`, `sync_operations`

All shop-specific rows include `shop_id`. Global master products and global categories are the only intended exceptions; a category with a non-null shop ID is custom. Monetary columns are integer paisa. Quantity columns are integer thousandths.

Indexes target tenant lookup, barcode lookup, sale/purchase children, product movement history, customer/supplier ledgers, chronological transactions, and sync queue status/entity lookup. Indexes are deliberately not added to low-cardinality fields without a tenant/query prefix.

## Persistence rules

- Transaction children duplicate `shop_id` to make tenant filtering and future RLS explicit; application writes must verify parent and child shops match.
- Inventory and ledgers are append-oriented sources of truth. Cached balances may be introduced only as rebuildable projections.
- `sale_items` are historical snapshots.
- `old_value`, `new_value`, and sync `payload` are JSON text. Their schemas must be versioned before cloud exchange.
- Images are filesystem/cache references and Supabase Storage paths, never SQLite BLOBs.

## Phase 1 migrations

Drift schema version 2 adds `shops.allow_negative_stock` and `cashiers` through an explicit incremental migration. The cloud intentionally omits Phase 0 procurement, supplier, and expense tables because Phase 1 does not synchronize those workflows. It includes profiles and cashier credentials, which have cloud identity/security value. Future local and cloud changes must use additive numbered migrations with upgrade and RLS regression tests.

## Phase 2A migration

Drift schema version 3 adds lease/backoff/dependency fields, deterministic pull cursors, device update timestamps, and master-product activation. Cloud migrations add aggregate fingerprints, cashier sessions, PIN-attempt limits, hardened cashier column privileges, and session-aware sale authorization.

## Product management migration

Drift schema version 4 and the matching PostgreSQL migration add master pack
labels plus custom-product category, unit, pack-label, and image-reference
fields. `shop_products(shop_id, master_product_id)` is unique when a master ID
is present. Opening stock remains an immutable `openingStock` inventory
movement; no mutable stock column is introduced.

## Customer and Khata migration

Drift schema version 5 adds customer notes and a ledger payment-method field.
PostgreSQL adds the same fields, an owner-only `save_customer` RPC, and the
idempotent `sync_customer_payment` RPC. Ledger `amount` is always a positive
magnitude: `creditSale` contributes `+amount`, while `paymentReceived`
contributes `-amount`. No mutable balance column exists. Financial entries have
no client update/delete privilege and corrections must be new entries.

## Suppliers and purchases migration

Drift schema version 6 adds supplier contact/notes, purchase payment rows,
purchase device/paid metadata, and immutable product-name snapshots. Cloud
tables mirror suppliers, purchases, items, payments, and supplier ledger rows.
Payable and stock remain projections of append-only ledger and inventory
movements; neither has a mutable balance column.

## Expenses migration

Drift schema version 7 adds tenant expense categories and extends expenses with
category identity, cash/digital payment method, expense timestamp, note,
reference, and device. Cloud expenses are immutable and carry a payload
fingerprint. Reporting indexes cover shop/date, shop/category/date, and
shop/payment-method/date without introducing summary balance columns.

## Sales history migration

Drift schema version 8 adds the tenant-scoped
`sales(shop_id, invoice_number)` index for fast exact receipt/reference lookup.
It does not rewrite financial records or introduce mutable totals.
# Reporting queries

Reporting introduces no mutable aggregate tables. Local queries use existing
shop/date, ledger, and inventory indexes. Cloud migration
`202609140004_owner_reporting.sql` adds the owner-only
`owner_report_summary(shop, start, end)` RPC; it does not grant direct writes.
All report windows are half-open UTC instants derived from Asia/Karachi dates.
