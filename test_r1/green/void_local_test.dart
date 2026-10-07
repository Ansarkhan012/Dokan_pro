// R1.3 (F-2) local void: one atomic transaction appends exactly one
// compensation per original effect and queues a v2 payload that carries the
// very ids written locally (movement per sale item, Udhaar refund), so the
// server can store the same rows instead of generating its own.
@Tags(['r1-green'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:flutter_test/flutter_test.dart';

const _opening = 10000;

Future<AppDatabase> _shopDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  final t = DateTime.utc(2026, 9, 1);
  await db.into(db.shops).insert(ShopsCompanion.insert(
    id: 'shop', name: 'Shop', phone: '', address: '',
    subscriptionPlan: SubscriptionPlan.trial,
    subscriptionStatus: SubscriptionStatus.trial,
    createdAt: t, updatedAt: t,
  ));
  await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
    id: 'm', shopId: 'shop', userId: 'owner', role: ShopRole.owner, createdAt: t,
  ));
  await db.into(db.devices).insert(DevicesCompanion.insert(
    id: 'device', shopId: 'shop', deviceName: 'd',
    deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: t,
  ));
  // Rice is loose (U1 measured, Rs 120/kg) so its 1.5 kg line is a valid
  // fractional quantity; coke is a piece product sold in whole units.
  for (final (id, price, measured) in [('coke', 18000, false), ('rice', 12000, true)]) {
    await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
      id: id, shopId: 'shop', customName: Value(id),
      purchasePrice: 10000, salePrice: price, createdAt: t, updatedAt: t,
      unit: Value(measured ? 'kg' : 'piece'),
      sellMode: Value(measured ? SellMode.measured.name : SellMode.piece.name),
    ));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
      id: 'opening-$id', shopId: 'shop', productId: id,
      type: InventoryMovementType.openingStock, quantity: _opening, createdBy: 'owner', createdAt: t,
    ));
  }
  await db.into(db.customers).insert(CustomersCompanion.insert(
    id: 'c', shopId: 'shop', name: 'Ahmed', createdAt: t, updatedAt: t,
  ));
  return db;
}

final _soldAt = DateTime.utc(2026, 9, 30, 5);

Future<String> _sell(AppDatabase db, List<SalePaymentDraft> payments, {String? customerId}) async =>
    (await LocalSaleService(db, const UuidV7Generator(), clock: () => _soldAt).createSale(SaleDraft(
      shopId: 'shop',
      cashierId: 'owner',
      deviceId: 'device',
      customerId: customerId,
      lines: const [
        SaleLineDraft(productId: 'coke', quantity: 2000),
        SaleLineDraft(productId: 'rice', quantity: 1500),
      ],
      payments: payments,
    )))
        .saleId;

Future<String> _void(AppDatabase db, String saleId) =>
    LocalSaleVoidService(db, const UuidV7Generator(), clock: () => _soldAt.add(const Duration(minutes: 5)))
        .voidSale(shopId: 'shop', saleId: saleId, ownerId: 'owner', deviceId: 'device', reason: 'wrong bill');

Future<int> _stock(AppDatabase db, String product) async => (await db
        .customSelect('select coalesce(sum(quantity),0) q from inventory_movements where product_id=?',
            variables: [Variable(product)])
        .getSingle())
    .read<int>('q');

Future<int> _balance(AppDatabase db) async => (await db
        .customSelect("select coalesce(sum(case when type in ('openingBalance','creditSale','adjustment') "
            "then amount else -amount end),0) b from customer_ledger_entries where customer_id='c'")
        .getSingle())
    .read<int>('b');

Future<Map<String, dynamic>> _voidPayload(AppDatabase db, String voidId) async => jsonDecode(
      (await (db.select(db.syncOperations)..where((t) => t.entityId.equals(voidId))).getSingle()).payload,
    ) as Map<String, dynamic>;

const _total = 36000 + 18000; // 2 x Rs 180 + 1.5 x Rs 120

void main() {
  test('B: a cash void restores stock with exactly one compensation per sale item, ids in the v2 payload', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final saleId = await _sell(db, const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: _total)]);
    expect(await _stock(db, 'coke'), _opening - 2000);
    final voidId = await _void(db, saleId);
    expect(await _stock(db, 'coke'), _opening);
    expect(await _stock(db, 'rice'), _opening);

    final compensations = await (db.select(db.inventoryMovements)..where((t) => t.referenceId.equals(voidId))).get();
    expect(compensations, hasLength(2));
    expect(compensations.every((m) => m.type == InventoryMovementType.returnIn && m.referenceType == 'sale_void'), isTrue);
    final items = await (db.select(db.saleItems)..where((t) => t.saleId.equals(saleId))).get();

    final payload = await _voidPayload(db, voidId);
    expect(payload['version'], 2);
    final ids = (payload['movement_ids'] as Map).cast<String, String>();
    expect(ids.keys.toSet(), items.map((i) => i.id).toSet(), reason: 'one id per original sale item');
    expect(ids.values.toSet(), compensations.map((m) => m.id).toSet(), reason: 'the queued ids are the local rows');
    for (final item in items) {
      final m = compensations.singleWhere((m) => m.id == ids[item.id]);
      expect((m.productId, m.quantity), (item.productId, item.quantity));
    }
    expect(payload['refund_ledger_id'], isNull);
    expect((payload['void'] as Map)['payment_breakdown'], {'cash': _total});
    expect(await db.select(db.customerLedgerEntries).get(), isEmpty);
    // Original records are retained, not deleted or rewritten.
    expect(await (db.select(db.saleItems)..where((t) => t.saleId.equals(saleId))).get(), hasLength(2));
    expect(await (db.select(db.inventoryMovements)..where((t) => t.referenceId.equals(saleId))).get(), hasLength(2));
  });

  test('C: an Udhaar void appends exactly one refund, carried in the payload, and clears the balance', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final saleId = await _sell(db, const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: _total)],
        customerId: 'c');
    expect(await _balance(db), _total);
    final voidId = await _void(db, saleId);
    expect(await _balance(db), 0);
    final refunds = await (db.select(db.customerLedgerEntries)
          ..where((t) => t.type.equals(CustomerLedgerType.refund.name)))
        .get();
    expect(refunds, hasLength(1));
    expect(refunds.single.amount, _total);
    final payload = await _voidPayload(db, voidId);
    expect(payload['refund_ledger_id'], refunds.single.id);
    // The original credit-sale entry is retained.
    expect(await (db.select(db.customerLedgerEntries)..where((t) => t.saleId.equals(saleId))).get(), hasLength(2));
  });

  test('D: a Cash + Digital + Udhaar void refunds only the Udhaar part, once', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final saleId = await _sell(db, const [
      SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 20000),
      SalePaymentDraft(method: PaymentMethod.digital, amountMinor: 14000),
      SalePaymentDraft(method: PaymentMethod.credit, amountMinor: 20000),
    ], customerId: 'c');
    final voidId = await _void(db, saleId);
    final refunds = await (db.select(db.customerLedgerEntries)
          ..where((t) => t.type.equals(CustomerLedgerType.refund.name)))
        .get();
    expect(refunds.single.amount, 20000);
    expect(await _balance(db), 0);
    expect(await _stock(db, 'coke'), _opening);
    final payload = await _voidPayload(db, voidId);
    expect((payload['void'] as Map)['payment_breakdown'], {'cash': 20000, 'digital': 14000, 'credit': 20000});
    expect((payload['void'] as Map)['amount'], _total);
    expect(payload['refund_ledger_id'], refunds.single.id);
  });

  test('a second void of the same sale is refused and writes nothing', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final saleId = await _sell(db, const [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: _total)]);
    await _void(db, saleId);
    final before = await db.customSelect('select count(*) c from inventory_movements').getSingle();
    await expectLater(_void(db, saleId), throwsA(anything));
    final after = await db.customSelect('select count(*) c from inventory_movements').getSingle();
    expect(after.data, before.data);
    expect(await _stock(db, 'coke'), _opening);
  });

  test('a failure inside the void transaction leaves no half-voided aggregate', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final saleId = await _sell(db, const [SalePaymentDraft(method: PaymentMethod.credit, amountMinor: _total)],
        customerId: 'c');
    await db.customStatement(
      "create temp trigger r1_fail_void_outbox before insert on sync_operations "
      "when new.entity_type='sale_void' begin select raise(abort, 'simulated local failure'); end",
    );
    await expectLater(_void(db, saleId), throwsA(anything));
    expect(await db.select(db.saleVoids).get(), isEmpty);
    expect(await (db.select(db.inventoryMovements)..where((t) => t.referenceType.equals('sale_void'))).get(), isEmpty);
    expect(await (db.select(db.customerLedgerEntries)..where((t) => t.type.equals('refund'))).get(), isEmpty);
    expect(await (db.select(db.auditLogs)..where((t) => t.action.equals('sale.voided'))).get(), isEmpty);
    expect(await _stock(db, 'coke'), _opening - 2000);
    expect(await _balance(db), _total);
  });
}
