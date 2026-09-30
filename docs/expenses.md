# Expenses

Expense categories are tenant reference data. Eleven defaults are created
idempotently for each shop, and owners may add custom categories. Expenses are
owner-only financial history and are never mixed with supplier purchases.

The local write transaction includes the expense, audit log, and persistent
sync operation. Amounts are integer paisa and must be greater than zero;
payment method is cash or digital. Cloud synchronization validates active
owner, tenant category, active device, actor, and payload fingerprint.

There is deliberately no edit or delete workflow. A future correction feature
must create an audited void/reversal. Reports, charts, dashboards, and
subscriptions remain outside this phase.
