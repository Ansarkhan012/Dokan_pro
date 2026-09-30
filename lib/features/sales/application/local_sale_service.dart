import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/domain/enums.dart';
import '../../../core/ids/id_generator.dart';
import '../../../database/app_database.dart';
import '../../../subscription/entitlement_policy.dart';
import '../domain/sale_draft.dart';

final class LocalSaleService {
  LocalSaleService(
    this.db,
    this.ids, {
    DateTime Function()? clock,
    this._authorizer = const AllowFinancialMutations(),
  }) : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final IdGenerator ids;
  final DateTime Function() _clock;
  final FinancialMutationAuthorizer _authorizer;

  Future<CreatedSale> createSale(SaleDraft draft) async {
    await _authorizer.authorize(shopId: draft.shopId, deviceId: draft.deviceId);
    return db.transaction(() async {
      // Replay of a committed checkout id: return it or refuse it, never
      // write a second aggregate (first statement, inside the transaction).
      if (draft.saleId case final checkoutId?) {
        final existing = await _existingCheckout(checkoutId, draft);
        if (existing != null) return existing;
      }
      final now = _clock().toUtc();
      final shop = await (db.select(
        db.shops,
      )..where((t) => t.id.equals(draft.shopId))).getSingleOrNull();
      if (shop == null) {
        throw const SaleValidationException('Shop does not exist');
      }
      final device =
          await (db.select(db.devices)..where(
                (t) =>
                    t.id.equals(draft.deviceId) &
                    t.shopId.equals(draft.shopId) &
                    t.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (device == null) {
        throw const SaleValidationException(
          'Device is not active for this shop',
        );
      }
      if (!await _isActiveActor(draft.shopId, draft.cashierId)) {
        throw const SaleValidationException(
          'Cashier is not active for this shop',
        );
      }
      if (draft.lines.isEmpty) {
        throw const SaleValidationException('Cart must not be empty');
      }
      // Every payment row is a real tender (> 0). A zero-total sale has no
      // payment rows; the total check below rejects an empty list otherwise.
      if (draft.payments.any((p) => p.amountMinor <= 0)) {
        throw const SaleValidationException(
          'Payment amounts must be greater than zero',
        );
      }

      final saleId = draft.saleId ?? ids.next();
      final itemRows = <Map<String, Object?>>[];
      var subtotal = 0;
      var discountTotal = 0;
      for (final line in draft.lines) {
        if (line.quantity <= 0) {
          throw const SaleValidationException(
            'Quantities must be greater than zero',
          );
        }
        if (line.discountMinor < 0) {
          throw const SaleValidationException('Discount cannot be negative');
        }
        final product =
            await (db.select(db.shopProducts)..where(
                  (t) =>
                      t.id.equals(line.productId) &
                      t.shopId.equals(draft.shopId) &
                      t.isActive.equals(true),
                ))
                .getSingleOrNull();
        if (product == null) {
          throw const SaleValidationException(
            'Product is not active for this shop',
          );
        }
        if (product.salePrice < 0 || product.purchasePrice < 0) {
          throw const SaleValidationException(
            'Product prices cannot be negative',
          );
        }
        final gross = _scaledPrice(product.salePrice, line.quantity);
        if (line.discountMinor > gross) {
          throw const SaleValidationException('Discount exceeds line value');
        }
        final name = await _productName(product);
        final lineTotal = gross - line.discountMinor;
        subtotal += gross;
        discountTotal += line.discountMinor;
        itemRows.add({
          'id': ids.next(),
          'product_id': product.id,
          'product_name_snapshot': name,
          'barcode_snapshot': product.barcode,
          'quantity': line.quantity,
          'cost_price_snapshot': product.purchasePrice,
          'sale_price_snapshot': product.salePrice,
          'discount_amount': line.discountMinor,
          'line_total': lineTotal,
        });
        if (!shop.allowNegativeStock && product.stockTrackingEnabled) {
          final stock = await _stock(draft.shopId, product.id);
          if (stock < line.quantity) {
            throw const SaleValidationException('Insufficient stock');
          }
        }
      }
      final grandTotal = subtotal - discountTotal;
      if (grandTotal < 0) {
        throw const SaleValidationException('Sale total cannot be negative');
      }
      final paid = draft.payments.fold(0, (sum, p) => sum + p.amountMinor);
      if (paid != grandTotal) {
        throw const SaleValidationException(
          'Payment total must equal sale total',
        );
      }
      final creditTotal = draft.payments
          .where((p) => p.method == PaymentMethod.credit)
          .fold(0, (sum, p) => sum + p.amountMinor);
      if (creditTotal > 0) {
        if (draft.customerId == null) {
          throw const SaleValidationException(
            'Credit payment requires a customer',
          );
        }
        final customer =
            await (db.select(db.customers)..where(
                  (t) =>
                      t.id.equals(draft.customerId!) &
                      t.shopId.equals(draft.shopId) &
                      t.isActive.equals(true),
                ))
                .getSingleOrNull();
        if (customer == null) {
          throw const SaleValidationException(
            'Credit customer is not active for this shop',
          );
        }
        if (customer.creditLimit case final limit?) {
          final entries =
              await (db.select(db.customerLedgerEntries)..where(
                    (t) =>
                        t.shopId.equals(draft.shopId) &
                        t.customerId.equals(customer.id),
                  ))
                  .get();
          final balance = entries.fold<int>(
            0,
            (sum, entry) => sum + entry.amount.abs() * entry.type.balanceSign,
          );
          if (balance + creditTotal > limit) {
            throw const SaleValidationException(
              'Customer credit limit exceeded',
            );
          }
        }
      }

      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: saleId,
              shopId: draft.shopId,
              cashierId: draft.cashierId,
              customerId: Value(draft.customerId),
              deviceId: draft.deviceId,
              invoiceNumber: Value(draft.invoiceNumber),
              subtotal: subtotal,
              discountTotal: discountTotal,
              taxTotal: 0,
              grandTotal: grandTotal,
              paymentStatus: PaymentStatus.paid,
              saleStatus: SaleStatus.completed,
              createdAt: now,
            ),
          );
      for (final row in itemRows) {
        await db
            .into(db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                id: row['id']! as String,
                shopId: draft.shopId,
                saleId: saleId,
                productId: row['product_id']! as String,
                productNameSnapshot: row['product_name_snapshot']! as String,
                barcodeSnapshot: Value(row['barcode_snapshot'] as String?),
                quantity: row['quantity']! as int,
                costPriceSnapshot: row['cost_price_snapshot']! as int,
                salePriceSnapshot: row['sale_price_snapshot']! as int,
                discountAmount: row['discount_amount']! as int,
                lineTotal: row['line_total']! as int,
                createdAt: now,
              ),
            );
        await db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: ids.next(),
                shopId: draft.shopId,
                productId: row['product_id']! as String,
                type: InventoryMovementType.sale,
                quantity: -(row['quantity']! as int),
                referenceType: const Value('sale'),
                referenceId: Value(saleId),
                createdBy: draft.cashierId,
                deviceId: Value(draft.deviceId),
                createdAt: now,
              ),
            );
      }
      for (final payment in draft.payments) {
        await db
            .into(db.salePayments)
            .insert(
              SalePaymentsCompanion.insert(
                id: ids.next(),
                saleId: saleId,
                shopId: draft.shopId,
                paymentMethod: payment.method,
                amount: payment.amountMinor,
                reference: Value(payment.reference),
                createdAt: now,
              ),
            );
      }
      if (creditTotal > 0) {
        await db
            .into(db.customerLedgerEntries)
            .insert(
              CustomerLedgerEntriesCompanion.insert(
                id: ids.next(),
                shopId: draft.shopId,
                customerId: draft.customerId!,
                type: CustomerLedgerType.creditSale,
                amount: creditTotal,
                saleId: Value(saleId),
                createdBy: draft.cashierId,
                createdAt: now,
              ),
            );
      }
      final auditId = ids.next();
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              id: auditId,
              shopId: draft.shopId,
              userId: draft.cashierId,
              action: 'sale.completed',
              entityType: 'sale',
              entityId: saleId,
              newValue: Value(jsonEncode({'grand_total': grandTotal})),
              deviceId: Value(draft.deviceId),
              createdAt: now,
            ),
          );
      final operationId = ids.next();
      final payload = await _aggregatePayload(draft.shopId, saleId, auditId);
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operationId,
              shopId: draft.shopId,
              deviceId: draft.deviceId,
              entityType: 'sale_aggregate',
              entityId: saleId,
              operationType: SyncOperationType.create,
              payload: jsonEncode(payload),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return CreatedSale(
        saleId: saleId,
        syncOperationId: operationId,
        grandTotalMinor: grandTotal,
      );
    });
  }

  /// The committed sale for [checkoutId], if any. Same checkout content →
  /// that sale (idempotent); different content → [CheckoutConflict].
  Future<CreatedSale?> _existingCheckout(
    String checkoutId,
    SaleDraft draft,
  ) async {
    final sale = await (db.select(
      db.sales,
    )..where((t) => t.id.equals(checkoutId))).getSingleOrNull();
    if (sale == null) return null;
    if (sale.shopId != draft.shopId) throw CheckoutConflict(checkoutId);
    final items = await (db.select(
      db.saleItems,
    )..where((t) => t.saleId.equals(checkoutId))).get();
    final payments = await (db.select(
      db.salePayments,
    )..where((t) => t.saleId.equals(checkoutId))).get();
    final committed = _canonicalCheckout(
      shopId: sale.shopId,
      cashierId: sale.cashierId,
      deviceId: sale.deviceId,
      customerId: sale.customerId,
      invoiceNumber: sale.invoiceNumber,
      lines: [
        for (final item in items)
          [item.productId, item.quantity, item.discountAmount],
      ],
      payments: [
        for (final payment in payments)
          [payment.paymentMethod.name, payment.amount, payment.reference],
      ],
    );
    final requested = _canonicalCheckout(
      shopId: draft.shopId,
      cashierId: draft.cashierId,
      deviceId: draft.deviceId,
      customerId: draft.customerId,
      invoiceNumber: draft.invoiceNumber,
      lines: [
        for (final line in draft.lines)
          [line.productId, line.quantity, line.discountMinor],
      ],
      payments: [
        for (final payment in draft.payments)
          [payment.method.name, payment.amountMinor, payment.reference],
      ],
    );
    if (committed != requested) throw CheckoutConflict(checkoutId);
    final operation =
        await (db.select(db.syncOperations)..where(
              (t) =>
                  t.entityType.equals('sale_aggregate') &
                  t.entityId.equals(checkoutId),
            ))
            .getSingleOrNull();
    return CreatedSale(
      saleId: checkoutId,
      syncOperationId: operation?.id ?? '',
      grandTotalMinor: sale.grandTotal,
    );
  }

  /// Order-independent form of everything a [SaleDraft] carries. Each draft
  /// line is stored as one sale item and each payment as one payment row, so
  /// the committed rows reproduce it exactly; prices are not part of it (they
  /// come from the product at commit time and are snapshotted then).
  String _canonicalCheckout({
    required String shopId,
    required String cashierId,
    required String deviceId,
    required String? customerId,
    required String? invoiceNumber,
    required List<List<Object?>> lines,
    required List<List<Object?>> payments,
  }) {
    List<String> sorted(List<List<Object?>> rows) =>
        rows.map(jsonEncode).toList()..sort();
    return jsonEncode({
      'shop': shopId,
      'cashier': cashierId,
      'device': deviceId,
      'customer': customerId,
      'invoice': invoiceNumber,
      'lines': sorted(lines),
      'payments': sorted(payments),
    });
  }

  int _scaledPrice(int unitPrice, int quantity) =>
      (unitPrice * quantity + 500) ~/ 1000;
  Future<bool> _isActiveActor(String shopId, String actorId) async {
    final owner =
        await (db.select(db.shopUsers)..where(
              (t) =>
                  t.shopId.equals(shopId) &
                  t.userId.equals(actorId) &
                  t.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (owner != null) return true;
    return await (db.select(db.cashiers)..where(
              (t) =>
                  t.shopId.equals(shopId) &
                  t.id.equals(actorId) &
                  t.isActive.equals(true),
            ))
            .getSingleOrNull() !=
        null;
  }

  Future<String> _productName(ShopProduct product) async {
    if (product.customName case final name?) return name;
    if (product.masterProductId case final id?) {
      final master = await (db.select(
        db.masterProducts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (master != null) return master.name;
    }
    throw const SaleValidationException('Product requires a display name');
  }

  Future<int> _stock(String shopId, String productId) async {
    final rows =
        await (db.select(db.inventoryMovements)..where(
              (t) => t.shopId.equals(shopId) & t.productId.equals(productId),
            ))
            .get();
    var total = 0;
    for (final row in rows) {
      total += row.quantity;
    }
    return total;
  }

  Future<Map<String, Object?>> _aggregatePayload(
    String shopId,
    String saleId,
    String auditId,
  ) async {
    final sale = await (db.select(
      db.sales,
    )..where((t) => t.id.equals(saleId) & t.shopId.equals(shopId))).getSingle();
    final items = await (db.select(
      db.saleItems,
    )..where((t) => t.saleId.equals(saleId) & t.shopId.equals(shopId))).get();
    final payments = await (db.select(
      db.salePayments,
    )..where((t) => t.saleId.equals(saleId) & t.shopId.equals(shopId))).get();
    final movements =
        await (db.select(db.inventoryMovements)..where(
              (t) => t.referenceId.equals(saleId) & t.shopId.equals(shopId),
            ))
            .get();
    final ledger = await (db.select(
      db.customerLedgerEntries,
    )..where((t) => t.saleId.equals(saleId) & t.shopId.equals(shopId))).get();
    const serializer = ValueSerializer.defaults(
      serializeDateTimeValuesAsString: true,
    );
    return {
      'version': 1,
      'operation': 'sync_sale_transaction',
      'sale': sale.toJson(serializer: serializer),
      'sale_items': items.map((e) => e.toJson(serializer: serializer)).toList(),
      'payments': payments
          .map((e) => e.toJson(serializer: serializer))
          .toList(),
      'inventory_movements': movements
          .map((e) => e.toJson(serializer: serializer))
          .toList(),
      'customer_ledger_entries': ledger
          .map((e) => e.toJson(serializer: serializer))
          .toList(),
      'audit_id': auditId,
    };
  }
}
