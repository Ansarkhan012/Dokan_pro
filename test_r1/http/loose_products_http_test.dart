// U2 loose products through the real Supabase HTTP path of a disposable
// LOCAL stack: the owner creates and edits measured products with the app's
// own product service and gateway (U1 create_shop_product + the existing
// update path), a device pulls them, sells picked quantities offline,
// restarts, reconnects, replays after a lost response, voids and returns,
// all with exact thousandths and paisa.
@Tags(['r1-http'])
library;

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

import '../support/http_stack.dart';
import '../support/sim_device.dart';

CustomProductInput _loose(String name, ProductUnit unit, int price, int opening, List<int> presets,
        {bool custom = true}) =>
    CustomProductInput(
      name: name,
      categoryId: ServerShop.categoryId,
      unit: unit,
      purchasePriceMinor: price - 1000,
      salePriceMinor: price,
      openingQuantity: opening,
      lowStockLevel: 5000,
      sellMode: SellMode.measured,
      measurePresets: presets,
      allowCustomQuantity: custom,
    );

/// A cashier sale of the cart's lines, paid in cash, as the POS commits it.
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

  test('owner creates kg and L products once; edits keep stock; presets re-pull', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final client = shop.owner.client;
    final gateway = SupabaseProductManagementGateway(client);
    final service = ProductManagementService(gateway, const UuidV7Generator());
    final atta = await service.createCustom(
      shopId: shop.shopId, deviceId: shop.deviceA,
      input: _loose('Atta', ProductUnit.kg, 13000, 40000, [500, 1000, 5000, 10000, 20000, 40000]));
    final oil = await service.createCustom(
      shopId: shop.shopId, deviceId: shop.deviceA,
      input: _loose('Loose oil', ProductUnit.liter, 17500, 20000, [250, 500, 1000], custom: false));

    final row = await client.from('shop_products')
        .select('sell_mode,unit,sale_price,measure_presets,allow_custom_quantity').eq('id', atta).single();
    expect(row, {
      'sell_mode': 'measured', 'unit': 'kg', 'sale_price': 13000,
      'measure_presets': [500, 1000, 5000, 10000, 20000, 40000], 'allow_custom_quantity': true,
    });
    final opening = await client.from('inventory_movements').select('quantity,type').eq('product_id', atta) as List;
    expect(opening, [{'quantity': 40000, 'type': 'openingStock'}], reason: 'opening stock exactly once');

    // A retried create of the same product (lost response), even with a
    // fresh movement id, answers already_exists and adds no second movement.
    final retried = await gateway.createCustomProduct(
      shopId: shop.shopId, deviceId: shop.deviceA,
      shopProductId: oil, movementId: '00000000-0000-0000-0000-000000000000',
      input: _loose('Loose oil', ProductUnit.liter, 17500, 20000, [250, 500, 1000], custom: false));
    expect(retried, oil);
    expect(await client.from('inventory_movements').select('id').eq('product_id', oil), hasLength(1));

    final device = await SimDevice.open('loose_owner', shop, shop.deviceA);
    devices.add(device);
    var catalog = await DriftPosCatalog(device.db, shopId: shop.shopId).load();
    var pulledAtta = catalog.products.firstWhere((p) => p.id == atta);
    expect(pulledAtta.measureUnit, MeasureUnit.kg);
    expect(pulledAtta.measurePresets, [500, 1000, 5000, 10000, 20000, 40000]);
    expect(pulledAtta.stockQuantity, 40000);
    final pulledOil = catalog.products.firstWhere((p) => p.id == oil);
    expect((pulledOil.measureUnit, pulledOil.allowCustomQuantity), (MeasureUnit.liter, false));

    // Edit: prices, threshold, presets and custom toggle; stock untouched.
    await gateway.updateProduct(
      shopId: shop.shopId, productId: atta, purchasePriceMinor: 12500, salePriceMinor: 13500,
      lowStockLevel: 2500, isActive: true, measurePresets: [250, 1000, 2500], allowCustomQuantity: false);
    expect(await client.from('inventory_movements').select('quantity').eq('product_id', atta),
        [{'quantity': 40000}], reason: 'an edit never writes stock');
    await device.pull();
    catalog = await DriftPosCatalog(device.db, shopId: shop.shopId).load();
    pulledAtta = catalog.products.firstWhere((p) => p.id == atta);
    expect((pulledAtta.salePriceMinor, pulledAtta.allowCustomQuantity, pulledAtta.stockQuantity, pulledAtta.measureUnit),
        (13500, false, 40000, MeasureUnit.kg));
    expect(pulledAtta.measurePresets, [250, 1000, 2500]);
    final product = await (device.db.select(device.db.shopProducts)..where((t) => t.id.equals(atta))).getSingle();
    expect((product.sellMode, product.unit), ('measured', 'kg'), reason: 'mode and unit never change');
  }, skip: skip);

  test('offline loose sale survives restart, syncs once, replays, voids and returns exactly', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final client = shop.owner.client;
    final service = ProductManagementService(SupabaseProductManagementGateway(client), const UuidV7Generator());
    final atta = await service.createCustom(
      shopId: shop.shopId, deviceId: shop.deviceA,
      input: _loose('Atta', ProductUnit.kg, 13000, 40000, [250, 500, 1000, 2500]));
    final device = await SimDevice.open('loose_cashier', shop, shop.deviceA);
    devices.add(device);
    final product = (await DriftPosCatalog(device.db, shopId: shop.shopId).load())
        .products.firstWhere((p) => p.id == atta);

    // Picker adds 1 kg then 1.5 kg into one line: 2.5 kg = Rs 325.00.
    final cart = PosCart()
      ..addQuantity(product, 1000)
      ..addQuantity(product, 1500);
    expect((cart.lines.single.quantity, cart.subtotalMinor), (2500, 32500));

    device.network = SimNetwork.offline;
    final sale = await _checkout(device, cart);
    expect(sale.grandTotalMinor, 32500);
    expect((await device.sync()).synced, 0, reason: 'offline');
    expect(await device.stock(atta), 37500, reason: 'local stock in grams');
    await device.restart();
    expect(await device.hasSale(sale.saleId), isTrue);

    device.network = SimNetwork.online;
    device.clockSkew = const Duration(minutes: 10); // past the retry backoff
    expect((await device.sync()).synced, 1);
    final serverItem = await client.from('sale_items')
        .select('quantity,line_total,measure_unit_snapshot').eq('sale_id', sale.saleId).single();
    expect(serverItem, {'quantity': 2500, 'line_total': 32500, 'measure_unit_snapshot': 'kg'});

    // Lost response after the server committed: the retry is a replay.
    final second = await _checkout(device, PosCart()..addQuantity(product, 750));
    device.network = SimNetwork.dropResponse;
    await device.sync();
    device.network = SimNetwork.online;
    device.clockSkew = const Duration(minutes: 20); // past the retry backoff
    expect((await device.sync()).synced, 1, reason: 'the retry is answered already_synced');
    expect(await client.from('sales').select('id').eq('id', second.saleId), hasLength(1));
    expect(await client.from('inventory_movements').select('quantity').eq('reference_id', second.saleId),
        [{'quantity': -750}], reason: 'one movement, no duplicate');

    Future<int> serverStock() async => (await client.from('inventory_movements').select('quantity').eq('product_id', atta)
            as List)
        .fold<int>(0, (sum, row) => sum + ((row as Map)['quantity'] as int));
    expect(await serverStock(), 40000 - 2500 - 750);

    // Void the 750 g sale: exactly 750 g back.
    await LocalSaleVoidService(device.db, const UuidV7Generator(), clock: device.now).voidSale(
      shopId: shop.shopId, saleId: second.saleId, ownerId: shop.owner.userId,
      deviceId: shop.deviceA, reason: 'wrong bill');
    expect((await device.sync()).synced, 1);
    expect(await serverStock(), 40000 - 2500);

    // Return 333 g + 667 g + 1500 g of the 2.5 kg line: exactly Rs 325.00.
    final item = await (device.db.select(device.db.saleItems)..where((t) => t.saleId.equals(sale.saleId))).getSingle();
    final refunds = <int>[];
    for (final grams in [333, 667, 1500]) {
      final created = await LocalSaleReturnService(device.db, const UuidV7Generator(), clock: device.now).create(SaleReturnDraft(
        shopId: shop.shopId, originalSaleId: sale.saleId, ownerId: shop.owner.userId,
        deviceId: shop.deviceA, refundMethod: PaymentMethod.cash, reason: 'returned',
        lines: [SaleReturnLineDraft(originalSaleItemId: item.id, quantity: grams)]));
      refunds.add(created.refundAmount);
      expect((await device.sync()).synced, 1);
    }
    expect(refunds.reduce((a, b) => a + b), 32500);
    final serverRefunds = await client.from('sale_return_items').select('quantity,refund_amount')
        .eq('original_sale_item_id', item.id) as List;
    expect(serverRefunds.fold<int>(0, (s, r) => s + ((r as Map)['refund_amount'] as int)), 32500);
    expect(await serverStock(), 40000, reason: 'every gram back');
    await device.pull();
    expect(await device.stock(atta), 40000, reason: 'device converges');
    final attention = (await device.queue()).where((o) => o.status != SyncStatus.synced);
    expect(attention, isEmpty);
  }, skip: skip);
}
