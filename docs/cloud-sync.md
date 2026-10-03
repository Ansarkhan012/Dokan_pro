# Cloud synchronization

## Push leasing

Sync schema version 3 adds lease owner, lease expiry, last-attempt time, next-attempt time, and an optional dependency operation ID. Claiming uses a Drift transaction and conditional update. Only one worker owns a live lease; expired `syncing` leases recover after crashes. Failure clears the lease, retains stable IDs/error/retry count, and applies bounded exponential backoff up to five minutes.

The worker owns no timer. It is invoked from startup, resume, connectivity hints, manual retry, or periodic foreground opportunities. A request result—not connectivity state—determines success. A dependent operation becomes eligible only after its referenced operation is synced.

## Failure handling (R1.5 / R1.6)

Every failed upload is classified from its stable code or exception type, never from message text (`lib/sync/sync_failure.dart`):

| Class | Examples | Outbox state |
| --- | --- | --- |
| connectivity | socket, DNS, TLS, timeout, `ClientException` | `failed` (retry-wait), backoff, retried without limit |
| transient | HTTP 5xx/408/429, `40001`, `40P01`, `55P03`, `57014`, `08xxx`, `53xxx` | `failed` (retry-wait), backoff, retried without limit |
| unknown | any other code or exception | `failed`; `needsAttention` after 5 attempts or 1 h |
| permanent | `DPV01` invalid/obsolete payload, `DPC01` conflicting replay, `DPX01` conflict not applied, legacy offset-less payload | `needsAttention` immediately |
| auth | `DPA01` inactive/foreign device or cashier, `42501`, expired session | `blockedAuth`; resumes once per new POS session or on owner Retry |

The four R1 sync RPCs raise these codes themselves (migration `202610020001`, one shared mapper `r1_raise_stable_sync_error`): sale, customer payment, void and return all emit `DPV01` for payload/contract validation, `DPC01` for a changed replay and `DPA01` for an inactive device or cashier; void emits `DPX01` for a second void or a void of a returned sale, return emits `DPX01` for a return of a voided sale or beyond the sold quantity. Approved record-and-flag cases not implemented yet (inactive customer, customer overpayment, out-of-window void) and a missing original sale keep their current SQLSTATE and are bounded as unknown.

`needsAttention` and `blockedAuth` operations are never picked up automatically and are never deleted; they keep the original payload plus `error_code`, a safe `attention_reason`, `attention_at` and the technical `last_error` (Drift v12). A dependant of a `needsAttention` operation needs attention too (`parent_needs_attention`). The owner's **Sync issues** screen lists them and offers Retry (re-queues the unchanged payload) only.

A sale the device accepted offline that breaks the credit limit on the server is recorded, not rejected: the sale RPC answers `accepted_flagged` with `flags` (also on an `already_synced` replay), the server keeps one `sync_exceptions` row, the device marks the operation synced and flagged, and the owner acknowledges it. The POS status chip shows `Needs attention` instead of `Synced` while anything is unresolved; cashiers see no codes.

`SyncWorker.runOnce` never throws: a lost lease leaves the operation to its new owner, and a local queue failure ends the run with every operation still leased or queued. Each runner has its own worker id (`uniqueSyncWorkerId`).

### Known follow-ups (not in R1.5 / R1.6)

- Record-and-flag for the remaining approved B-class cases (inactive customer, customer overpayment, out-of-window void); today they keep their SQLSTATE and are bounded as unknown (5 attempts or 1 h).
- `DPR01` missing-dependency policy (retry, `needs_attention` after 7 days or when the parent needs attention); a missing original sale is bounded as unknown today.
- Backend cashier/owner identity separation on shared devices (see [Cashier security](cashier-security.md)).
- Keyboard/sidebar overflow on the pilot tablet (see [QA pre-pilot](qa-pre-pilot.md)).

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
