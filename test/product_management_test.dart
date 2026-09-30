import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/products/drift_product_management_repository.dart';
import 'package:dukaan_pro/features/products/product_management_gateway.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/products/product_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product management service', () {
    late _Gateway gateway;
    late ProductManagementService service;
    setUp(() {
      gateway = _Gateway();
      service = ProductManagementService(gateway, _Ids());
    });

    test('searches master catalog by name and exact barcode', () async {
      expect(
        (await service.search(shopId: 'shop', query: ' surf ')).single.name,
        'Surf Excel 1kg',
      );
      expect(
        (await service.search(
          shopId: 'shop',
          query: '8964001000011',
        )).single.barcode,
        '8964001000011',
      );
    });

    test('adds master product once with scaled opening stock', () async {
      const input = AddProductInput(
        purchasePriceMinor: 85000,
        salePriceMinor: 95000,
        openingQuantity: 20000,
        lowStockLevel: 5000,
      );
      final id = await service.addMaster(
        shopId: 'shop',
        deviceId: 'device',
        product: gateway.master,
        input: input,
      );
      expect(id, 'shop-product');
      expect(gateway.lastOpeningQuantity, 20000);
      expect(gateway.lastShopProductId, 'shop-product');
      expect(gateway.lastMovementId, 'movement');
      expect(
        () => service.addMaster(
          shopId: 'shop',
          deviceId: 'device',
          product: _copyMaster(gateway.master, alreadyAdded: true),
          input: input,
        ),
        throwsA(isA<ProductValidationException>()),
      );
    });

    test('creates shop-only custom product and validates prices', () async {
      final id = await service.createCustom(
        shopId: 'shop',
        deviceId: 'device',
        input: const CustomProductInput(
          name: 'Local Flour',
          categoryId: 'category',
          unit: ProductUnit.kg,
          purchasePriceMinor: 10000,
          salePriceMinor: 12000,
          openingQuantity: 500,
          lowStockLevel: 100,
        ),
      );
      expect(id, 'shop-product');
      expect(gateway.createdCustom?.name, 'Local Flour');
      expect(gateway.createdCustom?.openingQuantity, 500);
      expect(
        () => service.createCustom(
          shopId: 'shop',
          deviceId: 'device',
          input: const CustomProductInput(
            name: 'Invalid',
            categoryId: 'category',
            unit: ProductUnit.piece,
            purchasePriceMinor: -1,
            salePriceMinor: 10,
            openingQuantity: 0,
            lowStockLevel: 0,
          ),
        ),
        throwsA(isA<ProductValidationException>()),
      );
    });
  });

  test('inactive product stays manageable but is excluded from POS', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 9, 13);
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(
            id: 'shop',
            name: 'Shop',
            phone: '',
            address: '',
            subscriptionPlan: SubscriptionPlan.trial,
            subscriptionStatus: SubscriptionStatus.trial,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'category',
            name: 'Staples',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.shopProducts)
        .insert(
          ShopProductsCompanion.insert(
            id: 'custom',
            shopId: 'shop',
            customName: const Value('Local Flour'),
            categoryId: const Value('category'),
            unit: const Value('kg'),
            purchasePrice: 10000,
            salePrice: 12000,
            isActive: const Value(false),
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(
      await DriftProductManagementRepository(db, shopId: 'shop').products(),
      hasLength(1),
    );
    expect(
      (await DriftPosCatalog(db, shopId: 'shop').load()).products,
      isEmpty,
    );
  });

  test('product pages and search are executed against SQLite', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const t = 1789344000;
    await db.customStatement(
      "insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at) values('shop','Shop','','','trial','trial',$t,$t)",
    );
    await db.customStatement(
      "with recursive n(x)as(values(0) union all select x+1 from n where x<249) insert into shop_products(id,shop_id,custom_name,barcode,purchase_price,sale_price,created_at,updated_at) select printf('p%03d',x),'shop',printf('Product %d',x),printf('code%03d',x),100,200,$t,$t from n",
    );
    final repository = DriftProductManagementRepository(db, shopId: 'shop');
    expect(await repository.products(limit: 200), hasLength(200));
    expect(await repository.products(limit: 200, offset: 200), hasLength(50));
    final exact = await repository.products(query: 'code249');
    expect(exact.single.id, 'p249');
    expect((await repository.products(query: 'Product 249')).single.id, 'p249');
  });
}

MasterCatalogItem _copyMaster(
  MasterCatalogItem value, {
  required bool alreadyAdded,
}) => MasterCatalogItem(
  id: value.id,
  name: value.name,
  brand: value.brand,
  barcode: value.barcode,
  categoryId: value.categoryId,
  categoryName: value.categoryName,
  unit: value.unit,
  alreadyAdded: alreadyAdded,
);

final class _Ids implements IdGenerator {
  var index = 0;
  @override
  String next() =>
      ['shop-product', 'movement', 'shop-product', 'movement'][index++];
}

final class _Gateway implements ProductManagementGateway {
  final master = const MasterCatalogItem(
    id: 'master',
    name: 'Surf Excel 1kg',
    brand: 'Surf Excel',
    barcode: '8964001000011',
    categoryId: 'category',
    categoryName: 'Household',
    unit: 'piece',
    alreadyAdded: false,
  );
  int? lastOpeningQuantity;
  String? lastShopProductId;
  String? lastMovementId;
  CustomProductInput? createdCustom;

  @override
  Future<List<MasterCatalogItem>> searchMasterCatalog({
    required String shopId,
    required String query,
  }) async => query.toLowerCase().contains('surf') || query == master.barcode
      ? [master]
      : [];
  @override
  Future<String> addMasterProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required String masterProductId,
    required AddProductInput input,
  }) async {
    lastOpeningQuantity = input.openingQuantity;
    lastShopProductId = shopProductId;
    lastMovementId = movementId;
    return shopProductId;
  }

  @override
  Future<String> createCustomProduct({
    required String shopId,
    required String deviceId,
    required String shopProductId,
    required String movementId,
    required CustomProductInput input,
  }) async {
    createdCustom = input;
    return shopProductId;
  }

  @override
  Future<void> updateProduct({
    required String shopId,
    required String productId,
    required int purchasePriceMinor,
    required int salePriceMinor,
    required int lowStockLevel,
    required bool isActive,
  }) async {}
}
