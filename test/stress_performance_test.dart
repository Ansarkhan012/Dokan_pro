import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/customers/drift_customer_repository.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/products/drift_product_management_repository.dart';
import 'package:dukaan_pro/features/purchases/drift_purchase_repository.dart';
import 'package:dukaan_pro/features/reports/drift_reporting_repository.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:flutter_test/flutter_test.dart';

const runStress = bool.fromEnvironment('RUN_STRESS');

void main() {
  test('large local dataset query timings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final seed = Stopwatch()..start();
    await _seed(db);
    seed.stop();

    Future<int> timed(Future<void> Function() work) async {
      final values = <int>[];
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        await work();
        watch.stop();
        values.add(watch.elapsedMilliseconds);
      }
      values.sort();
      return values[1];
    }

    final catalog = DriftPosCatalog(db, shopId: 'shop');
    final startupMs = await timed(() async {
      final result = await catalog.load();
      expect(result.products, hasLength(5000));
      expect(result.customers, hasLength(1000)); // Deliberate POS bound.
    });
    final barcodeMs = await timed(() async {
      final row = await db
          .customSelect(
            'select id from shop_products where shop_id=? and barcode=? limit 1',
            variables: [const Variable('shop'), const Variable('890000004999')],
          )
          .getSingle();
      expect(row.data['id'], 'p04999');
    });
    final productSearchMs = await timed(() async {
      expect(
        await DriftProductManagementRepository(
          db,
          shopId: 'shop',
        ).products(query: 'Product 499', limit: 100),
        isNotEmpty,
      );
    });
    final customerMs = await timed(() async {
      expect(
        await DriftCustomerRepository(
          db,
          shopId: 'shop',
        ).search('Customer 9999'),
        hasLength(1),
      );
    });
    final supplierMs = await timed(() async {
      expect(
        await DriftPurchaseRepository(db, shopId: 'shop').suppliers('Supplier'),
        hasLength(1),
      );
    });
    final purchaseFirstMs = await timed(() async {
      expect(
        await DriftPurchaseRepository(db, shopId: 'shop').purchases(limit: 100),
        hasLength(100),
      );
    });
    final purchaseNextMs = await timed(() async {
      expect(
        await DriftPurchaseRepository(
          db,
          shopId: 'shop',
        ).purchases(limit: 100, offset: 100),
        hasLength(100),
      );
    });
    final reportRepo = DriftReportingRepository(db, shopId: 'shop');
    final todayMs = await timed(() async {
      await reportRepo.load(
        ReportRange(
          DateTime.utc(2026, 9, 14),
          DateTime.utc(2026, 9, 15),
          label: 'today',
        ),
      );
    });
    final monthMs = await timed(() async {
      await reportRepo.load(
        ReportRange(
          DateTime.utc(2026, 9, 1),
          DateTime.utc(2026, 10, 1),
          label: 'month',
        ),
      );
    });
    final yearMs = await timed(() async {
      await reportRepo.load(
        ReportRange(DateTime.utc(2026), DateTime.utc(2027), label: 'year'),
        preset: ReportRangePreset.year,
      );
    });
    // Kept as one machine-readable line in test output.
    // ignore: avoid_print
    print(
      'STRESS_MEDIAN_MS seed=${seed.elapsedMilliseconds} startup=$startupMs product_search=$productSearchMs barcode=$barcodeMs customer=$customerMs supplier=$supplierMs purchase_first=$purchaseFirstMs purchase_next=$purchaseNextMs today=$todayMs month=$monthMs year=$yearMs',
    );
  }, skip: !runStress);
}

Future<void> _seed(AppDatabase db) => db.transaction(() async {
  const t = 1789344000;
  await db.customStatement(
    "insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at) values('shop','Stress','','','trial','trial',$t,$t)",
  );
  await db.customStatement(
    "insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at) values('device','shop','PC','windowsDesktop','identifier',$t,$t)",
  );
  await db.customStatement(
    "insert into cashiers(id,shop_id,display_name,login_code,created_at,updated_at) values('cashier','shop','Cashier','001',$t,$t)",
  );
  await db.customStatement(
    "insert into suppliers(id,shop_id,name,created_at,updated_at) values('supplier','shop','Supplier',$t,$t)",
  );
  await db.customStatement(
    "insert into expense_categories(id,shop_id,name,created_at,updated_at) values('expense-category','shop','Rent',$t,$t)",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<4999) insert into shop_products(id,shop_id,custom_name,barcode,purchase_price,sale_price,low_stock_level,created_at,updated_at) select printf('p%05d',x),'shop',printf('Product %d',x),printf('89000000%04d',x),10000,12000,5000,$t,$t from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<4999) insert into inventory_movements(id,shop_id,product_id,type,quantity,created_by,created_at) select printf('im%05d',x),'shop',printf('p%05d',x),'openingStock',100000,'cashier',$t from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<9999) insert into customers(id,shop_id,name,created_at,updated_at) select printf('c%05d',x),'shop',printf('Customer %d',x),$t,$t from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<49999) insert into customer_ledger_entries(id,shop_id,customer_id,type,amount,created_by,created_at) select printf('cl%05d',x),'shop',printf('c%05d',x%10000),'creditSale',1000,'cashier',$t from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<49999) insert into sales(id,shop_id,cashier_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at) select printf('s%05d',x),'shop','cashier','device',24000,0,0,24000,'paid','completed',$t+(x%86400) from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<99999) insert into sale_items(id,shop_id,sale_id,product_id,product_name_snapshot,quantity,cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at) select printf('si%06d',x),'shop',printf('s%05d',x%50000),printf('p%05d',x%5000),'Snapshot',1000,10000,12000,0,12000,$t+(x%86400) from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<49999) insert into sale_payments(id,sale_id,shop_id,payment_method,amount,created_at) select printf('sp%05d',x),printf('s%05d',x),'shop','cash',24000,$t+(x%86400) from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<19999) insert into purchases(id,shop_id,supplier_id,device_id,subtotal,discount_total,total,paid_amount,payment_status,created_by,created_at) select printf('pu%05d',x),'shop','supplier','device',10000,0,10000,10000,'paid','cashier',$t+(x%86400) from n",
  );
  await db.customStatement(
    "with recursive n(x)as(values(0)union all select x+1 from n where x<9999) insert into expenses(id,shop_id,category_id,category,amount,payment_method,description,device_id,expense_at,created_by,created_at) select printf('e%05d',x),'shop','expense-category','Rent',1000,'cash','Expense','device',$t+(x%86400),'cashier',$t+(x%86400) from n",
  );
});
