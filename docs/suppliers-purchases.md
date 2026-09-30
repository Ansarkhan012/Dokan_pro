# Suppliers and purchases

Owners can manage suppliers, record multi-line purchases, inspect purchase
history, and record supplier payments. Cashiers have no navigation, table
write privileges, or RPC execution privilege for procurement.

Supplier payable uses positive magnitudes signed by type: purchases increase
payable and `paymentMade`/refund entries reduce it. A purchase creates positive
`purchase` inventory movements (`1000 = 1 unit`). No stock or payable balance
column is maintained.

Local purchase and supplier-payment writes are atomic and queue one versioned
aggregate. Cloud RPCs require the authenticated active owner, the same-shop
active supplier/device/products, consistent totals, and stable UUIDs. Payload
fingerprints prevent changed replays and exact retries cannot duplicate stock
or payable.

Purchase returns, damage workflows, expenses, reports, subscriptions, and FBR
integration are deliberately postponed.
