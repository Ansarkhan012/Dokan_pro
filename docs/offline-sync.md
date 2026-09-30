# Offline synchronization

## Local-first write path

1. Validate the active shop and role.
2. Commit the business rows, append-only accounting/inventory effects, audit entry, and sync operation in one local SQLite transaction.
3. Update the UI from the local database immediately.
4. A background coordinator claims `pending`/retryable `failed` operations, marks each `syncing`, sends it later, then marks `synced` or `failed` with an incremented retry count.

The Phase 0 `SyncService` is intentionally offline-only and performs no fake network calls. Queue IDs and entity UUIDs remain stable across retries so the future server can implement idempotent upserts and transaction de-duplication. Payloads are JSON text today; versioned payload envelopes should be introduced with the real protocol.

## Conflict policy

Product data uses server-approved versioning/updated timestamps in Phase 1. If Coke changes from Rs 180 to Rs 190 while a counter is offline, the already committed sale item stays Rs 180. After the product update synchronizes, future drafts use Rs 190.

Inventory movements are never silently removed or rewritten. Concurrent offline counters may yield negative derived stock. The server preserves both movements and flags reconciliation for the owner. A correction is a new movement with an audit trail.

Completed sales do not normally generate delete operations. Void, return, and refund workflows use status transitions and compensating records. Queue claiming must be transactional; interrupted `syncing` entries will later be recovered using a lease/timeout policy.

## Security boundary

Local repository scoping prevents accidental cross-shop reads. It is not a cloud security boundary. Phase 1 PostgreSQL tables require RLS policies based on authenticated membership, and Storage paths/policies must be tenant scoped. The mobile client receives only the anon key.

## Phase 1 sale contract

One versioned JSON operation contains the complete sale aggregate: sale, snapshot items, payments, inventory movements, credit ledger entries, and audit metadata. The adapter calls `sync_sale_transaction`; domain rules do not depend on the Supabase SDK. Queue and entity UUIDs remain stable through `failed -> pending -> syncing`, so retries cannot create a new sale identity.

The RPC authorizes the owner, validates active device and actor, checks payment/credit integrity, and writes all rows in one PostgreSQL transaction. An existing sale UUID returns `already_synced` before child inserts. Connectivity hints may trigger attempts, but only a successful RPC response marks an operation synced.

Phase 2A supersedes the simple retry path with durable leases, bounded backoff, dependency gating, and deterministic reference-data pulls. See [Cloud sync](cloud-sync.md) and [Cashier security](cashier-security.md).

## Product reference data

Categories, master products, shop products, and inventory movements are pulled
incrementally into Drift. My Products and POS then read only the local
projection and remain usable offline. The initial add/custom-product workflow
requires the backend: its owner-only RPC commits product identity, opening
movement, and audit atomically, after which the same reference pull refreshes
both owner management and POS. Queueing product-management commands is reserved
for a later phase.

## Customer payments

Receiving a customer payment commits the `paymentReceived` ledger entry, audit
row, and one `customer_payment` queue operation in a single Drift transaction.
The UI derives the reduced balance immediately. The existing leased worker
dispatches the versioned payload to `sync_customer_payment`; stable ledger and
audit UUIDs plus a payload fingerprint make retries idempotent. A server reply,
not connectivity state, is what marks the queue row synced. Customer and ledger
reference pulls use deterministic `(created_at, id)` ordering for immutable
ledger history, so Khata search and statements remain available offline.

## Purchase aggregates

A purchase, its item snapshots, cash/digital payments, positive stock
movements, unpaid supplier-ledger amount, audit, and queue operation commit in
one Drift transaction. The existing worker dispatches the envelope to
`sync_purchase_transaction`. Supplier payments use `sync_supplier_payment`.
Both RPCs fingerprint payloads: identical UUID retries return `already_synced`
and changed replays fail. Only successful RPC responses complete queue leases.

## Expenses

An expense, audit row, and one `expense` queue operation commit atomically in
Drift. `sync_expense` requires an active owner and device, then fingerprints
and inserts the immutable cloud row. Exact retries are harmless and changed
payloads using the same UUID are rejected.
# Dashboard freshness

Owner reports are computed from the local Drift history and therefore work
offline. They include this device's locally committed operations immediately.
Until queued operations and reference pulls complete, another device's newest
transactions may not yet be represented; the dashboard surfaces that cached
state rather than presenting local data as globally current.
