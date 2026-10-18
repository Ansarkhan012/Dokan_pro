// U3 packaged product families through the real Supabase HTTP path of a
// disposable LOCAL stack: the owner creates a family with the app's own
// product service and gateway (U1 create_shop_product per size), a real
// partial failure is retried without duplicates, barcodes resolve to the
// exact size, other shops and non-owners are refused, and pack sales go
// through offline checkout, restart, reconnect, lost-response replay, void
// and partial returns with per-size stock.
@Tags(['r1-http'])
library;

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/products/product_management_service.dart';
import 'package:dukaan_pro/features/products/supabase_product_management_gateway.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_return_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/domain/sale_return.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart';

String _id() => const Uuid().v4();

PackVariantDraft _size(String id, String label, int sale, int packs, {String? barcode}) => PackVariantDraft(
      productId: id, movementId: _id(), packLabel: label, barcode: barcode,
      purchasePriceMinor: sale - 4000, salePriceMinor: sale,
      openingQuantity: packs * 1000, lowStockLevel: 2000);

Future<int> _serverStock(SupabaseClient client, String productId) async =>
    (await client.from('inventory_movements').select('quantity').eq('product_id', productId) as List)
        .fold<int>(0, (sum, row) => sum + ((row as Map)['quantity'] as int));

Future<CreatedSale> _checkout(SimDevice device, PosCart cart) =>
    LocalSaleService(device.db, const UuidV7Generator(), clock: device.now).createSale(SaleDraft(
      shopId: device.shop.shopId,
      cashierId: device.shop.owner.userId,
      deviceId: device.deviceId,
      lines: cart.toSaleLines(),
      payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: cart.subtotalMinor)],
    ));

void main() {
  late LocalHttpStack stack;
  final devices = <SimDevice>[];

  setUpAll(() async {
    if (r1HttpConfigured) stack = await LocalHttpStack.connect();
  });
  tearDown(() async {
    for (final device in devices) {
      await device.dispose();
    }
    devices.clear();
  });
  tearDownAll(() async {
    if (r1HttpConfigured) await stack.dispose();
  });
  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

  test('owner family: partial failure retried safely; barcodes, re-pull, isolation, owner-only', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final client = shop.owner.client;
    final service = ProductManagementService(SupabaseProductManagementGateway(client), const UuidV7Generator());
    final tag = _id().substring(0, 8);
    // A product that already owns a barcode the family will wrongly reuse.
    await service.createCustom(
      shopId: shop.shopId, deviceId: shop.deviceA,
      input: CustomProductInput(name: 'Old tea', categoryId: ServerShop.categoryId, unit: ProductUnit.piece,
          barcode: 'U3-OLD-$tag', purchasePriceMinor: 1, salePriceMinor: 2, openingQuantity: 0, lowStockLevel: 0));

    final familyId = _id(), t250 = _id(), t500 = _id(), t1kg = _id();
    ProductFamilyDraft draft(String barcode500) => ProductFamilyDraft(
          familyId: familyId, name: 'Tapal Danedar', categoryId: ServerShop.categoryId,
          variants: [
            _size(t250, '250 g', 29000, 24, barcode: 'U3-250-$tag'),
            _size(t500, '500 g', 55000, 18, barcode: barcode500),
            _size(t1kg, '1 kg', 105000, 8),
          ]);
    final first = draft('U3-OLD-$tag');
    // The server refuses the duplicate barcode after 250 g was created.
    final failure = await service
        .createFamily(shopId: shop.shopId, deviceId: shop.deviceA, family: first)
        .then<FamilyCreationIncomplete?>((_) => null, onError: (Object e) => e as FamilyCreationIncomplete);
    expect(failure!.created, [t250]);
    expect(failure.failedLabel, '500 g');
    expect(await client.from('shop_products').select('id').eq('family_id', familyId), hasLength(1));

    // Retry with the barcode fixed and the SAME ids: no duplicate 250 g, no
    // second opening movement.
    final fixed = ProductFamilyDraft(
      familyId: familyId, name: first.name, categoryId: first.categoryId,
      variants: [first.variants[0], _size(t500, '500 g', 55000, 18, barcode: 'U3-500-$tag'), first.variants[2]]);
    expect(await service.createFamily(shopId: shop.shopId, deviceId: shop.deviceA, family: fixed), [t250, t500, t1kg]);
    final rows = await client.from('shop_products')
        .select('id,custom_name,pack_label,unit,sell_mode,sale_price,purchase_price,barcode')
        .eq('family_id', familyId).order('sale_price', ascending: true) as List;
    expect(rows.map((r) => ((r as Map)['id'], r['pack_label'], r['unit'], r['sell_mode'], r['sale_price'], r['purchase_price'])), [
      (t250, '250 g', 'pack', 'piece', 29000, 25000),
      (t500, '500 g', 'pack', 'piece', 55000, 51000),
      (t1kg, '1 kg', 'pack', 'piece', 105000, 101000),
    ]);
    expect(await client.from('inventory_movements').select('id').eq('product_id', t250), hasLength(1),
        reason: 'opening stock for 250 g exactly once');
    expect((await _serverStock(client, t250), await _serverStock(client, t500), await _serverStock(client, t1kg)),
        (24000, 18000, 8000));

    // Duplicate barcodes are refused per shop, even straight through the RPC.
    await expectLater(
      service.createCustom(
        shopId: shop.shopId, deviceId: shop.deviceA,
        input: CustomProductInput(name: 'Fake', categoryId: ServerShop.categoryId, unit: ProductUnit.piece,
            barcode: 'U3-250-$tag', purchasePriceMinor: 1, salePriceMinor: 2, openingQuantity: 0, lowStockLevel: 0)),
      throwsA(isA<PostgrestException>()));

    // Two devices pull the same grouped family; a barcode resolves the size.
    for (final label in ['units_family_a', 'units_family_b']) {
      final device = await SimDevice.open(label, shop, label.endsWith('a') ? shop.deviceA : shop.deviceB);
      devices.add(device);
      final catalog = await DriftPosCatalog(device.db, shopId: shop.shopId).load();
      final family = groupCatalog(catalog.products).singleWhere((e) => e.isFamily);
      expect(family.name, 'Tapal Danedar');
      expect(family.variants.map((v) => v.id), [t250, t500, t1kg]);
      expect(catalog.products.singleWhere((p) => p.barcode == 'U3-500-$tag').id, t500);
      expect(catalog.products.singleWhere((p) => p.id == t1kg).name, 'Tapal Danedar 1 kg');
    }

    // Another shop sees nothing and cannot join the family.
    final other = await ServerShop.create(await stack.signUpOwner());
    expect(await other.owner.client.from('shop_products').select('id').eq('family_id', familyId), isEmpty);
    await expectLater(
      ProductManagementService(SupabaseProductManagementGateway(other.owner.client), const UuidV7Generator()).createFamily(
        shopId: other.shopId, deviceId: other.deviceA,
        family: ProductFamilyDraft(familyId: familyId, name: 'Tapal', categoryId: ServerShop.categoryId,
            variants: [_size(_id(), '250 g', 29000, 1)])),
      throwsA(isA<FamilyCreationIncomplete>()));
    await expectLater(
      other.owner.client.rpc('set_product_family', params: {'p_shop_id': shop.shopId, 'p_family_id': familyId, 'p_product_ids': [t250]}),
      throwsA(isA<PostgrestException>()));

    // Without an owner session (cashier/device role) family management is refused.
    final anon = stack.newClient(); // disposed by the stack
    await expectLater(
      anon.rpc('create_shop_product', params: {
        'p_payload': {'shop_id': shop.shopId, 'device_id': shop.deviceA, 'product_id': _id(), 'movement_id': _id(),
          'name': 'X', 'category_id': ServerShop.categoryId, 'unit': 'pack', 'purchase_price': 1, 'sale_price': 1,
          'family_id': familyId, 'pack_label': '2 kg'},
      }),
      throwsA(isA<PostgrestException>()));
    await expectLater(
      anon.rpc('set_product_family', params: {'p_shop_id': shop.shopId, 'p_family_id': null, 'p_product_ids': [t250]}),
      throwsA(isA<PostgrestException>()));
    expect(await client.from('shop_products').select('id').eq('family_id', familyId), hasLength(3));
  }, skip: skip);

  test('pack sales: per-size stock offline, restart, reconnect, replay, void and returns', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final client = shop.owner.client;
    final service = ProductManagementService(SupabaseProductManagementGateway(client), const UuidV7Generator());
    final t250 = _id(), t500 = _id(), t1kg = _id();
    await service.createFamily(
      shopId: shop.shopId, deviceId: shop.deviceA,
      family: ProductFamilyDraft(familyId: _id(), name: 'Tapal Danedar', categoryId: ServerShop.categoryId, variants: [
        _size(t250, '250 g', 29000, 24), _size(t500, '500 g', 55000, 18), _size(t1kg, '1 kg', 105000, 8),
      ]));
    final device = await SimDevice.open('units_family_sale', shop, shop.deviceA);
    devices.add(device);
    final catalog = await DriftPosCatalog(device.db, shopId: shop.shopId).load();
    PosProduct size(String id) => catalog.products.singleWhere((p) => p.id == id);

    // Two 500 g packs and one 250 g pack: two lines, never merged.
    final cart = PosCart()..add(size(t500))..add(size(t500))..add(size(t250));
    expect(cart.lines.map((l) => (l.product.id, l.quantity)), [(t500, 2000), (t250, 1000)]);
    device.network = SimNetwork.offline;
    final sale = await _checkout(device, cart);
    expect(sale.grandTotalMinor, 139000);
    expect((await device.sync()).synced, 0);
    await device.restart();
    device.network = SimNetwork.online;
    device.clockSkew = const Duration(minutes: 10); // past the retry backoff
    expect((await device.sync()).synced, 1);
    expect((await _serverStock(client, t500), await _serverStock(client, t250), await _serverStock(client, t1kg)),
        (16000, 23000, 8000), reason: 'only the sold sizes; no conversion between packs');
    final snapshots = await client.from('sale_items').select('product_id,product_name_snapshot,quantity,line_total')
        .eq('sale_id', sale.saleId) as List;
    expect(snapshots.map((r) => ((r as Map)['product_name_snapshot'], r['quantity'], r['line_total'])).toSet(),
        {('Tapal Danedar 500 g', 2000, 110000), ('Tapal Danedar 250 g', 1000, 29000)});

    // Lost response after the server committed: the retry is a replay.
    final second = await _checkout(device, PosCart()..add(size(t1kg)));
    device.network = SimNetwork.dropResponse;
    await device.sync();
    device.network = SimNetwork.online;
    device.clockSkew = const Duration(minutes: 20);
    expect((await device.sync()).synced, 1);
    expect(await client.from('inventory_movements').select('quantity').eq('reference_id', second.saleId),
        [{'quantity': -1000}], reason: 'one movement, no duplicate');

    // Void the 1 kg sale: exactly one 1 kg pack back.
    await LocalSaleVoidService(device.db, const UuidV7Generator(), clock: device.now).voidSale(
      shopId: shop.shopId, saleId: second.saleId, ownerId: shop.owner.userId,
      deviceId: shop.deviceA, reason: 'wrong bill');
    expect((await device.sync()).synced, 1);
    expect(await _serverStock(client, t1kg), 8000);

    // Return the two 500 g packs one at a time: Rs 550 each, exactly.
    final item500 = await (device.db.select(device.db.saleItems)
          ..where((t) => t.saleId.equals(sale.saleId) & t.productId.equals(t500)))
        .getSingle();
    final refunds = <int>[];
    for (var i = 0; i < 2; i++) {
      refunds.add((await LocalSaleReturnService(device.db, const UuidV7Generator(), clock: device.now).create(
        SaleReturnDraft(
          shopId: shop.shopId, originalSaleId: sale.saleId, ownerId: shop.owner.userId,
          deviceId: shop.deviceA, refundMethod: PaymentMethod.cash, reason: 'returned',
          lines: [SaleReturnLineDraft(originalSaleItemId: item500.id, quantity: 1000)]))).refundAmount);
      expect((await device.sync()).synced, 1);
    }
    expect(refunds, [55000, 55000]);
    expect((await _serverStock(client, t500), await _serverStock(client, t250)), (18000, 23000),
        reason: 'returns restore only the 500 g size');
    await device.pull();
    expect((await device.stock(t500), await device.stock(t250), await device.stock(t1kg)), (18000, 23000, 8000));
    expect((await device.queue()).where((o) => o.status != SyncStatus.synced), isEmpty);
  }, skip: skip);
}
