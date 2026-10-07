// U1 product units and variants foundation, device side: integer measure
// formatting, the checkout selling-mode rules and snapshot, exact line
// rounding, and the cumulative partial-return refund rule.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/format/measure_format.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = DateTime.utc(2026, 10, 8, 5);

Future<AppDatabase> _shop() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.shops).insert(ShopsCompanion.insert(
    id: 'shop', name: 'Shop', phone: '', address: '',
    subscriptionPlan: SubscriptionPlan.trial,
    subscriptionStatus: SubscriptionStatus.trial,
    createdAt: _t, updatedAt: _t,
  ));
  await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
    id: 'm', shopId: 'shop', userId: 'owner', role: ShopRole.owner, createdAt: _t,
  ));
  await db.into(db.devices).insert(DevicesCompanion.insert(
    id: 'device', shopId: 'shop', deviceName: 'd',
    deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: _t,
  ));
  // Surf: an existing-style row that never sets the U1 columns.
  await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
    id: 'surf', shopId: 'shop', customName: const Value('Surf'),
    purchasePrice: 30000, salePrice: 35000, createdAt: _t, updatedAt: _t,
  ));
  // Atta: loose, Rs 130/kg. Oil: loose, Rs 175 per liter.
  for (final (id, name, unit, price) in [
    ('atta', 'Atta', 'kg', 13000),
    ('oil', 'Oil', 'liter', 17500),
  ]) {
    await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
      id: id, shopId: 'shop', customName: Value(name), unit: Value(unit),
      sellMode: Value(SellMode.measured.name),
      purchasePrice: price - 1000, salePrice: price, createdAt: _t, updatedAt: _t,
    ));
  }
  // Tapal 250 g: a pack variant in a family.
  await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
    id: 'tapal-250', shopId: 'shop', customName: const Value('Tapal Danedar'),
    packLabel: const Value('250 g'), familyId: const Value('family-tapal'),
    purchasePrice: 38000, salePrice: 41000, createdAt: _t, updatedAt: _t,
  ));
  return db;
}

Future<CreatedSale> _sell(AppDatabase db, String product, int quantity) async {
  final price = (await (db.select(db.shopProducts)..where((t) => t.id.equals(product))).getSingle()).salePrice;
  final total = (price * quantity + 500) ~/ 1000;
  return LocalSaleService(db, const UuidV7Generator(), clock: () => _t).createSale(SaleDraft(
    shopId: 'shop', cashierId: 'owner', deviceId: 'device',
    lines: [SaleLineDraft(productId: product, quantity: quantity)],
    payments: [if (total > 0) SalePaymentDraft(method: PaymentMethod.cash, amountMinor: total)],
  ));
}

Future<SaleItem> _item(AppDatabase db, String saleId) =>
    (db.select(db.saleItems)..where((t) => t.saleId.equals(saleId))).getSingle();

Future<Map<String, dynamic>> _payload(AppDatabase db, String saleId) async => jsonDecode(
      (await (db.select(db.syncOperations)..where((t) => t.entityId.equals(saleId))).getSingle()).payload,
    ) as Map<String, dynamic>;

/// The pre-U1 per-return formula, kept here only as the comparison baseline.
int _legacyRefund(int lineTotal, int sold, int quantity) =>
    quantity == sold ? lineTotal : (lineTotal * quantity + sold ~/ 2) ~/ sold;

void main() {
  group('integer measure formatting', () {
    test('weight', () {
      expect(formatMeasureQuantity(250, MeasureUnit.kg), '250 g');
      expect(formatMeasureQuantity(500, MeasureUnit.kg), '500 g');
      expect(formatMeasureQuantity(1000, MeasureUnit.kg), '1 kg');
      expect(formatMeasureQuantity(1250, MeasureUnit.kg), '1.25 kg');
      expect(formatMeasureQuantity(2500, MeasureUnit.kg), '2.5 kg');
      expect(formatMeasureQuantity(333, MeasureUnit.kg), '333 g');
      expect(formatMeasureQuantity(40000, MeasureUnit.kg), '40 kg');
      expect(formatMeasureQuantity(1001, MeasureUnit.kg), '1.001 kg');
      expect(formatMeasureQuantity(-250, MeasureUnit.kg), '-250 g');
    });

    test('volume', () {
      expect(formatMeasureQuantity(250, MeasureUnit.liter), '250 ml');
      expect(formatMeasureQuantity(750, MeasureUnit.liter), '750 ml');
      expect(formatMeasureQuantity(1000, MeasureUnit.liter), '1 L');
      expect(formatMeasureQuantity(1500, MeasureUnit.liter), '1.5 L');
    });

    test('a line without a measure unit is a count', () {
      expect(formatLineQuantity(2000, null), '2');
      expect(formatLineQuantity(2500, MeasureUnit.kg), '2.5 kg');
      expect(formatLineQuantity(1000, null), '1', reason: 'never "1.0"');
    });

    test('sellable name carries the pack label only inside a family', () {
      expect(sellableName('Surf Excel 1kg', '1kg'), 'Surf Excel 1kg');
      expect(sellableName('Tapal Danedar', '250 g', familyId: 'f'), 'Tapal Danedar 250 g');
      expect(sellableName('Tapal Danedar', null, familyId: 'f'), 'Tapal Danedar');
    });
  });

  group('checkout selling-mode rules', () {
    late AppDatabase db;
    setUp(() async => db = await _shop());
    tearDown(() => db.close());

    test('an existing product defaults to piece with custom quantity allowed', () async {
      final surf = await (db.select(db.shopProducts)..where((t) => t.id.equals('surf'))).getSingle();
      expect((surf.sellMode, surf.familyId, surf.measurePresets, surf.allowCustomQuantity),
          ('piece', null, null, true));
    });

    test('piece 1000 and 2000 are accepted and snapshot no measure unit', () async {
      for (final quantity in [1000, 2000]) {
        final sale = await _sell(db, 'surf', quantity);
        final item = await _item(db, sale.saleId);
        expect((item.quantity, item.lineTotal, item.measureUnitSnapshot),
            (quantity, 35000 * quantity ~/ 1000, null));
        final line = (await _payload(db, sale.saleId))['sale_items'][0] as Map<String, dynamic>;
        expect(line.containsKey('measureUnitSnapshot'), isTrue);
        expect(line['measureUnitSnapshot'], isNull);
      }
    });

    test('piece 500 is refused and nothing is written', () async {
      await expectLater(_sell(db, 'surf', 500), throwsA(isA<SaleValidationException>()));
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.syncOperations).get(), isEmpty);
    });

    test('measured 250 / 750 / 1250 / 2500 g at Rs 130/kg are exact', () async {
      for (final (grams, paisa) in [(250, 3250), (750, 9750), (1250, 16250), (2500, 32500)]) {
        final sale = await _sell(db, 'atta', grams);
        final item = await _item(db, sale.saleId);
        expect((item.quantity, item.lineTotal, item.measureUnitSnapshot), (grams, paisa, 'kg'));
        expect(sale.grandTotalMinor, paisa);
        final payload = await _payload(db, sale.saleId);
        expect(payload['version'], 1, reason: 'no payload version bump');
        expect((payload['sale_items'][0] as Map)['measureUnitSnapshot'], 'kg');
        expect((payload['inventory_movements'][0] as Map)['quantity'], -grams);
      }
    });

    test('exact integer rounding: half paisa rounds up, never float', () async {
      // Rs 175 per liter: 333 ml = 5827.5 paisa -> 5828; 750 ml = 13125 exact.
      for (final (ml, paisa) in [(333, 5828), (750, 13125), (1, 18), (999, 17483)]) {
        final sale = await _sell(db, 'oil', ml);
        expect((await _item(db, sale.saleId)).lineTotal, paisa, reason: '$ml ml');
        expect((await _item(db, sale.saleId)).measureUnitSnapshot, 'liter');
      }
    });

    test('a pack variant snapshots its family name with the pack label', () async {
      final sale = await _sell(db, 'tapal-250', 2000);
      final item = await _item(db, sale.saleId);
      expect((item.productNameSnapshot, item.lineTotal, item.measureUnitSnapshot),
          ('Tapal Danedar 250 g', 82000, null));
    });

    test('a measured product without kg/liter is refused', () async {
      await (db.update(db.shopProducts)..where((t) => t.id.equals('atta')))
          .write(const ShopProductsCompanion(unit: Value('piece')));
      await expectLater(_sell(db, 'atta', 500), throwsA(isA<SaleValidationException>()));
    });
  });

  group('cumulative partial-return refund', () {
    test('first return equals the previous formula', () {
      for (final (lineTotal, sold, q) in [(5828, 333, 111), (32500, 2500, 750), (2000, 3000, 1000)]) {
        expect(
          saleReturnRefund(lineTotal: lineTotal, sold: sold, priorQuantity: 0, priorRefund: 0, quantity: q),
          _legacyRefund(lineTotal, sold, q),
        );
      }
    });

    test('the old formula over-refunds 1 paisa; the new rule converges exactly', () {
      // Rs 20.00 for 3 kg returned 1 kg at a time: old 667 x 3 = 2001.
      expect(_legacyRefund(2000, 3000, 1000) * 3, 2001);
      var prior = 0, refunded = 0;
      final refunds = <int>[];
      for (var i = 0; i < 3; i++) {
        final r = saleReturnRefund(lineTotal: 2000, sold: 3000, priorQuantity: prior, priorRefund: refunded, quantity: 1000);
        refunds.add(r);
        prior += 1000;
        refunded += r;
      }
      expect(refunds, [667, 666, 667]);
      expect(refunded, 2000);
    });

    test('adversarial 333 g / 667 g splits never exceed and always complete exactly', () {
      for (final sold in [1000, 1333, 1667, 2500, 3000, 999]) {
        for (final lineTotal in [1, 2, 3, 5828, 9999, 13000, 32500, 100001]) {
          for (final steps in [
            [333, 667],
            [667, 333],
            [333, 333, 334],
            [1, 1, 998],
            [250, 250, 250, 250],
          ]) {
            // Scale the split to this sold quantity, last step takes the rest.
            final parts = <int>[];
            var left = sold;
            for (var i = 0; i < steps.length - 1; i++) {
              final q = (sold * steps[i]) ~/ 1000;
              if (q <= 0 || q >= left) continue;
              parts.add(q);
              left -= q;
            }
            parts.add(left);
            var prior = 0, refunded = 0;
            for (final q in parts) {
              final r = saleReturnRefund(lineTotal: lineTotal, sold: sold, priorQuantity: prior, priorRefund: refunded, quantity: q);
              expect(r, greaterThanOrEqualTo(0));
              prior += q;
              refunded += r;
              expect(refunded, lessThanOrEqualTo(lineTotal),
                  reason: 'L=$lineTotal S=$sold parts=$parts');
            }
            expect(refunded, lineTotal, reason: 'final remainder: L=$lineTotal S=$sold parts=$parts');
          }
        }
      }
    });

    test('a history over-refunded by the old formula is never refunded further', () {
      // Two old returns of 1 kg each refunded 667 + 667 = 1334 of 2000.
      expect(saleReturnRefund(lineTotal: 2000, sold: 3000, priorQuantity: 2000, priorRefund: 1334, quantity: 1000), 666);
      expect(saleReturnRefund(lineTotal: 2000, sold: 3000, priorQuantity: 2000, priorRefund: 2000, quantity: 1000), 0);
    });

    test('returning beyond the sold quantity is refused', () {
      expect(() => saleReturnRefund(lineTotal: 1000, sold: 1000, priorQuantity: 600, priorRefund: 600, quantity: 401),
          throwsArgumentError);
    });
  });

  group('local returns of a measured line', () {
    late AppDatabase db;
    setUp(() async => db = await _shop());
    tearDown(() => db.close());

    Future<int> returnGrams(String saleId, String itemId, int grams) async =>
        (await LocalSaleReturnService(db, const UuidV7Generator(), clock: () => _t).create(SaleReturnDraft(
          shopId: 'shop', originalSaleId: saleId, ownerId: 'owner', deviceId: 'device',
          refundMethod: PaymentMethod.cash, reason: 'returned',
          lines: [SaleReturnLineDraft(originalSaleItemId: itemId, quantity: grams)],
        ))).refundAmount;

    test('333 g + 333 g + 334 g of 1 kg Oil refunds exactly the line total', () async {
      final sale = await _sell(db, 'oil', 1000); // Rs 175.00
      final item = await _item(db, sale.saleId);
      final refunds = [
        await returnGrams(sale.saleId, item.id, 333),
        await returnGrams(sale.saleId, item.id, 333),
        await returnGrams(sale.saleId, item.id, 334),
      ];
      expect(refunds.reduce((a, b) => a + b), 17500);
      expect(refunds, [5828, 5827, 5845]);
      await expectLater(returnGrams(sale.saleId, item.id, 1), throwsA(anything),
          reason: 'nothing left to return');
      final restored = await db.customSelect(
        "select coalesce(sum(quantity),0) q from inventory_movements where product_id='oil' and type='returnIn'",
      ).getSingle();
      expect(restored.read<int>('q'), 1000, reason: 'exact base units restored');
    });

    Future<int> returnQty(String product, int sold, int returned) async {
      final sale = await _sell(db, product, sold);
      final item = await _item(db, sale.saleId);
      return returnGrams(sale.saleId, item.id, returned);
    }

    test('piece sale 2000 -> return 1000 accepted', () async {
      expect(await returnQty('surf', 2000, 1000), 35000);
    });

    test('piece sale 2000 -> return 500 refused before anything is written', () async {
      for (final quantity in [1, 250, 500, 1500]) {
        await expectLater(returnQty('surf', 2000, quantity), throwsArgumentError, reason: '$quantity');
      }
      expect(await db.select(db.saleReturns).get(), isEmpty);
      expect((await db.select(db.syncOperations).get()).where((o) => o.entityType == 'sale_return'), isEmpty);
    });

    test('measured 2500 -> return 500 accepted', () async {
      expect(await returnQty('atta', 2500, 500), 6500);
    });

    test('measured split returns end exactly at the line total; nothing beyond', () async {
      final sale = await _sell(db, 'atta', 2500); // Rs 325.00
      final item = await _item(db, sale.saleId);
      final refunds = [
        for (final grams in [333, 667, 1, 1499]) await returnGrams(sale.saleId, item.id, grams),
      ];
      expect(refunds.reduce((a, b) => a + b), 32500);
      await expectLater(returnGrams(sale.saleId, item.id, 1), throwsA(anything));
      final totals = await db.customSelect(
        "select sum(quantity) q, sum(refund_amount) r from sale_return_items where original_sale_item_id=?",
        variables: [Variable(item.id)],
      ).getSingle();
      expect((totals.read<int>('q'), totals.read<int>('r')), (2500, 32500));
    });

    test('the same item twice in one return is refused', () async {
      final sale = await _sell(db, 'atta', 2500);
      final item = await _item(db, sale.saleId);
      await expectLater(
        LocalSaleReturnService(db, const UuidV7Generator(), clock: () => _t).create(SaleReturnDraft(
          shopId: 'shop', originalSaleId: sale.saleId, ownerId: 'owner', deviceId: 'device',
          refundMethod: PaymentMethod.cash, reason: 'returned',
          lines: [
            SaleReturnLineDraft(originalSaleItemId: item.id, quantity: 500),
            SaleReturnLineDraft(originalSaleItemId: item.id, quantity: 500),
          ],
        )),
        throwsArgumentError,
      );
      expect(await db.select(db.saleReturns).get(), isEmpty);
    });
  });
}
