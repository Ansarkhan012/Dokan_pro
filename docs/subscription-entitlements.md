# Subscription entitlement design

PostgreSQL owns plans, subscriptions, device state and claim eligibility. The
`entitlement_claims` RPC authorizes the authenticated owner, shop and active
device, but does not sign. The `issue-entitlement` Edge Function calls that RPC
with the caller JWT and signs its canonical JSON result with RSA-SHA256.

For local development, generate a disposable RSA-2048 JWK key pair (WebCrypto,
OpenSSL plus a JWK converter, or an equivalent audited tool). Configure the
private JWK only as `ENTITLEMENT_PRIVATE_JWK` and its label as
`ENTITLEMENT_KEY_ID` in Supabase function secrets. Pass only the public JWK
modulus/exponent to Flutter through `--dart-define` values
`ENTITLEMENT_RSA_MODULUS_B64URL` and `ENTITLEMENT_RSA_EXPONENT_B64URL`. Never
commit either a production private key or a service-role key. Production should
use a managed KMS/HSM-backed signer with rotation and audited key identifiers.

State calculation uses the last signed server time plus forward local elapsed
time. Moving the wall clock backwards by more than five minutes blocks new
mutations pending online verification. This detects common rollback attempts,
but a compromised OS can tamper with storage and clocks; offline tampering
cannot be made impossible without hardware-backed counters/attestation.

- Before `valid_until`: Trial Active or Active; within three days: Expiring Soon.
- After `valid_until` through `offline_grace_until`: Offline Grace, strong warning.
- After grace: Expired and new financial mutations are blocked.
- Bad signature, binding, version, timestamps, missing proof, or suspicious
  rollback: verification required and new mutations are blocked.

Historical/read-only data is never removed. A device revoked while disconnected
can use an already-issued proof only until its bounded grace expiry. It cannot
obtain a new proof, and instant offline revocation is not possible.

## Financial mutation boundaries

Production UI composition supplies `EntitlementMutationAuthorizer` to every
local aggregate service. Authorization finishes before the Drift transaction
opens; a denial therefore creates no financial row, stock movement, audit row,
or sync operation.

| Mutation | Local boundary |
| --- | --- |
| Sale (including Udhaar) | `LocalSaleService.createSale` |
| Return | `LocalSaleReturnService.create` |
| Void | `LocalSaleVoidService.voidSale` |
| Customer payment | `LocalCustomerPaymentService.receive` |
| Purchase | `LocalPurchaseService.create` |
| Supplier payment | `LocalSupplierPaymentService.record` |
| Expense | `LocalExpenseService.create` |
| Opening stock/manual adjustment/damage | `LocalInventoryAdjustmentService.record` |

There are no separate manual customer/supplier financial-ledger application
methods. Credit-sale/refund and purchase/payable postings are internal parts of
the aggregate services above and inherit their authorization decision.

## Accepted pre-pilot offline limitation

The pre-pilot commercial-access-control model intentionally stops at the
server-issued, shop-bound and device-bound RS256 entitlement plus centralized
local mutation authorization. Existing server RPCs continue to enforce tenant,
actor, active-device, aggregate, immutability and idempotency rules; they do not
claim to prove when a disconnected device created an operation.

A sufficiently modified or compromised offline client can bypass software-only
expiry enforcement. A client timestamp cannot repair this because it can be
forged, while checking only the subscription state at synchronization time
would reject legitimate work created offline before expiry. Closing that gap
requires stronger trusted hardware/time primitives and is explicitly deferred
from the controlled 1–2 shop pre-pilot. No server financial security check is
weakened to accommodate subscription behavior.

## Development issuance verification

Run the local stack and then execute:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_development_entitlement_e2e.ps1
```

The script generates a disposable RSA-2048 key in memory, writes the private
JWK only to a temporary Edge Function environment file, starts the real local
issuer, and deletes that file and its logs on completion. It creates an
authenticated development owner, shop and device, obtains a trial entitlement,
and verifies it with the same Dart RS256 verifier and policy used by Flutter.
It also checks malformed, cross-shop, wrong-device, tampered-token and revoked-
device rejection. The private key and service-role credentials are never
compiled into Flutter or printed by the test.
