# Authentication and RLS

Owners authenticate with Supabase email/password. An `auth.users` trigger inserts `profiles` deterministically with `on conflict do nothing`. First login reads active `shop_users`; if none exist, `create_owner_shop` creates the shop and owner membership within one PostgreSQL transaction using PKR, Asia/Karachi, and negative-stock-enabled defaults.

The app generates a UUID v7 once and retains it in platform preferences. `register_shop_device` accepts this app-scoped identifier, never a hardware identifier, and only an active owner can register or refresh it. Revoked devices remain inactive and are checked by the sale RPC.

All exposed tenant tables have RLS. `is_active_owner(shop_id)` is narrowly granted, uses `security definer`, and fixes `search_path` to `public, pg_temp`. It avoids recursive evaluation of `shop_users` policies. Helper/RPC execution is revoked from `public` and granted only to `authenticated`.

Direct policies permit owner reads and limited inserts/updates on mutable tables in their shop. No client delete policy exists. Sales, items, payments, movements, ledgers, and audit logs are read-only through PostgREST and written through the aggregate RPC. `shop_users` cannot be directly inserted or role-modified, preventing client-controlled owner escalation. Master products are authenticated-read-only.

Cashier PINs are validated as 4–8 digits and stored with PostgreSQL bcrypt via `crypt(..., gen_salt('bf', 12))`. Phase 2A adds trusted opaque cashier sessions, secure device storage, expiry, device/shop binding, revocation, and failed-attempt locking. No plaintext or hash is returned to Flutter or stored locally; see [Cashier security](cashier-security.md).

The SQL regression test establishes two owners and shops, verifies Owner A sees and writes only Shop A, rejects a Shop B write, and verifies anonymous reads return nothing. Run it only against an isolated local Supabase database.
