# Cashier security

Cashiers are shop-local identities, not public email/password users. Owners create them through `create_cashier`; PostgreSQL validates a 4–8 digit PIN and stores only a bcrypt cost-12 hash. Column privileges prevent authenticated clients from selecting `pin_hash`, and Flutter requests metadata fields only.

`authenticate_cashier` accepts shop, app-scoped device identifier, cashier, and PIN at a trusted security-definer boundary. It requires an active device and cashier, verifies with `pgcrypto`, and returns a 256-bit opaque token once over TLS. PostgreSQL stores only SHA-256 of that high-entropy token. Sessions bind shop, cashier, and device, expire after 12 hours, track last use, and support individual or owner revocation. Disabling a cashier revokes all sessions; disabling a device makes every bound session fail.

Five consecutive invalid attempts for one shop/cashier/device tuple create a 15-minute lock. Invalid responses are generic. This is a baseline; production should also add gateway/IP-aware throttling.

Flutter stores the opaque token using platform secure storage. It never receives a PIN hash. Online validation failure, expiry, or logout clears the token. Tokens are excluded from diagnostics and logs.

## Offline continuation

After a successful online authentication, a cashier may continue local billing without network requests until local session expiry or explicit logout. Remote revocation becomes effective locally when next learned from the backend; already-created local sales remain immutable and later upload can be rejected. Devices should reconnect regularly.

## Shared-tablet owner mode

The owner's Supabase session stays signed in underneath cashier mode (pulls and uploads use it), so owner screens are gated on the device. Entering cashier mode engages `OwnerModeLock` before any POS UI is shown, and the lock is persisted in secure storage so an app restart does not reopen owner mode. While locked, the device hub shows no owner actions, and every owner screen opens only through `ownerOnlyRoute`, which re-checks the lock and tears the screen down if owner mode locks while it is open. Only the owner's password (re-verified against Supabase Auth for the signed-in owner), a fresh owner sign-in, or a full sign-out releases it. Unlocking needs internet.

Residual risk: owner RPCs and RLS authorize `is_active_owner(auth.uid())`, and the tablet holds the owner JWT, so the backend cannot tell owner mode from cashier mode on a shared device. The boundary is enforced in the app, not the server. Closing it requires a cashier-scoped backend identity on shared devices (auth/RLS change).
