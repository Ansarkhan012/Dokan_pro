# Stage 2: user-visible string inventory

Generated 2026-10-12 by a static scan of `lib/` (Dart string literals that contain words; `.g.dart`, imports, keys and SQL calls excluded). It is a superset: some category D/B entries are internal and are confirmed per batch. Line numbers refer to the working tree at scan time.

| Category | Files | Occurrences |
| --- | ---: | ---: |
| A. Widget UI text | 36 | 759 |
| B. Domain, service and policy messages shown to users | 20 | 111 |
| C. Formatting helpers | 2 | 29 |
| D. Internal, SQL or never shown to users: **do not translate** | 9 | 21 |
| **Total** | **67** | **920** |

## A. Widget UI text (migrate to ARB)

### `lib/features/pos/pos_workspace.dart` (78)

| Line | Text |
| ---: | --- |
| 261 | No product matches that barcode. |
| 321 | This sale was already saved with different details. Nothing new was recorded. |
| 322 | Sale could not be completed. Nothing was charged. |
| 409 | The receipt could not be opened. Find it in Bills. |
| 429 | Sale |
| 430 | Products |
| 431 | Bills |
| 432 | Khata |
| 505 | Last sale saved on this device: ${formatPkr(sale.total)} at $time |
| 512 | View / Reprint |
| 516 | Dismiss |
| 571 | Open Current Bill |
| 572 | Current Bill • ${cart.lines.length} • ${formatPkr(cart.subtotalMinor)} |
| 589 | Dukaan Pro |
| 605 | Some records could not sync. The owner can review them. |
| 618 | Needs attention |
| 620 | Offline |
| 622 | Syncing |
| 624 | Pending sync |
| 625 | Synced |
| 667 | New Sale |
| 675 | Today: ${formatPkr(value?.total ?? 0)}  •  ${value?.bills ?? 0} bills |
| 698 | Search product or scan barcode |
| 725 | All |
| 768 | No local products found. |
| 822 | Current Bill |
| 827 | ${cart.lines.length} items |
| 834 | Tap a product to begin a sale. |
| 841 | Subtotal |
| 842 | Discount |
| 843 | Total |
| 914 | Completing… |
| 914 | Pay ${formatPkr(cart.subtotalMinor)} |
| 934 | Hold Bill |
| 949 | Clear |
| 976 | ${packCountLabel(line.quantity)} × ${formatPkr(line.product.salePriceMinor)} |
| 997 | × ${measureUnitPriceLabel(formatPkr(line.product.salePriceMinor), unit)} |
| 1008 | Remove |
| 1062 | Remove |
| 1203 | Credit limit exceeded. Ask the owner to increase the limit. |
| 1224 | Payment • ${formatPkr(widget.totalMinor)} |
| 1233 | Cash |
| 1236 | Digital |
| 1240 | Udhaar |
| 1244 | Split |
| 1258 | Cash received |
| 1261 | Digital payment will be recorded without a gateway. |
| 1267 | Cash amount |
| 1268 | Digital amount |
| 1269 | Udhaar amount |
| 1276 | Change: ${formatPkr(((parseMoneyMinor(cash.text) ?? 0) - widget.totalMinor).clamp(0, 1 << 62))} |
| 1300 | Cancel |
| 1302 | Complete Sale |
| 1313 | Rs  |
| 1319 | Udhaar customer |
| 1338 | Existing balance: ${formatPkr(customer.balanceMinor)} |
| 1339 | This sale on Udhaar: ${formatPkr(creditAmount)} |
| 1341 | New balance: ${formatPkr(projected)} |
| 1346 | Credit limit: ${formatPkr(limit)} |
| 1374 | Sale completed |
| 1387 | The sale is saved. Open its receipt from Bills. |
| 1393 | Saved on this tablet • Synced |
| 1398 | Saved on this tablet • Waiting to sync |
| 1413 | View receipt |
| 1417 | New sale |
| 1488 | Stock ${productStockLabel(product)}${product.isLowStock ?  |
| 1514 | Add |
| 1585 | From ${formatPkr(entry.fromPriceMinor)} |
| 1594 | ${entry.variants.length} pack sizes${low ?  |
| 1620 | Add |
| 1662 | No barcode |
| 1664 | ${productPriceLabel(product)} •  |
| 1665 | Stock ${productStockLabel(product)} |
| 1668 | Low stock |
| 1827 | ${minor < 0 ?  |
| 1827 | }Rs $rupees.${paisa.toString().padLeft(2,  |
| 1831 | ${quantity ~/ quantityScale} |
| 1834 | $sign${absolute ~/ quantityScale}.${(absolute % quantityScale).toString().padLeft(3,  |

### `lib/features/purchases/purchase_management_native.dart` (66)

| Line | Text |
| ---: | --- |
| 103 | Suppliers & Purchases |
| 108 | Suppliers |
| 109 | Purchases |
| 117 | Add supplier |
| 117 | New purchase |
| 133 | Search supplier name or phone |
| 134 | Search supplier or invoice |
| 160 | No suppliers yet. |
| 168 | ${s.phone ??  |
| 168 |  • Inactive |
| 173 | ${formatPkr(s.payableMinor)} payable |
| 195 | No purchases yet. |
| 201 | ${p.supplierName} • ${formatPkr(p.totalMinor)} |
| 203 | ${_date(p.date)} • ${p.invoiceNumber ??  |
| 208 | Paid |
| 210 | Partial |
| 211 | Credit |
| 240 | Supplier could not be saved. |
| 272 | Product |
| 289 | Purchase saved locally. |
| 299 | Could not save the purchase. Please try again. |
| 364 | Add supplier |
| 364 | Edit supplier |
| 371 | Name * |
| 372 | Contact person |
| 373 | Phone |
| 374 | Address |
| 375 | Notes |
| 384 | Active |
| 392 | Cancel |
| 408 | Save |
| 451 | New Purchase |
| 461 | Supplier * |
| 465 | Invoice/reference |
| 469 | Notes |
| 473 | Purchase date |
| 489 | Products |
| 493 | Total ${formatPkr(total)} |
| 500 | Amount paid |
| 501 | Rs  |
| 506 | Cash |
| 507 | Digital |
| 513 | Save Purchase |
| 524 | Qty ${quantityToInput(current.$1)} @ ${formatPkr(current.$2)} |
| 603 | Purchase item |
| 609 | Quantity |
| 613 | Unit cost |
| 626 | Add |
| 655 | Record Payment |
| 663 | Payable ${formatPkr(widget.supplier.payableMinor)} |
| 667 | Purchases ${formatPkr(widget.supplier.totalPurchasesMinor)} • Payments ${formatPkr(widget.supplier.totalPaymentsMinor)} |
| 673 | Purchase |
| 673 | Payment |
| 677 | ${l.signedAmountMinor > 0 ?  |
| 677 | }${formatPkr(l.amountMinor)} • ${formatPkr(l.runningBalanceMinor)} |
| 720 | Supplier Payment |
| 727 | Amount |
| 728 | Rs  |
| 733 | Cash |
| 734 | Digital |
| 741 | Reference |
| 745 | Note |
| 757 | Record |
| 769 | Purchase |
| 780 | Total ${formatPkr(purchase.totalMinor)} • Paid ${formatPkr(purchase.paidMinor)} • Due ${formatPkr(purchase.dueMinor)} |
| 787 | ${quantityToInput(l.quantity)} × ${formatPkr(l.unitCostMinor)} |

### `lib/features/sales/sales_history.dart` (65)

| Line | Text |
| ---: | --- |
| 186 | s.shop_id=? and s.sale_status='completed' and s.created_at>=? and s.created_at<? |
| 194 |  and s.id=? |
| 198 |  and (lower(coalesce(s.invoice_number,'')) like ? or lower(coalesce(cu.name,'')) like ? or lower(coalesce(cu.phone,'')) like ? |
| 208 |  or lower(s.id) like ? |
| 214 |  and s.cashier_id=? |
| 220 |  having count(distinct case when p.amount>0 then p.payment_method end)>1 |
| 222 |  having count(distinct case when p.amount>0 then p.payment_method end)=1 and max(case when p.amount>0 then p.payment_method end)=\ |
| 227 | Split |
| 227 | Unknown |
| 229 | Needs attention |
| 229 | Synced |
| 229 | Pending |
| 230 | Voided |
| 230 | Fully Returned |
| 230 | Partially Returned |
| 230 | Completed |
| 278 | Sale |
| 368 | ${formatDisplayDateTime(row.createdAt)} • ${row.reason} • ${formatPkr(row.refundAmount)} |
| 445 | Sales could not be loaded. Please try again. |
| 464 | Yesterday |
| 552 | Retry |
| 562 | No sales match these filters. |
| 582 | Loading… |
| 582 | Load more |
| 613 | Bill #, customer name or phone |
| 616 | Search |
| 631 | Cashier |
| 635 | All cashiers |
| 665 | Today |
| 666 | Yesterday |
| 667 | This Week |
| 669 | Custom dates |
| 678 | All payments |
| 679 | Cash |
| 680 | Digital |
| 681 | Udhaar |
| 682 | Split |
| 707 | Today's sales |
| 709 | ${summary.bills} ${summary.bills == 1 ?  |
| 712 | Cash |
| 713 | Digital |
| 714 | Udhaar |
| 763 | Completed |
| 764 | Voided |
| 771 | Synced |
| 772 | Synced |
| 776 | Needs attention |
| 777 | Needs attention |
| 782 | Waiting to sync |
| 879 | $shop • ${formatDisplayDateTime(detail.sale.at)} |
| 883 | Cashier: ${detail.sale.cashier} |
| 888 | Customer: ${detail.sale.customer} |
| 900 | ${l.name}\n${formatLineQuantity(l.quantity, l.measureUnit)} × ${formatPkr(l.unitPrice)} |
| 911 | Subtotal |
| 912 | Discount |
| 913 | Total |
| 915 | Returned |
| 916 | Net |
| 919 | Paid by ${paymentMethodLabel(p.key)} |
| 923 | Return: $value |
| 928 | Void reason: ${detail.voidReason} |
| 945 | Void |
| 953 | Return items |
| 961 | View / Reprint |
| 965 | Close |

### `lib/features/settings/owner_settings_screen.dart` (59)

| Line | Text |
| ---: | --- |
| 143 | Settings are unavailable offline until the first sync. |
| 144 | Showing cached settings. |
| 190 | Online subscription verification is required. |
| 198 | Trial active |
| 199 | Active |
| 200 | Expires soon |
| 201 | Offline grace |
| 203 | Online verification required |
| 204 | Expired |
| 205 | Online verification required |
| 225 | Enter a shop name and a non-negative stock threshold. |
| 272 | Settings saved. |
| 277 | Could not save settings. Check your connection. |
| 298 | Settings |
| 321 | Subscription |
| 324 | Shop details |
| 330 | Shop name |
| 339 | Phone |
| 345 | Address |
| 350 | Currency |
| 352 | Time zone |
| 353 | Pakistan (Asia/Karachi) |
| 360 | Stock |
| 367 | Allow selling below zero stock |
| 373 | Default low-stock alert level |
| 381 | Receipt |
| 388 | Receipt footer |
| 394 | Paper width |
| 399 | 58 mm |
| 403 | 80 mm |
| 413 | Show phone on receipt |
| 419 | Show address on receipt |
| 426 | Notifications |
| 431 | Owner alerts |
| 435 | Alerts are not available yet. Your choice is saved  |
| 436 | for when they are. |
| 447 | Saving… |
| 447 | Save settings |
| 451 | Registered devices |
| 454 | Cashiers |
| 487 | Checking subscription… |
| 505 | This tablet can record sales |
| 510 | Verification or renewal needed |
| 520 | Plan |
| 521 | Unavailable |
| 524 | Current period ends |
| 526 | Works offline until |
| 531 | Last checked online |
| 533 | Not yet |
| 543 | Online renewal is not available in the app yet. |
| 547 | Renew subscription |
| 581 | ${d.deviceName} (this device) |
| 586 | ${_deviceTypeLabel(d.deviceType)} • Registered  |
| 594 | Active |
| 595 | Inactive |
| 601 | Sync status for this tablet is shown at the top of the sales screen. |
| 608 | Android tablet |
| 609 | Windows computer |
| 610 | Mobile |

### `lib/app/auth_gate.dart` (48)

| Line | Text |
| ---: | --- |
| 154 | Could not sign in. Check your connection and try again. |
| 164 | Owner sign in |
| 169 | Full name |
| 173 | Email |
| 178 | Password |
| 189 | Please wait… |
| 191 | Sign up |
| 192 | Sign in |
| 198 | Have an account? Sign in |
| 241 | Bootstrap failed |
| 244 | Could not load your shop. Check your connection and try again. |
| 248 | Sign out |
| 318 | Could not create your shop. Please try again. |
| 329 | Shop name |
| 333 | Phone |
| 337 | Address |
| 346 | Creating shop… |
| 419 | Could not check this device registration. Check your connection. |
| 457 | Could not register this device. Check your connection. |
| 500 | Unlock owner mode once to set up cashier mode on this device. |
| 505 | Could not set up cashier mode on this device. Check your connection. |
| 514 | Could not secure owner mode on this device. Try again. |
| 589 | Device name |
| 593 | Registering… |
| 593 | Register this device |
| 596 | Device is revoked. |
| 598 | Device active. Local sales foundation is ready. |
| 604 | Owner Dashboard |
| 614 | Settings |
| 623 | Sales & Returns |
| 633 | Inventory |
| 642 | Manage products |
| 651 | Manage customers / Khata |
| 660 | Suppliers & Purchases |
| 669 | Expenses |
| 678 | Sync issues |
| 701 | Sign out |
| 709 | invalid login |
| 710 | invalid credentials |
| 711 | Wrong email or password. |
| 716 | No connection to the server. Check your internet and try again. |
| 718 | refresh token |
| 719 | Your session expired. Please sign in again. |
| 721 | Could not sign in. Please check your details and try again. |
| 725 | Web preview |
| 727 | Windows counter |
| 728 | Android tablet |
| 729 | Owner mobile |

### `lib/features/reports/owner_dashboard_native.dart` (42)

| Line | Text |
| ---: | --- |
| 44 | ${widget.shopName} • Dashboard |
| 55 | Could not calculate this report. |
| 60 | Retry |
| 86 | Cached device data • pending operations may not be reflected on other devices. |
| 90 | ${m.partialReturnCount} partially returned sale(s) are excluded. Profit is provisional until returns accounting is implemented. |
| 107 | Net Sales |
| 108 | Purchases |
| 109 | Gross Profit |
| 110 | Expenses |
| 111 | Net Profit |
| 112 | Customer Udhaar |
| 113 | Supplier Payable |
| 114 | Bills |
| 115 | Low Stock |
| 120 | Sales |
| 121 | Gross sales |
| 122 | Returns / voids |
| 123 | Net sales |
| 124 | Average bill |
| 125 | Cash |
| 126 | Digital |
| 127 | Udhaar created |
| 129 | Purchases |
| 130 | Period purchases |
| 131 | Paid |
| 132 | Credit created |
| 133 | Transactions |
| 136 | Sales vs Purchases |
| 140 | Top products by sales |
| 142 | Top products by quantity |
| 146 | Highest gross profit products |
| 147 | Expenses by category |
| 148 | Expenses by payment method |
| 149 | Top customer debtors |
| 150 | Top supplier payable |
| 152 | Low stock (current / threshold) |
| 159 | ${m.missingCostLines} sale lines excluded from profit because cost snapshots were invalid. |
| 163 | Cashier performance |
| 170 | ${c.bills} bills • Cash ${formatPkr(c.cash)} • Digital ${formatPkr(c.digital)} • Udhaar ${formatPkr(c.credit)} |
| 215 | No data |
| 221 | ${money ? formatPkr(r.value) : r.value}${secondary ?  |
| 259 | No period activity |

### `lib/features/products/product_management_native.dart` (40)

| Line | Text |
| ---: | --- |
| 101 | Product saved to My Products. |
| 117 | Products |
| 121 | Refresh |
| 132 | My Products |
| 133 | Add Product |
| 143 | Could not open products. Please try again. |
| 245 | Search name or barcode |
| 253 | Category |
| 257 | All categories |
| 277 | No products match this filter. |
| 313 | Loading… |
| 313 | Load more |
| 400 | Product saved. The image could not be updated on this tablet. |
| 440 | ${product.categoryName} • ${product.barcode ??  |
| 445 | Sale ${formatProductMoney(product.salePriceMinor)}${_perUnit(product)} •  |
| 446 | Purchase ${formatProductMoney(product.purchasePriceMinor)}${_perUnit(product)} |
| 449 | Stock ${formatLineQuantity(product.stockQuantity, product.measureUnit)}${product.isLowStock ?  |
| 449 |  • Inactive |
| 459 | Edit |
| 522 | Catalog search failed. Check internet and try again. |
| 533 | Search Master Catalog |
| 545 | Product name, brand, or barcode |
| 552 | Searching… |
| 552 | Search |
| 576 | ${product.brand.isEmpty ? product.categoryName : product.brand} • ${product.barcode}\n${product.unit}${product.packLabel == null ?  |
| 583 | Open / edit |
| 587 | Add |
| 640 | Could not save the product. Please try again. |
| 727 | Product created. The image could not be saved on this tablet. |
| 798 | Purchase price |
| 802 | Sale price |
| 806 | Opening stock |
| 810 | Low-stock threshold |
| 823 | Cancel |
| 832 | Enter valid non-negative values. |
| 845 | Add to My Shop |
| 870 | $sign${absolute ~/ 1000} |
| 876 | ${minor < 0 ?  |
| 876 | }Rs ${absolute ~/ 100}. |
| 877 | ${(absolute % 100).toString().padLeft(2,  |

### `lib/features/products/custom_product_dialog.dart` (39)

| Line | Text |
| ---: | --- |
| 126 | Could not open that image. Try another. |
| 151 | Complete all required fields with valid values. |
| 189 | Pack ${row.label.text.trim().isEmpty ? variants.length + 1 : row.label.text.trim()}:  |
| 190 | enter a sale price and whole-pack stock. |
| 277 | Could not create the product. Please try again. |
| 290 | For items that are not in the master catalog. |
| 297 | Cancel |
| 302 | Creating… |
| 338 |  per ${measure.wholeLabel} |
| 339 |  (${measure.wholeLabel}) |
| 345 | Barcode |
| 346 | Optional |
| 352 | Product details |
| 370 | Packaged Variants |
| 388 | Product family name * |
| 388 | Product name * |
| 389 | e.g. Tapal Danedar |
| 396 | Pack sizes |
| 414 | Category * |
| 437 | Volume (L) |
| 449 | Unit * |
| 469 | Pack size / label |
| 475 | Pricing & stock |
| 479 | Purchase price$per * |
| 484 | Sale price$per * |
| 492 | Opening stock$stockUnit |
| 497 | Low-stock alert at$stockUnit |
| 504 | Quick quantities |
| 517 | Allow custom quantity |
| 519 | Cashier may type any amount, not only quick quantities. |
| 532 | Category * |
| 557 | Rs  |
| 612 | Change product image |
| 634 | Product image preview |
| 654 | Product image |
| 665 | Optional · JPG, PNG or WebP |
| 681 | Change |
| 688 | Remove |
| 724 | Choose product image |

### `lib/features/inventory/inventory_management_native.dart` (38)

| Line | Text |
| ---: | --- |
| 60 | Inventory |
| 70 | Inventory could not be loaded. |
| 73 | Try again |
| 89 | Current Stock |
| 90 | Movement History |
| 132 | Search product or barcode |
| 140 | All |
| 144 | Low |
| 148 | Out |
| 165 | No products match this filter. |
| 185 | No stock movements yet. |
| 227 | Stock adjustment saved locally. |
| 235 | Stock adjustment could not be saved. Check the quantity and try again. |
| 264 | Adjust ${widget.product.name} |
| 272 | Reason |
| 276 | Manual correction (+ / -) |
| 280 | Damaged / wastage |
| 284 | Opening stock |
| 293 | Quantity (+ / -) |
| 294 | Quantity |
| 299 | Reason / note * |
| 312 | Cancel |
| 324 | Enter a valid quantity and reason. |
| 329 | Save Adjustment |
| 351 | No barcode |
| 406 | Out of stock |
| 408 | Low stock |
| 411 | in stock |
| 417 | Inactive |
| 425 | Adjust |
| 439 | Opening stock |
| 440 | Purchase |
| 441 | Sale |
| 443 | Void |
| 443 | Return |
| 444 | Damaged / wastage |
| 445 | Adjustment |
| 446 | Stock correction |

### `lib/features/customers/customer_khata_view.dart` (37)

| Line | Text |
| ---: | --- |
| 49 | Search customer name or phone |
| 59 | Could not load Khata: ${snap.error} |
| 63 | No customers found. |
| 75 | ${customer.phone ??  |
| 75 |  • Inactive |
| 79 | Clear |
| 80 | ${formatPkr(customer.balanceMinor)} due |
| 133 | Receive Payment |
| 152 | Balance |
| 154 | Credit limit |
| 156 | Not set |
| 160 | Credit sales |
| 164 | Payments |
| 172 | Statement |
| 176 | No ledger entries yet. |
| 190 | ${_date(line.createdAt)}${line.note == null ?  |
| 197 | ${line.signedAmountMinor >= 0 ?  |
| 200 | Balance ${formatPkr(line.runningBalanceMinor)} |
| 244 | Payment saved locally and queued for sync. |
| 252 | Payment could not be recorded. Nothing was changed. |
| 285 | Receive Payment |
| 295 | Amount |
| 296 | Rs  |
| 301 | Cash |
| 304 | Digital |
| 313 | Reference (optional) |
| 318 | Note (optional) |
| 331 | Cancel |
| 339 | Enter an amount greater than zero. |
| 345 | Payment cannot exceed ${formatPkr(widget.maximumMinor)}. |
| 360 | Record Payment |
| 375 | ${value.day.toString().padLeft(2,  |
| 378 | Sale${line.saleId == null ?  |
| 380 | Payment${line.paymentMethod == null ?  |
| 381 | Opening balance |
| 382 | Return adjustment |
| 383 | Manual adjustment |

### `lib/features/expenses/expense_management_native.dart` (34)

| Line | Text |
| ---: | --- |
| 101 | Expenses |
| 105 | Add category |
| 113 | Add Expense |
| 128 | Today |
| 129 | This month |
| 137 | Search description/category |
| 148 | All categories |
| 161 | Category |
| 175 | Any date |
| 190 | No expenses found. |
| 199 | ${e.category} • ${e.paymentMethod.name} • ${_dateTime(e.expenseAt)} |
| 210 | ${e.category}\n${formatPkr(e.amountMinor)} • ${e.paymentMethod.name}\n${_dateTime(e.expenseAt)}${e.reference == null ?  |
| 210 | }${e.note == null ?  |
| 215 | Close |
| 249 | Custom category |
| 252 | Name |
| 257 | Add |
| 274 | Category could not be created. |
| 317 | Expense saved locally. |
| 326 | Could not save the expense. Please try again. |
| 361 | Add Expense |
| 374 | Category * |
| 378 | Description * |
| 386 | Amount * |
| 387 | Rs  |
| 392 | Cash |
| 395 | Digital |
| 402 | Expense date |
| 416 | Reference |
| 420 | Note |
| 429 | Cancel |
| 439 | Complete all required fields. |
| 456 | Save |
| 489 | ${_date(d)} ${d.hour.toString().padLeft(2,  |

### `lib/features/products/edit_product_dialog.dart` (27)

| Line | Text |
| ---: | --- |
| 86 |  per ${measure!.wholeLabel} |
| 124 | Could not open that image. Try another. |
| 143 | Enter valid non-negative values. |
| 167 | Could not update product. |
| 177 | Edit product |
| 198 | Pricing & stock |
| 204 | Loose product · sold by weight (kg) |
| 205 | Loose product · sold by volume (L) |
| 212 | Purchase price$_per |
| 217 | Sale price$_per |
| 224 | Low-stock alert at${measure == null ?  |
| 230 | Quick quantities |
| 243 | Allow custom quantity |
| 247 | Availability |
| 252 | Active |
| 253 | Inactive products are hidden from sale. |
| 279 | Cancel |
| 284 | Saving… |
| 284 | Save |
| 300 | This product may already exist |
| 307 | Your shop already has: |
| 313 | • ${match.name} |
| 314 | ${match.sameBarcode ?  |
| 318 | and ${matches.length - 5} more |
| 321 | Creating it again makes a separate product with its own  |
| 322 | stock. Go back to edit, or create it anyway. |
| 330 | Go back |

### `lib/features/customers/customer_management_native.dart` (26)

| Line | Text |
| ---: | --- |
| 63 | Customers could not be refreshed. Showing available offline data. |
| 96 | Customers could not be refreshed. Showing available offline data. |
| 164 | Customers / Khata |
| 180 | Add customer |
| 188 | Retry |
| 198 | Could not open customers: ${snap.error} |
| 213 | Search name or phone |
| 221 | No customers yet. Add the first customer. |
| 236 | ${c.phone ??  |
| 236 |  • Inactive |
| 243 | Clear |
| 244 | ${formatPkr(c.balanceMinor)} due |
| 289 | Customer saved. |
| 294 | Customer could not be saved. |
| 330 | Add customer |
| 330 | Edit customer |
| 339 | Name * |
| 344 | Phone |
| 348 | Address |
| 353 | Notes |
| 361 | Credit limit (optional) |
| 362 | Rs  |
| 368 | Active |
| 382 | Cancel |
| 392 | Name and a valid credit limit are required. |
| 408 | Save |

### `lib/features/sync/sync_attention_native.dart` (23)

| Line | Text |
| ---: | --- |
| 37 | Sync issues |
| 44 | Could not open local data. |
| 78 | No sync issues. |
| 84 | Nothing here was deleted. Records stay on this device until  |
| 85 | they sync. |
| 107 | This record could not sync. |
| 108 | Code: ${operation.errorCode ??  |
| 109 | ${flagged ?  |
| 110 | ${_time(at)} • attempts ${operation.retryCount} |
| 117 | Acknowledge |
| 127 | Retry |
| 136 | Sale • ${billReference(operation.entityId)} |
| 137 | Bill void |
| 138 | Bill return |
| 139 | Customer payment |
| 140 | Purchase |
| 141 | Supplier payment |
| 142 | Expense |
| 143 | Stock adjustment |
| 148 | Waiting for authorisation |
| 149 | Needs attention |
| 153 | ${at.day.toString().padLeft(2,  |
| 154 | ${at.hour.toString().padLeft(2,  |

### `lib/features/sales/sales_management_native.dart` (19)

| Line | Text |
| ---: | --- |
| 63 | Sales & Returns |
| 68 | Sales could not be opened. |
| 131 | Return saved locally. |
| 138 | Return could not be saved. Check quantities and try again. |
| 151 | Void sale |
| 154 | Reason * |
| 159 | Cancel |
| 163 | Void Sale |
| 185 | Sale void recorded locally. |
| 193 | Void is allowed only for an owner within 15 minutes and before any return. |
| 226 | Return items |
| 237 | ${widget.detail.lines[i].name} (sold ${quantityToInput(widget.detail.lines[i].quantity)}) |
| 242 | Refund method |
| 244 | Cash |
| 247 | Digital |
| 251 | Udhaar adjustment |
| 258 | Reason * |
| 266 | Cancel |
| 281 | Save Return |

### `lib/features/receipts/receipt_view.dart` (16)

| Line | Text |
| ---: | --- |
| 26 | ${formatDisplayDateTime(receipt.dateTime)} • ${receipt.cashier} |
| 27 | Customer: ${receipt.customer} |
| 28 | Completed |
| 36 | ${formatLineQuantity(line.quantity, line.measureUnit)} × ${line.name}  ${formatPkr(line.total)} |
| 39 |   @ ${line.measureUnit == null ?  |
| 44 | Subtotal ${formatPkr(receipt.subtotal)} |
| 46 | Discount -${formatPkr(receipt.discount)} |
| 47 | Total ${formatPkr(receipt.total)} |
| 48 | Returned ${formatPkr(receipt.returned)} |
| 49 | Net ${formatPkr(receipt.netTotal)} |
| 51 | ${paymentMethodLabel(row.key)}: ${formatPkr(row.value)} |
| 53 | Received ${formatPkr(receipt.received!)} |
| 54 | Change ${formatPkr(receipt.change)} |
| 71 | Receipt |
| 76 | Print / Reprint |
| 88 | Close |

### `lib/app/cashier_login_panel.dart` (14)

| Line | Text |
| ---: | --- |
| 77 | Enter the cashier’s 4 to 8 digit PIN. |
| 99 | Cashier authenticated. Offline billing remains available until local expiry. |
| 106 | Login failed or temporarily locked. |
| 128 | Could not load cashiers. Please try again. |
| 129 | Retry |
| 142 | Dukaan Pro — ${widget.shopName} |
| 148 | No cashier has been created yet. |
| 149 | No active cashier is available. |
| 152 | Ask the owner to sign in and add a cashier. |
| 161 | Manage cashiers |
| 190 | Signing in… |
| 190 | Start Shift / Login |
| 198 | Hide cashier setup |
| 198 | Manage cashiers |

### `lib/app/owner_cashier_setup_panel.dart` (12)

| Line | Text |
| ---: | --- |
| 39 | Enter the cashier name. |
| 43 | PIN must contain 4 to 8 digits. |
| 47 | PINs do not match. |
| 74 | Could not create the cashier. Please try again. |
| 98 | Could not update the cashier. Please try again. |
| 119 | Cashiers |
| 136 | Active |
| 136 | Disabled |
| 146 | Cashier name |
| 154 | Numeric PIN |
| 162 | Confirm PIN |
| 166 | Creating… |

### `lib/features/pos/measured_quantity_picker.dart` (12)

| Line | Text |
| ---: | --- |
| 36 | Only $available in stock. |
| 37 | Only $available available. |
| 122 |  • Available ${formatMeasureQuantity(product.stockQuantity < 0 ? 0 : product.stockQuantity, unit)} |
| 138 | ${measureUnitPriceLabel(formatPkr(product.salePriceMinor), unit)}$available |
| 146 | In bill: ${formatMeasureQuantity(widget.editing!, unit)} |
| 170 | Custom quantity |
| 197 | Quantity |
| 229 | Total — |
| 230 | Total ${formatPkr(lineTotalMinor(product.salePriceMinor, quantity))} |
| 231 |  for ${formatMeasureQuantity(quantity, unit)} |
| 259 | Cancel |
| 267 | Add |

### `lib/features/products/pack_family_editor.dart` (11)

| Line | Text |
| ---: | --- |
| 75 | Pack size ${i + 1} |
| 84 | Saved |
| 92 | Remove pack size |
| 103 | Pack size * |
| 110 | Barcode |
| 111 | Optional |
| 122 | Sale price * |
| 130 | Purchase cost |
| 139 | Opening stock (packs) |
| 145 | Low-stock alert (packs) |
| 160 | Add pack size |

### `lib/app/owner_access.dart` (8)

| Line | Text |
| ---: | --- |
| 36 | Owner access required |
| 41 | Owner mode is locked on this device. Ask the owner to unlock it. |
| 82 | Wrong owner password. |
| 87 | Could not check the password. Check your connection. |
| 112 | Owner mode is locked. Enter the owner password. |
| 117 | Owner password |
| 129 | Checking… |
| 129 | Unlock owner mode |

### `lib/features/products/measure_preset_editor.dart` (7)

| Line | Text |
| ---: | --- |
| 45 | That quick quantity is already in the list. |
| 50 | Use at most $maxMeasurePresets quick quantities. |
| 61 | Keep at least one quick quantity. |
| 84 | Remove |
| 105 | Quick quantities full ($maxMeasurePresets) |
| 106 | Add quick quantity |
| 124 | Add |

### `lib/app/cashier_resume_gate_native.dart` (6)

| Line | Text |
| ---: | --- |
| 193 | This device could not be opened. Try again. |
| 205 | Owner mode could not be closed safely on this device, so cashier mode was not opened. Restart the app and try again. |
| 232 | Cashier |
| 306 | Owner sign in |
| 341 | Back to cashier login |
| 364 | Try again |

### `lib/features/pos/pack_selector.dart` (5)

| Line | Text |
| ---: | --- |
| 21 | $count ${thousandths == quantityScale ?  |
| 61 | Cancel |
| 82 | Stock not tracked |
| 99 | ${formatPkr(variant.salePriceMinor)} • $stock |
| 116 | Add |

### `lib/features/pos/pos_runtime_web.dart` (5)

| Line | Text |
| ---: | --- |
| 26 | $shopName • POS preview |
| 43 | Cashier authentication successful |
| 47 | $cashierName is signed in. |
| 50 | The offline POS database is available on Android and Windows. Chrome remains an auth and onboarding preview target. |
| 56 | End preview session |

### `lib/features/pos/pos_runtime_native.dart` (3)

| Line | Text |
| ---: | --- |
| 269 | The local POS could not be opened. Check this device’s local storage and try again. |
| 275 | Retry |
| 277 | Log out |

### `lib/app/dukaan_pro_app.dart` (2)

| Line | Text |
| ---: | --- |
| 14 | Dukaan Pro |
| 23 | Dukaan Pro is not connected. Provide SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define. |

### `lib/features/customers/customer_management_web.dart` (2)

| Line | Text |
| ---: | --- |
| 15 | Customers / Khata |
| 18 | Customer offline management is available on Android and Windows. |

### `lib/features/expenses/expense_management_web.dart` (2)

| Line | Text |
| ---: | --- |
| 15 | Expenses |
| 18 | Offline expense management is available on Android and Windows. |

### `lib/features/inventory/inventory_management_web.dart` (2)

| Line | Text |
| ---: | --- |
| 15 | Inventory |
| 17 | Inventory management is available on Windows and Android. |

### `lib/features/products/product_management_web.dart` (2)

| Line | Text |
| ---: | --- |
| 17 | Products |
| 22 | Product management uses the native Drift catalog. Open Dukaan Pro on Windows or Android. |

### `lib/features/purchases/purchase_management_web.dart` (2)

| Line | Text |
| ---: | --- |
| 15 | Suppliers & Purchases |
| 17 | Purchasing is available on Android and Windows. |

### `lib/features/reports/owner_dashboard_web.dart` (2)

| Line | Text |
| ---: | --- |
| 15 | $shopName Dashboard |
| 18 | Offline owner reports are available on Android and Windows. |

### `lib/features/sales/sales_management_web.dart` (2)

| Line | Text |
| ---: | --- |
| 16 | Sales |
| 18 | Sales management is available on Windows and Android. |

### `lib/features/sync/sync_attention_web.dart` (2)

| Line | Text |
| ---: | --- |
| 15 | Sync issues |
| 17 | Sync issues are available on Android and Windows. |

### `lib/core/ui/pos_ui.dart` (1)

| Line | Text |
| ---: | --- |
| 277 | * Required |

## B. Domain, service and policy messages shown to users (map to ARB at the UI boundary; keep the English source text for logs and tests)

### `lib/features/sales/application/local_sale_service.dart` (19)

| Line | Text |
| ---: | --- |
| 37 | Shop does not exist |
| 49 | Device is not active for this shop |
| 54 | Cashier is not active for this shop |
| 58 | Cart must not be empty |
| 64 | Payment amounts must be greater than zero |
| 76 | Quantities must be greater than zero |
| 80 | Discount cannot be negative |
| 92 | Product is not active for this shop |
| 97 | Product prices cannot be negative |
| 107 | Measured product requires kg or liter |
| 112 | Piece products are sold in whole units |
| 117 | Discount exceeds line value |
| 141 | Insufficient stock |
| 147 | Sale total cannot be negative |
| 152 | Payment total must equal sale total |
| 161 | Credit payment requires a customer |
| 174 | Credit customer is not active for this shop |
| 191 | Customer credit limit exceeded |
| 446 | Product requires a display name |

### `lib/features/products/product_management_service.dart` (18)

| Line | Text |
| ---: | --- |
| 30 | This product is already in your shop |
| 50 | Product name is required |
| 53 | Category is required |
| 110 | it could not be saved |
| 123 | Product family name is required |
| 126 | Category is required |
| 129 | Add at least one pack size |
| 135 | Every pack needs a size label |
| 138 | Pack size $label is listed twice |
| 144 | Barcode $barcode is already used in this shop |
| 148 | Enter a sale price for $label |
| 151 | Prices cannot be negative |
| 158 | Stock for $label must be whole packs |
| 169 | Loose products are sold by weight (kg) or volume (L) |
| 175 | Use at most $maxMeasurePresets quick quantities |
| 180 | Quick quantities are not valid |
| 186 | Prices cannot be negative |
| 189 | Stock values cannot be negative |

### `lib/sync/sync_failure.dart` (14)

| Line | Text |
| ---: | --- |
| 48 | The cloud rejected this record as invalid or out of date. |
| 49 | A different version of this record is already in the cloud. |
| 50 | This change conflicts with the cloud and cannot be applied. |
| 53 | This device or cashier is no longer authorised. |
| 54 | This device or session is not authorised to sync. |
| 55 | The sign-in session expired. |
| 56 | The sign-in session is missing. |
| 57 | The sign-in session expired. |
| 58 | This device or session is not authorised to sync. |
| 73 | This record was saved by an older app version and cannot be  |
| 74 | sent safely. |
| 85 | No connection to the cloud. It will retry automatically. |
| 112 | The cloud is temporarily unavailable. It will retry  |
| 120 | The cloud could not accept this record. |

### `lib/features/products/product_management_models.dart` (11)

| Line | Text |
| ---: | --- |
| 4 | Piece |
| 5 | Pack |
| 7 | Gram |
| 8 | Liter |
| 9 | Bottle |
| 10 | Carton |
| 11 | Dozen |
| 12 | Bag |
| 207 | Pack $failedLabel was not created: $reason.  |
| 208 | ${created.length} size(s) already saved;  |
| 209 | press Create again to finish without duplicating them. |

### `lib/features/pos/pos_state.dart` (8)

| Line | Text |
| ---: | --- |
| 122 | Enter a valid payment. |
| 125 | Payment total must equal the sale total. |
| 134 | Cash received is less than the total. |
| 216 | Cart must not be empty |
| 229 | $rupees.${paisa.toString().padLeft(2,  |
| 243 | ${minor < 0 ?  |
| 243 | }Rs ${absolute ~/ 100}. |
| 244 | ${(absolute % 100).toString().padLeft(2,  |

### `lib/subscription/entitlement_policy.dart` (8)

| Line | Text |
| ---: | --- |
| 54 | Online subscription verification is required. |
| 64 | Stored subscription proof is invalid. Verify online. |
| 72 | Device time changed significantly. Connect online to verify. |
| 85 | Shop subscription needs renewal. Please contact the owner. |
| 94 | Grace period active. Online verification is needed. |
| 103 | Subscription ending soon. |
| 113 | Subscription verified. |
| 172 | Subscription verified. |

### `lib/core/errors/safe_error_message.dart` (5)

| Line | Text |
| ---: | --- |
| 6 | invalid login |
| 7 | invalid credentials |
| 8 | Wrong email or password. |
| 10 | refresh token |
| 11 | Your session expired. Please sign in again. |

### `lib/database/repositories/sync_queue_repository.dart` (5)

| Line | Text |
| ---: | --- |
| 81 | An earlier record it depends on needs attention. |
| 143 | Saved in the cloud, but it broke a shop rule  |
| 144 | )}). Please  |
| 145 | review it. |
| 416 | customer credit limit exceeded |

### `lib/auth/auth_session_controller.dart` (4)

| Line | Text |
| ---: | --- |
| 67 | Sign in did not create a valid session. |
| 104 | Your shop membership is inactive. |
| 122 | This device has been revoked. |
| 155 | Your session expired. Please sign in again. |

### `lib/core/images/product_image_processing.dart` (4)

| Line | Text |
| ---: | --- |
| 28 | The selected file is empty. |
| 31 | The selected image is too large. |
| 36 | Choose a JPG, PNG or WebP product image. |
| 86 | The selected image is too large. |

### `lib/auth/device_mode.dart` (3)

| Line | Text |
| ---: | --- |
| 173 | This device must be set up for cashier mode once. Ask the owner to sign in. |
| 182 | The offline cashier session expired. Connect to the internet and sign in again. |
| 191 | Offline cashier access is unavailable because this shop or device no longer matches. Connect to the internet and sign in again. |

### `lib/features/sales/domain/bill_reference.dart` (2)

| Line | Text |
| ---: | --- |
| 10 | Bill #$invoice |
| 11 | Bill #${billCode(saleId)} |

### `lib/features/sales/domain/sale_draft.dart` (2)

| Line | Text |
| ---: | --- |
| 68 | SaleValidationException: $message |
| 78 | CheckoutConflict: sale $saleId is already saved with different content |

### `lib/subscription/entitlement.dart` (2)

| Line | Text |
| ---: | --- |
| 31 | {${keys.map((k) =>  |
| 75 | Invalid entitlement interval |

### `lib/features/purchases/local_purchase_service.dart` (1)

| Line | Text |
| ---: | --- |
| 97 | Purchase payments must be positive cash or digital amounts. |

### `lib/features/receipts/receipt_model.dart` (1)

| Line | Text |
| ---: | --- |
| 39 | Completed |

### `lib/features/receipts/receipt_printer.dart` (1)

| Line | Text |
| ---: | --- |
| 27 | No receipt printer is configured. You can retry from Sales. |

### `lib/features/reports/report_models.dart` (1)

| Line | Text |
| ---: | --- |
| 50 | Custom |

### `lib/features/sales/application/local_sale_void_service.dart` (1)

| Line | Text |
| ---: | --- |
| 66 | The 15-minute void window has expired. Use a return instead. |

### `lib/sync/sync_health.dart` (1)

| Line | Text |
| ---: | --- |
| 47 | $prefix-${const Uuid().v4()} |

## C. Formatting helpers (dates, payment labels, relative dates): become locale-aware functions

### `lib/core/format/display_format.dart` (23)

| Line | Text |
| ---: | --- |
| 6 | Jan |
| 7 | Feb |
| 8 | Mar |
| 9 | Apr |
| 10 | May |
| 11 | Jun |
| 12 | Jul |
| 13 | Aug |
| 14 | Sep |
| 15 | Oct |
| 16 | Nov |
| 17 | Dec |
| 23 | ${local.day} ${_months[local.month - 1]} ${local.year} |
| 31 | $hour:$minute ${local.hour < 12 ?  |
| 46 | Today, $time |
| 47 | Yesterday, $time |
| 48 | Tomorrow, $time |
| 49 | ${formatDisplayDate(local)}, $time |
| 55 | Cash |
| 56 | Digital |
| 57 | Udhaar |
| 58 | Split |
| 59 | No payment |

### `lib/core/format/measure_format.dart` (6)

| Line | Text |
| ---: | --- |
| 14 | $sign$absolute ${unit.fractionLabel} |
| 15 | $sign${formatDisplayQuantity(absolute)} ${unit.wholeLabel} |
| 29 | $name $label |
| 60 | Enter a valid quantity. |
| 61 | Quantity must be more than zero. |
| 62 | Quantity is too large. |

## D. Internal, SQL or never shown to users: **do not translate** (listed so reviewers can confirm)

### `lib/database/app_database.dart` (6)

| Line | Text |
| ---: | --- |
| 85 | ON shop_products(shop_id, master_product_id)  |
| 86 | WHERE master_product_id IS NOT NULL |
| 121 | ON sales(shop_id, invoice_number) |
| 170 | WHERE entity_type IN ('shopProducts', 'saleItems') |
| 178 | ON shop_products(shop_id, master_product_id)  |
| 179 | WHERE master_product_id IS NOT NULL |

### `lib/subscription/entitlement_verifier.dart` (5)

| Line | Text |
| ---: | --- |
| 15 | Unsupported signature algorithm |
| 17 | SHA-256/RSA |
| 24 | Invalid entitlement signature |
| 27 | Entitlement belongs to another shop |
| 30 | Entitlement belongs to another device |

### `lib/features/inventory/drift_inventory_repository.dart` (2)

| Line | Text |
| ---: | --- |
| 138 | Unnamed product |
| 147 | Invoice $purchaseInvoice |

### `lib/features/products/drift_product_management_repository.dart` (2)

| Line | Text |
| ---: | --- |
| 33 | Uncategorized |
| 44 | Uncategorized |

### `lib/sync/sale_payload_codec.dart` (2)

| Line | Text |
| ---: | --- |
| 14 | AmbiguousTimestampPayload: $path="$value" has no UTC offset  |
| 15 | (queued before R1.2); not uploaded |

### `lib/auth/device_credential.dart` (1)

| Line | Text |
| ---: | --- |
| 49 | DeviceCredential(shop: $shopId, device: $deviceId) |

### `lib/core/config/app_environment.dart` (1)

| Line | Text |
| ---: | --- |
| 15 | Production requires SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define. |

### `lib/database/tables/organization_tables.dart` (1)

| Line | Text |
| ---: | --- |
| 11 | Asia/Karachi |

### `lib/features/shop/supabase_shop_bootstrap_gateway.dart` (1)

| Line | Text |
| ---: | --- |
| 13 | shop_id, role, shops(name) |

