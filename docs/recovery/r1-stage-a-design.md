# R1 Stage A — reproduction, contracts and migration plan

Status: **design only, awaiting approval.** No application behaviour, schema or
migration has been changed. Reproduction tests live in `test/r1_stage_a/` on the
local branch `r1/stage-a` and are expected to FAIL until the matching R1
substage lands.

R1 invariant: *one real checkout = exactly one financial sale*, and *all
authorised devices converge to the same financial, inventory and Udhaar state
once connected and synchronised*.

## 1. Reproduction harness

- Client: real Drift services on independent in-memory databases (one per
  simulated device).
- Server: the real 18 migrations applied from zero to a scratch database
  `r1_stage_a` inside the local Supabase container; RPCs and pull queries run
  as `authenticated` with the owner JWT `sub` claim (RLS and triggers active).
  The dev database is never touched; the scratch database is dropped after
  each file.
- Not exercised: the PostgREST/Kong HTTP hop (R1.7 adds one HTTP-level test on
  the ephemeral CI stack).
- Server tests run only with `--dart-define=R1_SERVER=true`.

## 2. Reproduced failures (all measured on 2026-09-30, Asia/Karachi device)

| ID | Test | Result |
| --- | --- | --- |
| F-1 data | `f1_checkout_durability_repro_test` | Lease lost after server success → `StateError` escapes `complete()`; sale committed; cart not cleared; retry committed a **second sale** (2 sale ids, 2 queue rows) |
| F-1 UI throw | same | "Nothing was charged" shown and Pay button re-armed after a committed sale |
| F-1 UI hang | same (run with `--plain-name hang`) | After 30 s simulated: "Completing…" still shown, no receipt |
| T-1 (NEW) | `t1_timestamp_shift_repro_test` | Real sale `04:59:26.256Z` stored on server as `09:59:26.000Z` (+4:59:59.7). Queued payload `2026-09-30T09:59:26.000` (local, no offset) → normaliser appends `Z` |
| F-2 | `f2_void_convergence_repro_test` | Stock opening/sale/localVoid/afterPull/server = 10000/8000/10000/**12000**/10000; Udhaar 36000/0/**-36000**/0; 2 `returnIn` and 2 `refund` rows; local vs server compensation ids differ |
| O-2 A | `o2_pull_cursor_repro_test` | B cursor `05:01:30Z`; late sale created `03:01:30Z` on server but never pulled; B stock 9000 vs server 8000 |
| O-2 B | same | Future row moved B cursor to `2026-10-01T05:01:35Z`; next normal sale never pulled; B 9000 vs server 8000 |
| F-3 zero | `f3_permanent_rejection_repro_test` | Local Rs 0 sale committed; server `invalid sale payment`; 6 retries, still eligible after 30 days |
| F-3 credit | same | Two offline Rs 180 Udhaar sales vs Rs 300 limit; B rejected `customer credit limit exceeded`; 6 retries, still eligible after 30 days; B device Udhaar 18000 never reaches server |

### New finding T-1 (timestamp shift) — CRITICAL

Drift stores `DateTime` as Unix seconds and reads it back as a *local*
`DateTime`. `LocalSaleService._aggregatePayload` (and
`LocalPurchaseService`) serialise with `toJson(serializeDateTimeValuesAsString)`,
producing local wall-clock strings without an offset.
`normalizeSalePayloadForCloud` rebuilds them with `DateTime.utc(<local
fields>)`, so a UTC+05:00 device records every sale 5 h in the future and
drops sub-second precision. Purchases are not normalised; PostgreSQL reads the
offset-less string as UTC → same shift (code evidence; not executed).
Consequences: every void of a synced sale is rejected ("void correction window
expired") on Pakistani devices, so F-2 is currently masked by a permanent void
failure; sale-derived pull cursors jump 5 h ahead (amplifies O-2); cloud
reports are shifted. CI runs in UTC, which hides it.

### O-6 evidence

`SyncWorker.runOnce` escapes with `StateError` when `completeLease` fails and
`failLease` then also fails (reproduced in F-1 data). Lease loss is realistic:
the lease is 2 minutes and `client.rpc` has no timeout.

## 3. Checkout commit contract

```
editing ──tap Complete──► local_committing ──Drift txn commits──► locally_committed  ◄── POINT OF NO RETURN
   ▲                            │ validation/DB error (txn rolled back)        │
   └──── "Sale not saved" ◄─────┘                                              ▼
                                                   cart cleared + receipt shown (same frame)
                                                                               ▼
                                                     sync_pending (background, non-blocking)
                                                        │ success/already_synced       │ permanent code
                                                        ▼                              ▼
                                                     synced                     needs_attention
```

- **Point of no return:** the Drift transaction that inserts sale, items,
  payments, movements, ledger, audit and outbox commits.
- **Idempotent commit:** the payment dialog mints a `checkoutId` (the future
  `sale.id`) once per confirmation. `createSale` accepts it; if a sale with that
  id already exists for the shop, it returns the existing sale instead of
  inserting. A double tap or an ambiguous retry cannot create a second sale.
- **Cart clears / receipt available:** immediately after the commit returns,
  before any network call. `complete()` returns `CreatedSale` from the local
  commit only; sync is started with `unawaited` and its outcome never reaches
  the checkout error path.
- **Sync call:** bounded per RPC (15 s timeout); outcome feeds the pending
  badge only.
- **Process dies after commit:** nothing to undo. On restart the POS shows a
  "Last sale saved on this device: Rs X at hh:mm — Reprint" banner (latest sale
  of this device within 30 minutes) so the cashier does not re-ring.
- **Messages:** pre-commit failure → "Sale not saved. Nothing was recorded."
  Pending → "Saved on this device · will sync when online". Permanent →
  "Saved on this device · owner review needed" (no alarm to the customer).

## 4. Void identity (F-2) — choose Option A

| | A: client ids in payload, server validates | B: ids derived (UUIDv5 of void id + sale item id) |
| --- | --- | --- |
| Idempotency / replay | void id advisory lock + fingerprint (existing) | same |
| Consistency with codebase | matches sales, returns, purchases (all client ids) | new cross-language hashing contract |
| Malicious payload | server maps ids to its own `sale_items`; recomputes quantity/product/amount; rejects duplicate or foreign ids (PK/unique) | no attacker-chosen ids |
| Existing rows | repair must match by `(reference_id, product_id)` | repair can recompute ids |
| Migration | new RPC version, payload v2 | RPC change + `uuid_generate_v5` + Dart v5 |

**Decision: Option A.** Payload v2 adds `movement_ids: {sale_item_id: uuid}`
covering every sale item exactly once, and `refund_ledger_id` present iff the
server finds a credit payment. The server uses only the ids from the client;
product, quantity, customer and amount come from the server's own
`sale_items`/`sale_payments`. The fingerprint covers the ids, so an exact replay
returns `already_synced` and a changed replay is a permanent conflict.
Returns already follow this pattern.

## 5. Server-assigned sync order (O-2)

### Options

1. **Global `bigserial`/sequence:** unsafe on its own. Transaction A takes N,
   B takes N+1, B commits, a reader returns N+1 and advances the cursor past N,
   then A commits: A is skipped forever.
2. **Global sequence + `xmin` horizon:** return only rows whose writing
   transaction id is below `pg_snapshot_xmin(pg_current_snapshot())`. Correct,
   but any long-running transaction in the database delays every shop's pull,
   and pull must be an RPC.
3. **Per-shop transactional counter (chosen):** `shop_sync_state(shop_id,
   last_seq)`. The first write of a transaction for a shop runs
   `UPDATE … SET last_seq = last_seq + 1 RETURNING last_seq` and caches the
   value in a transaction-local setting; every row that transaction writes for
   that shop gets the same `server_seq`. A row lock is held until commit.

### Commit-order proof for option 3

- A locks the shop row and takes N. B, for the same shop, blocks on that row
  lock until A commits or aborts; only then does it take N+1. Therefore
  commit(A) happens before seq(B) is even assigned, so within a shop seq
  order equals commit order.
- A reader's statement snapshot therefore always sees a *prefix* of each
  shop's committed sequence: if it sees N+1 it already sees N (or N was
  aborted and will never appear). The cursor `(server_seq, id) > (last)` can
  never skip a row that commits later.
- Aborted transactions leave gaps; the cursor is `>` so gaps are harmless.
- Rows of one transaction share a seq; `id` breaks ties for pagination.
- Updates of mutable rows (prices, customers) get a new seq and are re-pulled;
  application is an idempotent upsert by id.
- **Lock ordering rule:** every sync RPC calls `next_sync_seq(shop)` as its
  first write, before advisory locks, so it cannot deadlock with the
  credit/overpayment advisory locks. Any residual deadlock (40P01) is
  classified transient.
- Contention is per shop only (2–5 devices); the checkout RPC holds it for
  ~8 ms (measured RPC cost), so no cross-shop contention at 5,000 shops.
- Global reference rows (`categories` with null shop, `master_products`) use a
  single-row `global_sync_state` with the same pattern (writes are rare,
  admin-only).

Client clocks become irrelevant for ordering; `created_at` stays business time
only. `received_at timestamptz default now()` records ingestion time.

## 6. Permanent-error model

Server RPCs raise a stable custom SQLSTATE plus JSON `detail`; the client
classifies by `code`, never by message text.

| Class | Codes | Client action |
| --- | --- | --- |
| Transient | network/timeout, HTTP 5xx/408/429, `40001`, `40P01`, `55P03`, `57014`, `DPR01` (dependency not yet on server) | `retry_wait` with capped backoff |
| Idempotent success | RPC status `already_synced` | `synced` |
| Accepted with flags | RPC status `accepted_flagged` | `synced` + owner exception list |
| Auth blocked | `42501`, `DPA01` | `retry_wait` long backoff + "sign-in required"; not poison |
| Permanent | `DPV01` invalid payload, `DPC01` conflicting replay, `DPX01` business conflict that cannot be applied (e.g. double void) | `needs_attention`, never auto-retried |
| Unknown | anything else | `retry_wait`; after 24 h flag as "stuck" but keep retrying |

Local queue states: `pending`, `leased` (today's `syncing`), `retry_wait`
(today's `failed`), `synced`, `needs_attention`. Financial rows are never
deleted because sync failed. The owner can retry or acknowledge an item.

## 7. Offline fact vs server policy

A = invalid financial fact (must never have been committed locally; fix the
client). B = valid offline fact that violates a policy (record and flag).

| Condition | Local check | Server check | Type | Retry? | Server action (proposed) | Local reconciliation | Owner sees |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Zero-amount payment row | allows 0 | rejects ≤0 | A (contract) | no | reject `DPV01` | client no longer emits 0 rows (§8) | nothing |
| Totals/line mismatch, bad movement, bad ledger | recomputed | recomputed | A | no | reject `DPV01` | `needs_attention` (bug) | alert |
| Conflicting replay | n/a | hash differs | A | no | reject `DPC01` | `needs_attention` | alert |
| Credit limit exceeded (cross-device) | per device | trigger | B | — | **accept, flag** `credit_limit_exceeded` | `synced` | exception list |
| Customer overpayment (cross-device) | per device | trigger | B | — | **accept, flag** `overpayment` (balance may go negative) | `synced` | exception list |
| Customer deactivated while offline | active check | active check | B | — | accept, flag | `synced` | exception list |
| Negative stock on adjustment (policy off) | per device | check | B | — | accept, flag | `synced` | exception list |
| Void outside 15 min (client clocks) | local check | check | B | — | accept, flag (window uses untrusted clocks) | `synced` | exception list |
| Void/return before sale on server | none | "original sale required" | transient | yes | `DPR01` | `retry_wait` + dependency | nothing |
| Double void of one sale (two devices) | per device | unique | B, cannot apply twice | no | `DPX01`, not applied | `needs_attention`; local compensation shown as unconfirmed | decision |
| Return beyond sold qty (two devices) | per device | check | B, cannot apply as stock | no | `DPX01` | `needs_attention` | decision |
| Return of voided sale / void of returned sale | per device | check | B | no | `DPX01` | `needs_attention` | decision |
| Device revoked / cashier deactivated while offline | local | check | security (R2) | no | keep reject (`DPA01`) | `retry_wait` long, then attention | alert |
| Owner membership inactive | n/a | check | auth | long | `DPA01` | auth-blocked | sign-in |

No class results in silent financial loss: every non-applied fact stays on the
device and is surfaced.

## 8. Zero-payment contract

A zero-total sale is legitimate (free carrier bag, zero-priced item, future
100% discount): goods leave the shop and stock must move. Contract:
**every payment row amount > 0; a sale with `grand_total = 0` has no payment
rows.** Server already accepts this (payment sum 0 = total 0; the row check
applies only to rows present), so **no server change**. Client changes:
`LocalSaleService` rejects any payment row ≤ 0 and allows an empty payment list
only when `grand_total = 0`; the POS builds no payment row for a Rs 0 total.

## 9. Dependency ordering

Populate `dependsOnOperationId` (already honoured by `acquireLease`) when a
void or return references a sale whose `sale_aggregate` operation is not yet
`synced` on this device. Server backstop: "original sale required" becomes
transient `DPR01`. If the parent reaches `needs_attention`, the dependent is
shown with it. Customer payments need no dependency once overpayment is
accept-and-flag.

## 10. Convergence definition and test matrix

Converged = for a shop, every device's projection equals the server's for:
sale existence and status (incl. void/return state), sale items, payments,
returned quantities, inventory movement ids and per-product stock, customer
ledger ids and Udhaar balance.

| # | Scenario | Devices | Expected |
| --- | --- | --- | --- |
| 1 | A sale → B pull | A,B | B has sale, movements, ledger |
| 2 | A offline sale (old `created_at`) → late upload → B pull | A,B | B receives (O-2 A) |
| 3 | A future clock → B pull → normal sale → B pull | A,B | B receives both (O-2 B) |
| 4 | A sale → A void → sync → pull (A and B) | A,B | stock/Udhaar = pre-sale on both (F-2) |
| 5 | A sale → B return | A,B | both converge |
| 6 | Duplicate upload ×10, concurrent | A | one aggregate |
| 7 | Response lost after server commit | A | retry `already_synced` |
| 8 | Retry storm across restarts | A | one aggregate |
| 9 | UTC+05:00 device | A | server `created_at` = real instant (T-1) |
| 10 | Server restart mid-sync | A | transient, then synced |
| 11 | Client restart after commit before sync | A | no loss, one sale |
| 12 | Transient network failure | A | retry_wait → synced |
| 13 | Permanent conflict (zero row, conflicting replay) | A | needs_attention, no retry |
| 14 | Credit limit exceeded across devices | A,B | accepted + flagged; balances converge |
| 15 | Double void on two devices | A,B | one applied, other needs_attention |

## 11. Proposed PostgreSQL migrations (new, forward-only)

1. `…_r1_sync_order.sql`
   - `shop_sync_state(shop_id uuid pk references shops on delete cascade,
     last_seq bigint not null default 0)`, `global_sync_state` (single row).
   - `next_sync_seq(shop)` security definer, `search_path` pinned, no client
     EXECUTE; transaction-local cache.
   - `server_seq bigint` (nullable at first) and `received_at timestamptz
     default now()` on every pulled table; `BEFORE INSERT OR UPDATE` trigger
     sets `server_seq` (clients cannot write it: not in column grants, and the
     trigger overwrites).
   - Backfill per shop ordered by `(created_at|updated_at, id)`; set
     `shop_sync_state.last_seq`; then `SET NOT NULL`.
   - Indexes `(shop_id, server_seq, id)` on each pulled table.
2. `…_r1_void_identity.sql` — `sync_sale_void` v2 (client ids validated,
   server-derived amounts); v1 handling per decision Q3.
3. `…_r1_sync_codes_and_flags.sql` — `sync_exceptions` table (owner-select RLS,
   no client writes); coded errors in every sync RPC; credit-limit and
   overpayment triggers record a flag instead of raising when invoked from a
   sync RPC; `next_sync_seq` first in each RPC.

Production-sized note: for large tables, backfill in batches and build indexes
with `CREATE INDEX CONCURRENTLY` in a separate non-transactional migration.
Pre-pilot volumes (2 dev sales) allow in-transaction creation. Old clients keep
working: they still pull by `created_at` and never see `server_seq`.
Rollback: forward-fix only; the new columns and tables are additive.

## 12. Proposed Drift migration (schema v11, one bump)

- `sync_operations`: add `error_code` (text), `attention_at` (datetime);
  status values gain `retryWait`, `needsAttention`; `UPDATE … SET status =
  'retryWait' WHERE status = 'failed'`.
- `sync_cursors`: add `server_seq` (int, nullable); on upgrade delete cursors of
  financial entities → one full, idempotent re-pull.
- Timestamps stay Unix seconds; payloads serialise `toUtc().toIso8601String()`
  explicitly (T-1).
- Commit `drift_schema_v11.json` + generated schema; first real upgrade test
  v10→v11 with financial rows (also closes part of R4 early).

## 13. Existing-data detection → dry-run → repair → verify

Read-only detection:

```sql
-- Server: T-1 shifted rows (sale recorded in the future relative to ingestion)
select id, created_at, synced_at, created_at - synced_at as skew
from sales where created_at > synced_at + interval '1 minute';
-- Server: void compensation count vs sale items
select v.id, (select count(*) from sale_items i where i.sale_id = v.original_sale_id) items,
       (select count(*) from inventory_movements m where m.reference_id = v.id) moves
from sale_voids v;
-- After R1.4: rows without order
select 'sales', count(*) from sales where server_seq is null;  -- repeat per table
```

```sql
-- Device (Drift): duplicated void compensation
select reference_id, product_id, count(*), group_concat(id)
from inventory_movements where reference_type = 'sale_void'
group by reference_id, product_id having count(*) > 1;
select sale_id, count(*), group_concat(id) from customer_ledger_entries
where type = 'refund' and sale_id in (select original_sale_id from sale_voids)
group by sale_id having count(*) > 1;
```

Repair (not run in Stage A): device duplicates → remove the local-only row
whose id does not exist on the server and whose `(reference_id, product_id)`
matches a server row (a local copy error, not history), inside one transaction
with an audit row. Server T-1 rows → subtract the device offset only for rows
matching the skew signature; dry-run report first; verification by re-running
detection and the convergence suite.

## 14. Performance

- Pull: `WHERE shop_id = $1 AND (server_seq > $2 OR (server_seq = $2 AND id > $3))
  ORDER BY server_seq, id LIMIT 100` → range scan on `(shop_id, server_seq, id)`,
  bounded per page and independent of other tenants (fixes the measured
  sequential scan on `sale_payments`).
- Write cost: one counter-row update per transaction (cached), one extra btree
  per pulled table; to be measured with the existing pgbench harness before
  and after (target: checkout RPC within +15% of 7.7 ms).
- No new per-event round trips; the flag model removes endless retries.
- Partitioning stays in R6.

## 15. Security

Unchanged: tenant RLS, composite tenant FKs, server recomputation, advisory
locks + fingerprints, no service key in Flutter. `server_seq` is server-only;
client ids are identity only; `sync_exceptions` is owner-read-only; error
`detail` never includes another tenant's data (the current "sale id belongs to
another shop" message becomes a generic `DPV01`). S-1/S-2/S-4 stay in R2.

## 16. Implementation substages

| Substage | Failing test first | Main files | Migration | Exit criteria |
| --- | --- | --- | --- | --- |
| R1.0 Harness in CI | — | `test/r1_stage_a/harness.dart` → `test/integration/`, CI job on the ephemeral stack | none | server tests run in CI |
| R1.1 Checkout durability + zero contract | F-1 (3), F-3 zero | `pos_runtime_native.dart`, `pos_workspace.dart`, `pos_state.dart`, `local_sale_service.dart` | none | F-1 tests green; one sale per checkout |
| R1.2 Timestamp integrity (T-1) | T-1 | `local_sale_service.dart`, `local_purchase_service.dart`, `sale_payload_codec.dart` | none | T-1 green on UTC+05:00 |
| R1.3 Void convergence | F-2 | `local_sale_void_service.dart`, dependency ids | `_r1_void_identity` | F-2 green; scenario 4 |
| R1.4 Server ordering | O-2 A/B | pull gateway/service, cursors | `_r1_sync_order`, Drift v11 | O-2 green; EXPLAIN shows index range scan |
| R1.5 Error model + flags | F-3 credit, permanent cases | sync worker/queue, RPCs, needs-attention list | `_r1_sync_codes_and_flags` | F-3 green; no infinite retry |
| R1.6 Lifecycle (O-6 minimum) | runOnce throw | `sync_worker.dart`, `sync_queue_repository.dart` | none | no escape; per-RPC timeout |
| R1.7 Convergence suite + repair dry-run | matrix §10 | integration tests, detection scripts | none | full matrix green in CI |

## 17. Decisions requiring approval

1. Record-and-flag for credit limit, overpayment, inactive customer, negative
   stock and out-of-window voids (vs rejecting).
2. Double void / over-return / void-vs-return conflicts → not applied,
   `needs_attention`.
3. v1 void payloads: reject as `DPV01` (recommended pre-pilot) or accept with
   legacy server-generated ids flagged.
4. Zero-total sale allowed with no payment rows.
5. Per-shop transactional counter for `server_seq`.
6. Include T-1 in R1 (recommended: it blocks F-2 and corrupts ordering).
7. One full re-pull of financial entities on the v11 upgrade.
8. Existing dev data (2 sales, likely +5 h shifted): repair script vs leave.
9. New CI job running server integration tests in the ephemeral stack.
