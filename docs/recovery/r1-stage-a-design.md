# R1 Stage A — revised design (reproduction, contracts, migration plan)

Status: **design only, awaiting final approval.** No application behaviour,
schema or migration has changed. Artifacts live on the local branch
`r1/stage-a`: failing reproduction tests in `test/r1_stage_a/` and the
`server_seq` prototype in `test/r1_stage_a/server_seq_prototype/`.

R1 invariant: *one real checkout = exactly one financial sale*; once connected
and synchronised, every authorised device converges to the same financial,
inventory and Udhaar state.

---

## A. Accepted reproductions

Accepted as evidence (not re-proved): **F-1** checkout durability, **F-2** void
compensation identity divergence, **O-2** late-upload and future-clock cursor
skips, **F-3/O-4** permanent-rejection retry loop, **O-6** lease-error escape,
**T-1** timezone corruption (UTC+05:00 sales stored +4 h 59 m 59.7 s; both dev
sales show the skew). T-1 is in R1 and is fixed before any void work.

New sub-finding recorded during this revision, **T-1b** (code evidence):
`sync_cursors.updated_at` is a Drift `DateTime` stored as Unix **seconds**,
while server timestamps carry microseconds. After each page the cursor is
truncated, so rows in the same second are fetched again; a page of ≥100 rows
inside one second loops forever. Resolved by the integer `server_seq` cursor
(§E) — no timestamp is used as a cursor after R1.

## B. Revised checkout contract

```
editing ─► local_committing ─► locally_committed ─► cart cleared + receipt
               │ rollback                   │
               ▼                            └─► worker wake-up signal (not awaited)
       "Sale not saved"                                   │
                                     background worker ─► synced | retry_wait | blocked_auth | needs_attention
```

**Success definition.** Checkout succeeds when the single Drift transaction
containing sale, items, payments, inventory movements, customer ledger (if any),
audit and the outbox operation commits. Nothing after that commit can change the
checkout result.

**Implementation.**

1. `PaymentDialog` confirmation mints `checkoutId = UuidV7Generator().next()`
   **before** calling the committer; the POS keeps it in widget state for the
   current cart until the cart is cleared.
2. `LocalSaleService.createSale(draft)` takes `draft.saleId = checkoutId` (new
   required field). Inside the transaction, first statement: look up
   `sales where id = checkoutId and shop_id = draft.shopId`.
   - absent → normal insert (uses `checkoutId` as `sale.id`);
   - present and its **fingerprint** (canonical JSON of shop, device, cashier,
     customer, line product ids/quantities/discounts, payment methods/amounts)
     equals the draft's → return the existing `CreatedSale` (idempotent, no
     writes);
   - present with a different fingerprint → throw `CheckoutConflict` (hard
     local conflict; nothing written; logged).
   The fingerprint is stored in a new `sales.checkout_fingerprint` column (Drift
   v11) so the comparison never re-derives from mutable product prices.
3. `_NativeSaleCommitter.complete()` = `await createSale(...)` then
   `_worker.wake()` and **return**. `wake()` is synchronous and non-throwing:
   it sets a flag / schedules a microtask on a single long-lived
   `SyncWorkerRunner`; the committer never awaits it. `lastSyncSucceeded` is
   removed from the checkout path; the pending badge observes the queue.
4. `PosCheckoutController.complete` clears the cart as soon as `commit()`
   returns; the receipt dialog is shown from `CreatedSale` (local data only).
5. Error mapping in `pos_workspace.checkout`: only exceptions thrown **before**
   the transaction commits can reach the catch block (validation,
   `CheckoutConflict`, database failure), and they map to
   "Sale not saved. Nothing was recorded."
6. The RPC timeout (15 s per call) lives in `SyncWorkerRunner`, never in
   checkout. One runner per POS runtime with a unique `workerId`
   (`device-<id>-<uuid>`), one DB instance (§P R1.6).
7. Double tap: `completing` flag (existing) + idempotent `checkoutId`; a second
   invocation with the same id returns the same sale.
8. Process death after commit: on POS start, `LastSaleRecovery` reads the
   newest sale for this device created within 30 minutes and shows
   "Last sale saved on this device: Rs X at hh:mm — Reprint". The cart was
   in memory and is not restored (no duplicate path).

**R1.1 tests (added to the existing F-1 reproductions):** commit then gateway
throws → receipt, cart cleared, one sale; gateway hangs → receipt within one
frame; same `checkoutId` twice with same content → one sale, same id; same id
with different lines → `CheckoutConflict`, no rows; rapid double tap on
"Complete Sale" → one sale; kill after commit (reopen DB) → last-sale banner
shows that sale; zero-total cases (§J).

## C. Timestamp boundary inventory and canonical codec

### Inventory (every synchronised timestamp)

| Direction | Entity / field | Current code | Status |
| --- | --- | --- | --- |
| Drift → payload | sale aggregate: `sale.createdAt`, `sale.syncedAt`, `sale_items[].createdAt`, `payments[].createdAt`, `inventory_movements[].createdAt`, `customer_ledger_entries[].createdAt` | Drift `toJson(serializeDateTimeValuesAsString)` of values read back from Drift (local `DateTime`) → offset-less local string | **Defect (T-1)** |
| payload → server | same, via `normalizeSalePayloadForCloud` | rebuilds `DateTime.utc(<local fields>)` | **Defect (T-1)** |
| Drift → payload | purchase aggregate: `purchase.createdAt`, `purchase_items`, `payments`, `inventory_movements`, `supplier_ledger_entries` `createdAt` | same `toJson`; not normalised; PostgreSQL reads offset-less text in session time zone (UTC) | **Defect (T-1)** |
| payload | customer payment `entry.created_at`, `audit.created_at` | `now.toUtc().toIso8601String()` → `…Z` | correct |
| payload | supplier payment `entry/audit.created_at` | same | correct |
| payload | expense `expense_at`, `created_at` | `toUtc().toIso8601String()` | correct |
| payload | inventory adjustment `movement/audit.created_at` | same | correct |
| payload | void `void.created_at`; server derives compensation `created_at` from it | same | correct |
| payload | return `return.created_at`; server derives items/movements/ledger | same | correct |
| server | `synced_at`, audit/product `created_at` via `now()` | server clock | correct |
| server → pull | every `created_at`, `updated_at`, `last_seen_at`, `last_synced_at`, `synced_at`, `expense_at` | JSON with offset; `DateTime.parse(..).toUtc()` | correct instant; stored in Drift as Unix seconds (sub-second loss) |
| cursor | `sync_cursors.updated_at` | Drift seconds; sent as `toUtc().toIso8601String()` | **Defect (T-1b)** |
| local business rules | void window, reports (fixed +05:00), entitlement clock | `toUtc()` comparisons | correct |
| online RPCs | product create, customer/supplier save, settings | server `now()` | correct |

### One boundary: `lib/sync/sync_time.dart`

```dart
abstract final class SyncTime {
  /// Only way an instant leaves the device: always UTC, always ends with 'Z'.
  static String encode(DateTime instant) => instant.toUtc().toIso8601String();
  /// Only way an instant enters from the server: requires an explicit offset
  /// or 'Z'; throws FormatException for offset-less text.
  static DateTime decode(String text);
}
```

- Every payload builder uses `SyncTime.encode` (sale and purchase aggregates stop
  using Drift `toJson` for timestamps; the other five already match and switch to
  the codec for uniformity).
- `normalizeSalePayloadForCloud` is deleted; no code path may turn an
  offset-less wall-clock string into UTC.
- Pull uses `SyncTime.decode`; cursors become integers (§E), so no timestamp is
  a cursor.
- Legacy queued v1 sale/purchase payloads (offset-less) are not rewritten: the
  v11 upgrade marks any such **unsynced** operation `needs_attention` with
  reason `legacy_timestamp_payload` (inventory §K: currently zero exist), because
  rewriting would change the server fingerprint and guessing the zone is
  unsafe.
- No historical timestamp is repaired in R1.

**Tests:** codec unit tests run under both `TZ=UTC` and `TZ=Asia/Karachi`
(encode of a local `DateTime` is the same instant with `Z`; decode rejects
offset-less input; Drift round trip keeps the instant to the second). The T-1
integration test runs in CI twice with an explicit environment:
`TZ=UTC flutter test --tags tz` and `TZ=Asia/Karachi flutter test --tags tz`
(the Dart VM honours `TZ` on Linux); the job asserts
`DateTime.now().timeZoneOffset == 5h` in the Karachi run so a silently ignored
`TZ` fails the job.

## D. Integration-test architecture

Two layers, both only against local/ephemeral stacks:

1. **Direct-DB layer (fast, deterministic)** — the Stage A harness (scratch
   database with all migrations, RPCs as `authenticated` with a JWT claim).
   Used for server rule coverage and concurrency (§F).
2. **HTTP layer (new in R1.0)** — real PostgREST/Kong/GoTrue of the
   **ephemeral CI stack** (`supabase start` in the job; locally a developer may
   point it at their own local stack). Uses the production gateway classes
   unchanged: `SupabaseClient(url, anonKey)` from `package:supabase`,
   `SupabaseSaleUploadGateway`, `SupabaseReferencePullGateway`,
   `ReferencePullService`, `SyncWorker`.
   - Setup per test through public APIs only: `auth.signUp` (owner; sign-up is
     enabled and confirmation disabled in `config.toml`), `create_owner_shop`,
     `register_shop_device`, `create_custom_shop_product`, `save_customer`.
     No service-role key.
   - Config from `supabase status -o env` (`API_URL`, `ANON_KEY`) via
     `--dart-define`; the harness refuses to run unless the URL host is
     `127.0.0.1`/`localhost`.
   - Cases: sale upload; idempotent replay (`already_synced`); void upload
     (v2); pull through PostgREST with the `server_seq` cursor; error mapping —
     a zero-amount payment row returns `PostgrestException.code == 'DPV01'`
     classified `permanent`; conflicting replay → `DPC01`; credit limit
     exceeded across two owner sessions → `accepted_flagged` with the exception
     row visible to the owner; revoked device → `DPA01` → `blocked_auth`.
   - CI: a new job `integration` (Flutter + Supabase CLI, same pins) runs both
     layers plus the TZ matrix.

## E. `server_seq` allocation mechanism (exact)

Granularity: **one value per (mutation transaction, shop)**, shared by every row
that transaction inserts or updates for that shop; `id` breaks ties.

Objects (new migration `…_r1_sync_order.sql`):

```sql
create table public.shop_sync_state(
  shop_id uuid primary key references public.shops(id) on delete cascade,
  last_seq bigint not null);
create table public.global_sync_state(
  singleton boolean primary key default true check (singleton),
  last_seq bigint not null);
-- RLS enabled, no policies, no grants to anon/authenticated.

create function public.sync_begin(p_shop uuid) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  k text := 'dukaan.sync_seq_' || coalesce(replace(p_shop::text,'-',''), 'global');
  cached text := current_setting(k, true);
  tx text := txid_current()::text;
  s bigint;
begin
  if cached is not null and cached <> '' and split_part(cached, ':', 1) = tx then
    return split_part(cached, ':', 2)::bigint;          -- same transaction: reuse
  end if;
  if p_shop is null then
    update global_sync_state set last_seq = last_seq + 1 returning last_seq into s;
  else
    insert into shop_sync_state values (p_shop, 1)
      on conflict (shop_id) do update set last_seq = shop_sync_state.last_seq + 1
      returning last_seq into s;                        -- row lock until commit
  end if;
  perform set_config(k, tx || ':' || s, true);          -- transaction-local
  return s;
end $$;
revoke all on function public.sync_begin(uuid) from public, anon, authenticated;

create function public.assign_server_seq() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.server_seq := public.sync_begin(<shop key of this table>);  -- always overwrites
  return new;
end $$;
-- BEFORE INSERT OR UPDATE trigger named a00_server_seq on each table in §G
-- (a00_ fires before every existing BEFORE trigger, see lock ordering below).
```

- **Allocation point:** each R1 sync RPC calls `perform sync_begin(shop)`
  explicitly *after* its entity advisory lock and idempotency check and *before*
  its first insert or any other lock.
- **Propagation:** every subsequent insert/update in that transaction reaches
  `a00_server_seq`, which calls `sync_begin` and gets the cached value (same
  `txid`). One counter update per transaction per shop.
- **Client-supplied values:** ignored — the trigger overwrites `NEW.server_seq`
  unconditionally, the column is absent from all column-level UPDATE grants, and
  the cache is keyed by `txid`, so a forged or session-level setting is never
  reused (prototype: forged `1:999999` ignored, got 5).
- **Direct/legacy writes** (owner PostgREST inserts/updates of products,
  customers, categories, devices; old-client RPCs): the trigger allocates on the
  first row — same semantics, same lock.
- **Idempotent replay:** the RPC returns `already_synced` before `sync_begin`,
  so no value is consumed and no row is written (prototype: counter 4 → 4).
- **Rollback:** the counter update rolls back with the transaction, so the next
  writer reuses the number and no gap appears (prototype: seqs 1,2,3, rolled-back
  row absent).
- **Two shops:** different counter rows, no blocking (prototype: shop B
  committed while shop A held its lock 2.4 s longer).
- **Lock ordering (deadlock avoidance):** entity advisory lock → shop counter row
  → customer/supplier advisory locks in policy triggers. `a00_` naming makes the
  seq trigger fire before `customer_credit_limit_before_insert` and
  `customer_overpayment_guard`, so even a legacy path takes the shop lock before
  the customer lock. Residual `40P01` is classified transient.
- **Cost:** one counter-row update and one row lock per transaction per shop;
  per row a GUC read. Per-shop writes serialise: prototype with 8 writers and
  0–15 ms artificial holds sustained 86 TPS for one shop; one shop's real load is
  < 1 TPS. The rejected alternative (one value per row) would take N counter
  updates (N tuple versions + WAL) per aggregate for the same lock semantics.
- **Backfill:** existing rows get `server_seq = 0`; counters start at 0; a first
  pull from cursor `(-1, '')` includes everything; ties are broken by `id`.

## F. Concurrency proof and test design (executed on a prototype)

Executed with real concurrent PostgreSQL connections against a disposable
database (`test/r1_stage_a/server_seq_prototype/run.sh`):

| Scenario | Procedure | Observed |
| --- | --- | --- |
| A | A: shop S, obtains N, holds 3 s. B: same shop starts at +0.5 s. Reader at +1.5 s | B in `Lock/transactionid` wait; reader saw 0 new rows; B finished 10 ms after A committed; A=1, B=2 |
| B | A obtains, holds 2 s, **rolls back**; B waits | B proceeded after rollback with seq 3 (reused number, no gap); A's rows never exist |
| C | Shops S1 and S2 concurrently, S1 held 3 s | S2 committed while S1 still held its lock |
| D | One checkout writes `sales`, `sale_items`, `inventory_movements` | all three rows share the same `server_seq`; forged client values (−1, 999999, 0) overwritten |
| E | Idempotent replay of an existing sale | `already_synced`; counter unchanged; no rows |
| Prefix stress | 8 writers, one shop, random holds, ~10% rollbacks, 20–25 s; reader polling `max(seq)` vs `count(*)` | 2,169 transactions, 1,959 committed; seqs exactly 1..1959; **0 violations in 400 polls** |

Why the prefix property holds: within a shop, a transaction can only obtain a
value after every earlier holder of the counter row has committed or rolled
back; so committed values are assigned in commit order and a statement snapshot
always contains a contiguous prefix of committed values. A cursor
`(server_seq, id) > (s, i)` therefore can never pass a row that commits later.

R1.4 turns these into CI integration tests on the real migrated schema (two
`Process`-driven `psql` connections from Dart, plus the HTTP pull in §D).

## G. Exact pull inventory (POS runtime, 15 entities)

Cursor today: `(created_at, id)` for immutable, `(updated_at, id)` for mutable.
Proposed cursor for all: `(server_seq, id)`; index `(shop_id, server_seq, id)`
(global rows: `(server_seq, id)` partial where shop is null). Seq source is the
`a00_server_seq` trigger unless stated.

| # | Table | Scope (verified) | Mutability | Client write paths today | Seq key | `server_seq` protection |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `shops` | its own `id` | mutable | none (RPCs) | `new.id` | trigger; no client write grant |
| 2 | `devices` | shop | mutable | UPDATE on 5 listed columns | shop | trigger; not in column grant |
| 3 | `cashiers` | shop | mutable | none (RPCs) | shop | trigger |
| 4 | `categories` | **mixed**: `shop_id` nullable (null = global) | mutable | table INSERT (policy requires non-null shop); UPDATE on 3 columns | shop or global counter | trigger overwrites INSERT value; not in UPDATE grant |
| 5 | `master_products` | **global** (no `shop_id`) | mutable | none | global counter | trigger |
| 6 | `shop_products` | shop | mutable | table INSERT; UPDATE on 13 listed columns | shop | trigger overwrites; not in UPDATE grant |
| 7 | `customers` | shop | mutable | table INSERT; UPDATE on 7 listed columns | shop | trigger overwrites; not in UPDATE grant |
| 8 | `customer_ledger_entries` | shop | immutable | none (RPCs) | shop | trigger |
| 9 | `inventory_movements` | shop | immutable | none | shop | trigger |
| 10 | `sales` | shop | immutable (server updates `aggregate_hash` in same txn) | none | shop | trigger (same txn → same seq) |
| 11 | `sale_items` | shop | immutable | none | shop | trigger |
| 12 | `sale_payments` | shop | immutable | none | shop | trigger |
| 13 | `sale_returns` | shop | immutable | none | shop | trigger |
| 14 | `sale_return_items` | shop | immutable | none | shop | trigger |
| 15 | `sale_voids` | shop | immutable | none | shop | trigger |

`categories` gets two client cursors (`categoriesGlobal` by global counter,
`categoriesShop` by shop counter) because the two counters are separate number
spaces. The 7 owner-screen entities (`suppliers`, `supplier_ledger_entries`,
`purchases`, `purchase_items`, `purchase_payments`, `expense_categories`,
`expenses`) have the same `created_at` defect — decision Q2.

## H. Error state machine

Queue states: `pending`, `leased`, `retry_wait`, `blocked_auth`, `synced`,
`needs_attention`. New columns: `error_class`, `error_code`,
`attempt_count`, `server_error_count`, `first_server_error_at`,
`attention_reason`, `attention_at`, `acknowledged_at`.

| From | Event | To | Rule |
| --- | --- | --- | --- |
| pending / retry_wait (due) | acquire | leased | lease 2 min |
| leased (expired) | acquire | leased | crash recovery |
| leased | `inserted` / `already_synced` / `accepted_flagged` | synced | |
| leased | **connectivity** (no HTTP response: socket, DNS, timeout before response) | retry_wait | backoff `min(2^n, 300) s` + jitter; **unbounded** — the device can be offline for days and the event is valid |
| leased | **server transient** (5xx, 408, 429, `40001`, `40P01`, `55P03`, `57014`) | retry_wait | same backoff; `server_error_count++`; if ≥ 20 **or** `now − first_server_error_at ≥ 24 h` → needs_attention(`server_transient_exhausted`) |
| leased | `DPR01` dependency missing | retry_wait | if parent op is `needs_attention` → needs_attention(`parent_needs_attention`); after 7 days → needs_attention(`dependency_timeout`) |
| leased | **auth** (`42501`, `DPA01`, HTTP 401 / JWT expired) | blocked_auth | no timer; returns to `pending` on auth-state change (sign-in, token refresh success, cashier login) or explicit retry |
| leased | **permanent** (`DPV01`, `DPC01`, `DPX01`) | needs_attention | immediate |
| leased | **unknown** (any other code/exception) | retry_wait | `server_error_count++`; after **5** unknown errors **or 1 h** since the first → needs_attention(`unknown_error`) |
| needs_attention | owner "Retry" | pending | counters reset; error history kept in audit log |
| needs_attention | owner "Acknowledge" | needs_attention | `acknowledged_at` set; never deleted |

`failed` (today) maps to `retry_wait` in the v11 migration. Financial rows are
never deleted because of sync state.

## I. Record-and-flag semantics

Approved B-class facts (credit limit exceeded, customer inactive, negative stock
from an offline transaction, out-of-window void, overpayment of money actually
received) are **accepted and flagged**:

- The RPC runs in one transaction: validation → `sync_begin` → business rows →
  server-derived rows (recomputed amounts) → `sync_exceptions` rows → commit.
  A crash before commit leaves none of them; after commit, all of them.
- The policy triggers (`enforce_customer_credit_limit`,
  `prevent_customer_overpayment`, `prevent_supplier_overpayment`) check a
  transaction-local setting `dukaan.sync_policy = 'record_and_flag'` set by the
  sync RPC. When set, they insert a `sync_exceptions` row instead of raising;
  when unset (any other path), they keep raising as today.
- `sync_exceptions(id, shop_id, entity_type, entity_id, rule_code, detail jsonb,
  device_id, created_at default now(), server_seq, acknowledged_at,
  acknowledged_by)`, `unique(shop_id, entity_type, entity_id, rule_code)`;
  RLS owner-select; no client writes; acknowledgement via an owner RPC.
- RPC result `{"status":"accepted_flagged","flags":[...]}` when this
  transaction inserted any exception; replays return `already_synced`.
- **Not applied** (`DPX01`, whole transaction rolled back, local op
  `needs_attention`, local rows stay and show "unconfirmed"): second void of an
  already-voided sale, return beyond sold quantity, void of a returned sale,
  return of a voided sale.
- Kept as rejection (R2 security scope): revoked device or deactivated cashier
  → `DPA01`.

## J. Zero-total contract (approved)

`grand_total == 0` allowed; zero payment rows; every payment row `> 0`; stock
movements normal; server recomputes totals (server already accepts an empty
payment array with total 0 — no server change). Client: `LocalSaleService`
rejects any payment row `≤ 0` and allows an empty list only when total is 0;
POS builds no payment row for Rs 0.
Tests: zero-priced item line; zero-total checkout; no `sale_payments` row;
inventory decremented; replay of the same `checkoutId` → one sale; server sync
`inserted` then `already_synced`. No discount UI in R1.

## K. v1 void inventory (read-only, 2026-09-30)

| Location | Pending/retrying v1 void ops | Server-accepted voids | F-2 duplicates |
| --- | --- | --- | --- |
| Local dev server (`supabase_db_POS_store`) | n/a | `sale_voids` = 0 | n/a |
| Windows device DB (`%APPDATA%\com.dukaanpro\dukaan_pro\dukaan_pro.sqlite`, schema v10) | 0 (queue: 12 sales + 2 customer payments, all `synced`) | local `sale_voids` = 0 | none (movements and refunds) |
| Android AVD `Medium_Tablet` (booted `-read-only`) | app installed, **no local database file** | — | — |
| Hosted | none linked | — | — |

No real pending v1 void would be stranded. Proposed: new client sends v2; the
server rejects any v1 void with `DPV01`. (The Windows device DB also holds data
for 5 shops from earlier local-stack resets; only 2 shops exist on the server —
recorded, not touched.)

## L. v10 → v11 resync protocol

- **Marker:** new Drift table `sync_resync_state(shop_id, entity, phase,
  seq_cursor, id_cursor, started_at, completed_at)`; phases
  `pending → detecting → pulling → complete | blocked`.
- **Entities reset:** all 15 (§G) move to `server_seq` cursors; legacy
  `sync_cursors` rows are kept until the entity completes.
- **Order:** shops, devices, cashiers, categoriesGlobal, categoriesShop,
  master_products, shop_products, customers, sales, sale_items, sale_payments,
  inventory_movements, customer_ledger_entries, sale_returns,
  sale_return_items, sale_voids (parents before children for Drift FKs).
- **Pagination:** 200 rows per page; one Drift transaction per page writes the
  rows and advances `seq_cursor/id_cursor`, so process death resumes from the
  last committed page, not from zero.
- **Idempotent apply:** mutable reference tables upsert by id. Immutable
  financial tables use *insert-if-absent*; if a row with the same id exists and
  its financial fields differ (amount, quantity, product, type, customer, sale)
  the row is **not overwritten**, and the difference is written to a local
  `sync_divergence` report. `created_at` differences are ignored (known T-1).
- **F-2 artifacts:** `detecting` runs the §O device queries first. If duplicate
  void compensation exists, `inventory_movements` and `customer_ledger_entries`
  resync go to `blocked` (no rows applied for those two entities), the owner sees
  "Sync repair required", and all other entities continue. Nothing is deleted.
- **Authority:** an entity uses its `server_seq` cursor for normal pulls only
  after its resync phase is `complete`; until then the legacy cursor remains.
- **Resume:** on start, any entity in `pulling` continues from its stored
  cursor; `blocked` stays blocked until an approved repair clears it.

## M. Migration deployment compatibility

Verified in Supabase CLI v2.113.0 source (`apps/cli-go/pkg/migration/file.go`):
remote `db push` executes a file as a pipelined batch but runs statements
matching `CREATE INDEX`/`REINDEX`/`VACUUM`/`CLUSTER`/`ALTER SYSTEM` outside the
pipeline; local `db start`/`db reset` no longer use that code (a separate
TypeScript bootstrap). A file with an explicit `begin; … commit;` (the style of
all 18 existing migrations) cannot run `CREATE INDEX CONCURRENTLY`.

Decision for R1: **ordinary `CREATE INDEX` inside each transactional migration**
(tables are tiny pre-pilot; identical behaviour in local reset, CI and
`db push`). Online/concurrent indexing is deferred to R6, where a separate
non-transactional migration must be verified on every deployment path before
use. All R1 migrations are new forward-only files; the 18 existing files are
untouched; rollback is forward-fix (all changes additive).

## N. v10 → v11 upgrade test fixture

Built from `test/generated_migrations/schema_v10.dart` with drift_dev's
`SchemaVerifier` (no reset), seeded with raw SQL:

- shop, owner membership, device, product, customer (credit limit);
- sale `S1` (credit Rs 360, 2 items) with 2 `sale_items`, 1 `sale_payments`
  (credit), 2 `inventory_movements` (−1000 each), 1 `customer_ledger_entries`
  (`creditSale` 36000);
- sale `S2` (cash) with item, payment, movement;
- `sync_operations`: S1 `pending`, S2 `failed` (retry_count 3, `last_error`,
  `next_attempt_at`);
- `sync_cursors`: `inventoryMovements` and `sales` rows.

Assertions after `migrateAndValidate(db, 11)`: every id unchanged; all amounts,
quantities, payment methods and ledger amounts unchanged; stock and Udhaar
projections unchanged; `failed` → `retry_wait` with `attempt_count` preserved;
pending stays pending; legacy cursors present; `sync_resync_state` created in
phase `pending`; new columns present with defaults. The v11 snapshot is
committed during implementation only.

## O. Read-only historical detection plan

No repair runs in R1. R1.7 ships detection queries, a dry-run report, exact
proposed repair scripts (not executed) and verification queries.

Known T-1 rows (local dev server, measured):

| Sale id | `created_at` | `synced_at` | skew |
| --- | --- | --- | --- |
| `01a0c263-7263-7e84-8e43-c9cb1defabb8` | 2026-09-21 10:14:52+00 | 2026-09-21 05:15:22.951986+00 | +04:59:29.048 |
| `01a0c277-82a8-78b2-b6d4-b987dcb014d1` | 2026-09-21 10:36:47+00 | 2026-09-21 05:37:17.815473+00 | +04:59:29.185 |

Detection (read-only):

```sql
-- candidate T-1 rows: future relative to ingestion (candidate only; offline or
-- clock-skewed legitimate rows can also match, so never repair on this alone)
select id, created_at, synced_at, created_at - synced_at skew from sales
where created_at > synced_at + interval '1 minute';
-- void compensation completeness
select v.id, (select count(*) from sale_items i where i.sale_id = v.original_sale_id) items,
       (select count(*) from inventory_movements m where m.reference_id = v.id) moves from sale_voids v;
-- after R1.4
select count(*) from sales where server_seq is null;   -- per table
```

```sql
-- device: duplicated void compensation / refunds
select reference_id, product_id, count(*), group_concat(id) from inventory_movements
where reference_type = 'sale_void' group by 1, 2 having count(*) > 1;
select sale_id, count(*), group_concat(id) from customer_ledger_entries
where type = 'refund' and sale_id in (select original_sale_id from sale_voids)
group by 1 having count(*) > 1;
```

A T-1 repair proposal must use evidence beyond the skew heuristic (device zone
at creation, payload version, audit trail) and requires separate approval. Local
duplicate rows are never deleted automatically.

## P. Implementation order

| Substage | Failing test first | Files | Migration | Exit criteria |
| --- | --- | --- | --- | --- |
| R1.0 Harness + CI | — | move harness to `test/integration/`; HTTP layer (§D); `integration` CI job with TZ matrix; fix widget-test ordering artifact | none | both layers run in CI on the ephemeral stack |
| R1.1 Checkout durability + zero total | F-1 (3) + §B/§J cases | `pos_runtime_native.dart`, `pos_workspace.dart`, `pos_state.dart`, `local_sale_service.dart`, `sync_worker_runner.dart` (new) | none | one sale per checkout; receipt never waits on network |
| R1.2 Timestamp boundary (T-1) | T-1 under UTC and Karachi, codec tests | `sync_time.dart` (new), sale/purchase payload builders, codec removal, pull decode | none | T-1 green in both zones in CI |
| R1.3 Void identity (F-2) + dependency ids | F-2 | `local_sale_void_service.dart`, dependency ids for void/return | `…_r1_void_identity.sql` | F-2 green; v1 rejected `DPV01` |
| R1.4 Server order (O-2, T-1b) | O-2 A/B, §F concurrency tests | pull gateway/service, resync | `…_r1_sync_order.sql`; Drift v11 (incl. queue columns for R1.5) | O-2 green; EXPLAIN index range scan; upgrade test (§N) green |
| R1.5 Error model + record-and-flag | F-3 (2) + permanent/unknown/auth cases | worker, queue, classifier, needs-attention list | `…_r1_sync_codes_and_flags.sql` (R1 sync RPCs only) | F-3 green; no unbounded retry except connectivity |
| R1.6 Lifecycle (O-6 minimum) | `runOnce` escape | `sync_worker.dart`, `sync_queue_repository.dart`, single DB instance for POS runtime | none | no escaping exceptions; unique worker id |
| R1.7 Convergence suite + read-only detection | matrix (below) | integration tests, detection SQL, dry-run report | none | matrix green in CI; dry-run report produced, no mutation |

Convergence matrix (R1.7): A sale → B pull; offline late upload; future clock;
sale → void → pull on A and B; A sale → B return; duplicate upload ×10
concurrent; response lost; retry storm across restarts; UTC+05:00 device;
server restart mid-sync; client restart after commit; transient failure;
permanent conflict; cross-device credit limit (flagged); double void on two
devices (one applied, one needs_attention); zero-total sale.

## Q. Remaining decisions requiring approval

1. **Checkout fingerprint column** `sales.checkout_fingerprint` (Drift only) for
   local idempotent-commit conflict detection.
2. **Owner-screen entities** (7 procurement/expense tables): include them in the
   R1.4 `server_seq` migration (same trigger, same defect) or defer to a later
   phase.
3. **Legacy queued v1 sale/purchase payloads** at upgrade → `needs_attention`
   (`legacy_timestamp_payload`); none exist today.
4. **Error thresholds:** server-transient 20 attempts / 24 h; unknown 5 / 1 h;
   dependency 7 days; connectivity unbounded.
5. **v1 void rejection** as `DPV01` (inventory shows no stranded operation).
6. **New CI job** `integration` (ephemeral stack, HTTP layer, TZ matrix).
