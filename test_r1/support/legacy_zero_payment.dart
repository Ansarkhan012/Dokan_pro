// Crafts the aggregate that PosWorkspace cash mode queued for a Rs 0 total
// BEFORE R1.1: a committed sale with one cash payment row of amount 0.
//
// R1.1 made that row impossible to create through LocalSaleService (every
// payment row must be > 0; a zero-total sale has no payment rows), but devices
// upgraded from earlier builds can still hold such queued operations, and the
// server must keep rejecting them (R1.5, DPV01). The scenarios that exercise
// that rejection therefore build it here: the zero-total sale is committed
// through the real service, then exactly the row and payload entry the old
// code wrote are added in one local transaction.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/sync/sync_time.dart';

Future<void> addLegacyZeroCashPayment(AppDatabase db, String saleId) =>
    db.transaction(() async {
      final sale = await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingle();
      if (sale.grandTotal != 0) {
        throw StateError('legacy zero-payment shape needs a zero-total sale');
      }
      final payment = SalePayment(
        id: const UuidV7Generator().next(),
        saleId: saleId,
        shopId: sale.shopId,
        paymentMethod: PaymentMethod.cash,
        amount: 0,
        createdAt: sale.createdAt,
      );
      await db.into(db.salePayments).insert(payment);
      final operation = await (db.select(db.syncOperations)
            ..where((t) => t.entityType.equals('sale_aggregate') & t.entityId.equals(saleId)))
          .getSingle();
      final payload = jsonDecode(operation.payload) as Map<String, dynamic>;
      // Timestamps use the explicit-UTC wire form (R1.2), so the Rs 0 row
      // stays the only defect in this payload.
      payload['payments'] = [payment.toJson(serializer: SyncTime.payloadSerializer)];
      await (db.update(db.syncOperations)..where((t) => t.id.equals(operation.id)))
          .write(SyncOperationsCompanion(payload: Value(jsonEncode(payload))));
    });
