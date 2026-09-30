# Phase 1 behavior and boundaries

Minimal UI supports owner sign-up, sign-in, sign-out, bootstrap loading, shop creation, and device registration. Development without cloud configuration shows a clear setup message; `APP_ENV=production` fails startup unless both public Supabase values are present. Unit tests never initialize Supabase.

`LocalSaleService.createSale` validates shop, active actor, active device, cart, thousandth quantities, prices, discounts, exact split-payment totals, and the credit customer. One Drift transaction inserts the sale, immutable snapshots, payments, negative movements, positive credit debt, audit record, and one aggregate queue operation. Any exception rolls back every row.

One unit equals 1000 quantity points; selling two units records `-2000`. Money remains integer paisa. Fractional multiplication rounds once to nearest paisa using integer arithmetic. Negative stock defaults to allowed. Setting `allow_negative_stock=false` activates local availability validation without altering history.

Phase 2A added trusted cashier sessions, queue leasing/recovery, deterministic reference pulls, and immutable aggregate fingerprints. Customer payment posting, returns/voids, discrepancy views, broader sync, and the production POS interface remain later work.
