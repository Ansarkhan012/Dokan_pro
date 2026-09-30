# Cloud synchronization

## Push leasing

Sync schema version 3 adds lease owner, lease expiry, last-attempt time, next-attempt time, and an optional dependency operation ID. Claiming uses a Drift transaction and conditional update. Only one worker owns a live lease; expired `syncing` leases recover after crashes. Failure clears the lease, retains stable IDs/error/retry count, and applies bounded exponential backoff up to five minutes.

The worker owns no timer. It is invoked from startup, resume, connectivity hints, manual retry, or periodic foreground opportunities. A request result—not connectivity state—determines success. A dependent operation becomes eligible only after its referenced operation is synced.

## Sale idempotency

The server takes a transaction advisory lock derived from sale UUID. It hashes PostgreSQL `jsonb::text` with SHA-256 and stores the fingerprint. JSONB object keys are canonicalized; array order is significant. Exact replay returns `already_synced`; the same UUID with altered aggregate data is rejected. Pre-fingerprint legacy sales fail closed.

The sale RPC accepts an active Supabase owner or valid cashier session. Cashier/shop/device context is derived and verified from the token, so arbitrary payload cashier IDs are not trusted.

## Pull synchronization

Initial pull covers shop configuration, devices, cashier metadata, categories, master products, shop products, and customers. Each entity has a durable `(updated_at, UUID)` cursor and ordered query, avoiding equal-timestamp gaps. A page and cursor apply in one local transaction. Tenant checks reject foreign records.

Deactivation uses `is_active`; rows are retained rather than deleted. Add `deleted_at` tombstones before permanent deletion is needed.

## Conflict ownership

- Cloud/owner controls configuration, activation, prices, and customer profile fields.
- Completed sale aggregates are immutable device-created records once accepted.
- Inventory merges append-only movements, never a last-write-wins stock value.
- Customer balances remain ledger-derived; profile fields synchronize separately.
