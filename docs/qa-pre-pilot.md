# Pre-pilot authentication and manual verification

Supabase Auth remains authoritative for owners. Owner identity is never created
offline. `AuthSessionController` serializes owner-auth transitions and uses a
generation counter so logout, newer auth events, and disposal invalidate stale
asynchronous work. Duplicate sign-in submission is ignored while a request is
active.

A provisioned cashier may work offline only while the locally secured session
is unexpired, its shop matches the resolved shop, its device matches the stable
registered device, and required local shop/reference data exists. Any mismatch
clears the cached credential. Internet is required to authenticate a new
cashier, refresh an owner session, or recover an invalid cached session.

## Manual Windows checklist

1. Fresh launch — expect **Owner sign in**, never an endless spinner.
2. Enter a wrong password — expect **Wrong email or password**, with no backend details.
3. Enter valid owner credentials — expect shop resolution, then the registered-device screen.
4. Restart — expect the same device to restore without registration prompt.
5. Select an active cashier and enter the PIN — expect the POS workspace.
6. Add an item — expect cart totals and stock from local SQLite.
7. Choose **End cashier session** — expect return to cashier selection.
8. Restart — expect the ended cashier not to resume automatically.
9. Choose **Sign out** — expect Owner sign in and local cashier token removal.
10. Restart — expect Owner sign in.
11. Sign in again — expect the known shop/device to restore.
12. With a valid cashier session, disconnect the network and restart.
13. Valid offline session — expect POS only if expiry/shop/device/local-data checks pass.
14. Expired, wrong-shop, wrong-device, or incomplete-data session — expect denial and a clear internet-required recovery message; never POS access.
