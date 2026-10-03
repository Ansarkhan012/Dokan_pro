// R1.5 owner-visible Needs Attention: the POS status chip never says Synced
// while an operation needs attention and shows the cashier no technical
// detail; the owner's Sync issues list shows the affected record, the safe
// reason and the stable code, and offers only Retry / Acknowledge.
@Tags(['r1-green'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/pos/pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/bill_reference.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/features/sync/sync_attention_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pos_fixture.dart';

const _catalog = PosCatalogSnapshot(products: [coke], categories: [], customers: []);

Future<String> _sell(AppDatabase db) async =>
    (await LocalSaleService(db, const UuidV7Generator()).createSale(const SaleDraft(
      shopId: shopId,
      cashierId: ownerId,
      deviceId: deviceId,
      lines: [SaleLineDraft(productId: cokeId, quantity: 1000)],
      payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: cokePrice)],
    ))).saleId;

Future<void> _mark(AppDatabase db, String saleId, SyncOperationsCompanion values) =>
    (db.update(db.syncOperations)..where((t) => t.entityId.equals(saleId))).write(values);

const _needsAttention = SyncOperationsCompanion(
  status: Value(SyncStatus.needsAttention),
  errorClass: Value('permanent'),
  errorCode: Value('DPV01'),
  attentionReason: Value('The cloud rejected this record as invalid or out of date.'),
  lastError: Value('PostgrestException(message: DPV01: invalid sale payment, code: DPV01)'),
);

Future<void> _dispose(WidgetTester tester, PosHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
  await h.db.close();
}

void main() {
  testWidgets('cashier POS shows Needs attention, never Synced, and no technical detail', (tester) async {
    final h = await PosHarness.open(mode: GatewayMode.hang);
    final sale = await _sell(h.db);
    await _mark(h.db, sale, _needsAttention);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: PosWorkspace(
        shopName: 'Shop',
        cashierName: 'cashier',
        initialCatalog: _catalog,
        committer: h.committer,
        salesHistory: DriftSalesHistoryRepository(h.db, shopId: shopId),
        offline: false,
        initialHasPendingSync: false,
        onLogout: () async {},
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Synced'), findsNothing);
    expect(find.textContaining('DPV01'), findsNothing);
    expect(find.textContaining('invalid sale payment'), findsNothing);
    await _dispose(tester, h);
  });

  testWidgets('owner list shows record, reason and code; Retry re-queues; Acknowledge clears a flag', (tester) async {
    final h = await PosHarness.open(mode: GatewayMode.hang);
    final rejected = await _sell(h.db);
    final flagged = await _sell(h.db);
    await _mark(h.db, rejected, _needsAttention);
    await _mark(h.db, flagged, const SyncOperationsCompanion(
      status: Value(SyncStatus.synced),
      errorClass: Value('flagged'),
      errorCode: Value('credit_limit_exceeded'),
      attentionReason: Value('Saved in the cloud, but it broke a shop rule (customer credit limit exceeded). Please review it.'),
    ));
    final queue = SyncQueueRepository(h.db, shopId: shopId);
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SyncAttentionView(queue: queue, onRetried: () => retried++)),
    ));
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    await settle();
    expect(find.text('Sale • ${billReference(rejected)}'), findsOneWidget);
    expect(find.text('Sale • ${billReference(flagged)}'), findsOneWidget);
    expect(find.textContaining('Code: DPV01'), findsOneWidget);
    expect(find.textContaining('invalid or out of date'), findsOneWidget);
    expect(find.textContaining('Code: credit_limit_exceeded'), findsOneWidget);
    expect(find.textContaining('PostgrestException'), findsNothing, reason: 'no raw server error');
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.text('Retry'));
    await settle();
    expect(retried, 1);
    final requeued =
        await (h.db.select(h.db.syncOperations)..where((t) => t.entityId.equals(rejected))).getSingle();
    expect(requeued.status, SyncStatus.pending);

    await tester.tap(find.text('Acknowledge'));
    await settle();
    expect(find.text('No sync issues.'), findsOneWidget);
    await _dispose(tester, h);
  });
}
