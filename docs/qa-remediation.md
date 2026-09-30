# QA remediation decisions

## Ledger overpayment

The MVP does not support advances. Customer receipts cannot exceed current
receivables and supplier payments cannot exceed current payables. Local Drift
services reject them before committing. PostgreSQL trigger guards serialize by
shop and party with advisory transaction locks, then recalculate the append-only
ledger balance before accepting an RPC insert.

## Synchronization lifecycle

Native POS synchronization runs on startup, after a local POS/Khata commit, when
the app resumes, and every two minutes while pending work exists. The network
request—not connectivity state—determines success. Existing leases and backoff
remain authoritative, so overlapping triggers cannot process one operation
twice and retries do not tight-poll.

## Reporting limitations

Returns are not fully implemented. Fully returned/voided sales are excluded,
but partially returned sales cannot yet produce a trustworthy adjusted profit.
Any period containing partial returns must be treated as provisional. A zero
cost snapshot means a deliberately valid zero cost in the current schema;
unknown cost is not representable and must not be imported as zero. A future
migration must add explicit cost-validity semantics before importing unknown
historical costs.
