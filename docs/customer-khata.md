# Customers and Khata

The owner device screen opens customer management. Owners can search, add,
edit, activate/deactivate, set contact details and notes, and configure an
optional credit limit. Similar names or phone numbers are allowed because they
can be legitimate; the UI makes phone search available instead of imposing a
lossy uniqueness rule.

The cashier POS `Customers / Khata` destination is read-only for profiles. It
shows balances and statements and permits a cash or digital payment receipt.
The raw PIN and session token are never part of customer or ledger data.

Balances are calculated as:

`openingBalance + creditSale + adjustment - paymentReceived - refund`

Amounts are integer paisa and stored as positive magnitudes. The entry type
provides the accounting sign. Every payment receipt is an immutable local row,
an audit row, and a durable sync operation committed atomically. PostgreSQL
accepts it only for an active owner or a valid cashier session bound to the
same active shop device. Replaying an identical payload returns
`already_synced`; a different payload with the same entry UUID is rejected.

Returns UI and manual adjustments are postponed. Their enum values remain so a
future implementation can add compensating ledger entries without editing
history. WhatsApp reminders, suppliers, reports, and subscriptions are outside
this phase.
