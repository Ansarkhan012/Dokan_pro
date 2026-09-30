import 'package:drift/native.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/reports/drift_reporting_repository.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final at = DateTime.utc(2026, 9, 14, 7); // Noon in Asia/Karachi.
  final range = ReportRange(
    DateTime.utc(2026, 9, 13, 19),
    DateTime.utc(2026, 9, 14, 19),
    label: 'test',
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _seed(db, at);
  });
  tearDown(() => db.close());

  test(
    'calculates snapshot profit, allocations, balances and rankings',
    () async {
      final report = await DriftReportingRepository(
        db,
        shopId: 'shop-a',
      ).load(range);
      final summary = report.summary;
      expect(summary.sales, 100000);
      expect(summary.cogs, 70000);
      expect(summary.grossProfit, 30000);
      expect(summary.expenses, 8000);
      expect(summary.netProfit, 22000);
      expect(summary.purchases, 50000);
      expect(summary.purchasePaid, 30000);
      expect(summary.purchaseCredit, 20000);
      expect(
        (summary.cash, summary.digital, summary.credit),
        (60000, 20000, 20000),
      );
      expect((summary.receivables, summary.payables), (20000, 20000));
      expect(summary.billCount, 1);
      expect(report.topSalesProducts.single.label, 'Snapshot Tea');
      expect(report.topProfitProducts.single.value, 30000);
      expect(report.cashiers.single.name, 'Ali');
      expect(report.lowStock.single.value, 2000);
    },
  );

  test(
    'uses half-open ranges and never subtracts purchases from profit',
    () async {
      final excluded = await DriftReportingRepository(db, shopId: 'shop-a')
          .load(
            ReportRange(
              at.add(const Duration(seconds: 1)),
              range.endUtc,
              label: 'x',
            ),
          );
      expect(excluded.summary.sales, 0);
      expect(excluded.summary.grossProfit, 0);
      expect(excluded.summary.netProfit, 0);
    },
  );

  test(
    'partial returns reduce net revenue, payment bucket and snapshot COGS',
    () async {
      final t = at.millisecondsSinceEpoch ~/ 1000;
      await db.customStatement(
        "insert into sale_returns(id,shop_id,original_sale_id,customer_id,device_id,refund_method,refund_amount,reason,created_by,created_at) values('return','shop-a','sale','customer','device','cash',50000,'half','owner',$t)",
      );
      await db.customStatement(
        "insert into sale_return_items(id,shop_id,return_id,original_sale_item_id,product_id,product_name_snapshot,quantity,unit_price_snapshot,refund_amount,created_at) values('return-item','shop-a','return','item','product','Snapshot Tea',500,100000,50000,$t)",
      );
      final report = await DriftReportingRepository(
        db,
        shopId: 'shop-a',
      ).load(range);
      expect(
        (
          report.summary.grossSales,
          report.summary.returns,
          report.summary.sales,
        ),
        (100000, 50000, 50000),
      );
      expect((report.summary.cogs, report.summary.grossProfit), (35000, 15000));
      expect(
        (report.summary.cash, report.summary.digital, report.summary.credit),
        (10000, 20000, 20000),
      );
      expect(report.summary.partialReturnCount, 1);
      expect(report.topSalesProducts.single.value, 50000);
    },
  );

  test('Pakistan period boundaries are deterministic', () {
    final today = ReportRange.forPreset(
      ReportRangePreset.today,
      DateTime.utc(2026, 9, 14, 20),
    );
    expect(today.startUtc, DateTime.utc(2026, 9, 14, 19));
    expect(today.endUtc, DateTime.utc(2026, 9, 15, 19));
    final custom = ReportRange.custom(
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    expect(custom.startUtc, DateTime.utc(2026, 8, 31, 19));
    expect(custom.endUtc, DateTime.utc(2026, 9, 30, 19));
  });
}

Future<void> _seed(AppDatabase db, DateTime at) async {
  final t = at.millisecondsSinceEpoch ~/ 1000;
  Future<void> sql(String statement) => db.customStatement(statement);
  await sql(
    "insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at) values('shop-a','A','','','trial','trial',$t,$t)",
  );
  await sql(
    "insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at) values('device','shop-a','PC','windowsDesktop','dev',$t,$t)",
  );
  await sql(
    "insert into cashiers(id,shop_id,display_name,login_code,created_at,updated_at) values('cashier','shop-a','Ali','001',$t,$t)",
  );
  await sql(
    "insert into shop_products(id,shop_id,custom_name,purchase_price,sale_price,low_stock_level,created_at,updated_at) values('product','shop-a','Current Tea',70000,100000,5000,$t,$t)",
  );
  await sql(
    "insert into sales(id,shop_id,cashier_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at) values('sale','shop-a','cashier','device',100000,0,0,100000,'paid','completed',$t)",
  );
  await sql(
    "insert into sale_items(id,shop_id,sale_id,product_id,product_name_snapshot,quantity,cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at) values('item','shop-a','sale','product','Snapshot Tea',1000,70000,100000,0,100000,$t)",
  );
  await sql(
    "insert into sale_payments(id,sale_id,shop_id,payment_method,amount,created_at) values('cash','sale','shop-a','cash',60000,$t),('digital','sale','shop-a','digital',20000,$t),('credit','sale','shop-a','credit',20000,$t)",
  );
  await sql(
    "insert into inventory_movements(id,shop_id,product_id,type,quantity,created_by,created_at) values('stock','shop-a','product','openingStock',3000,'owner',$t),('sold','shop-a','product','sale',-1000,'cashier',$t)",
  );
  await sql(
    "insert into purchases(id,shop_id,supplier_id,subtotal,discount_total,total,paid_amount,payment_status,created_by,created_at) values('purchase','shop-a',null,50000,0,50000,30000,'partiallyPaid','owner',$t)",
  );
  await sql(
    "insert into expenses(id,shop_id,category,amount,payment_method,description,created_by,created_at,expense_at) values('expense','shop-a','Rent',8000,'cash','Rent','owner',$t,$t)",
  );
  await sql(
    "insert into customers(id,shop_id,name,created_at,updated_at) values('customer','shop-a','Customer',$t,$t)",
  );
  await sql(
    "insert into customer_ledger_entries(id,shop_id,customer_id,type,amount,created_by,created_at) values('cl','shop-a','customer','creditSale',20000,'owner',$t)",
  );
  await sql(
    "insert into suppliers(id,shop_id,name,created_at,updated_at) values('supplier','shop-a','Supplier',$t,$t)",
  );
  await sql(
    "insert into supplier_ledger_entries(id,shop_id,supplier_id,type,amount,created_by,created_at) values('sl','shop-a','supplier','purchase',20000,'owner',$t)",
  );
}
