import 'package:drift/native.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shop parent must precede membership and cached customer survives', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const t = 1789344000;
    await expectLater(
      db.customStatement(
        "insert into shop_users(id,shop_id,user_id,role,is_active,created_at) values('m','shop','owner','owner',1,$t)",
      ),
      throwsA(anything),
    );
    await db.customStatement(
      "insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at) values('shop','Test','','','trial','trial',$t,$t)",
    );
    await db.customStatement(
      "insert into shop_users(id,shop_id,user_id,role,is_active,created_at) values('m','shop','owner','owner',1,$t)",
    );
    await db.customStatement(
      "insert into customers(id,shop_id,name,created_at,updated_at) values('customer','shop','Cached customer',$t,$t)",
    );
    expect(
      (await db.select(db.customers).get()).single.name,
      'Cached customer',
    );
  });

  test('DAAL sale is immediately summarized, paged and uses snapshots', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day).toUtc().millisecondsSinceEpoch ~/
        1000;
    await db.customStatement(
      "insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at) values('shop','Test','','','trial','trial',$start,$start)",
    );
    await db.customStatement(
      "insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at) values('device','shop','PC','windowsDesktop','x',$start,$start)",
    );
    await db.customStatement(
      "insert into cashiers(id,shop_id,display_name,login_code,created_at,updated_at) values('cashier','shop','Ali','1',$start,$start)",
    );
    await db.customStatement(
      "insert into shop_products(id,shop_id,custom_name,purchase_price,sale_price,created_at,updated_at) values('product','shop','Changed name',40000,60000,$start,$start)",
    );
    await db.customStatement(
      "insert into sales(id,shop_id,cashier_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at) values('sale','shop','cashier','device',57000,0,0,57000,'paid','completed',$start)",
    );
    await db.customStatement(
      "insert into sale_items(id,shop_id,sale_id,product_id,product_name_snapshot,quantity,cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at) values('item','shop','sale','product','DAAL',1000,45000,57000,0,57000,$start)",
    );
    await db.customStatement(
      "insert into sale_payments(id,sale_id,shop_id,payment_method,amount,created_at) values('payment','sale','shop','cash',57000,$start)",
    );
    final repo = DriftSalesHistoryRepository(db, shopId: 'shop');
    final summary = await repo.watchToday().first;
    expect((summary.total, summary.bills, summary.cash), (57000, 1, 57000));
    final row = (await repo.page(
      filter: SaleHistoryFilter(
        range: ReportRange(
          DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true),
          DateTime.fromMillisecondsSinceEpoch(
            (start + 86400) * 1000,
            isUtc: true,
          ),
          label: 'test',
        ),
      ),
    )).single;
    expect(row.sync, 'Pending');
    final detail = await repo.detail(row);
    expect(detail.lines.single.name, 'DAAL');
    expect(detail.lines.single.unitPrice, 57000);
  });

  test('SQL filters cover dates, payments, search and active pagination', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const base = 1789344000;
    await db.customStatement(
      "insert into shops(id,name,phone,address,subscription_plan,subscription_status,created_at,updated_at) values('shop','Test','','','trial','trial',$base,$base)",
    );
    await db.customStatement(
      "insert into devices(id,shop_id,device_name,device_type,device_identifier,created_at,updated_at) values('device','shop','PC','windowsDesktop','x',$base,$base)",
    );
    await db.customStatement(
      "insert into cashiers(id,shop_id,display_name,login_code,created_at,updated_at) values('cashier','shop','Ali','1',$base,$base)",
    );
    await db.customStatement(
      "insert into customers(id,shop_id,name,phone,created_at,updated_at) values('customer','shop','Ahmed Buyer','03001234567',$base,$base)",
    );
    Future<void> sale(
      String id,
      int at,
      List<String> methods, {
      String? invoice,
      String? customer,
    }) async {
      await db.customStatement(
        "insert into sales(id,shop_id,cashier_id,customer_id,device_id,invoice_number,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at) values('$id','shop','cashier',${customer == null ? 'null' : "'$customer'"},'device',${invoice == null ? 'null' : "'$invoice'"},100,0,0,100,'paid','completed',$at)",
      );
      for (var i = 0; i < methods.length; i++) {
        await db.customStatement(
          "insert into sale_payments(id,sale_id,shop_id,payment_method,amount,created_at) values('$id-p$i','$id','shop','${methods[i]}',${100 ~/ methods.length},$at)",
        );
      }
    }

    await sale(
      'today',
      base + 3600,
      ['cash'],
      invoice: 'INV-FAST',
      customer: 'customer',
    );
    await sale('yesterday', base - 3600, ['digital']);
    await sale('week', base - 86400 * 2, ['credit']);
    await sale('split', base - 86400 * 8, ['cash', 'digital']);
    for (var i = 0; i < 55; i++) {
      await sale('page$i', base + 4000 + i, ['cash']);
    }
    final repo = DriftSalesHistoryRepository(db, shopId: 'shop');
    SaleHistoryFilter f(
      DateTime a,
      DateTime b, {
      SalePaymentFilter p = SalePaymentFilter.all,
      String q = '',
    }) => SaleHistoryFilter(
      range: ReportRange(a, b, label: 'x'),
      payment: p,
      query: q,
    );
    final today = f(
      DateTime.fromMillisecondsSinceEpoch(base * 1000, isUtc: true),
      DateTime.fromMillisecondsSinceEpoch((base + 86400) * 1000, isUtc: true),
    );
    expect(await repo.page(filter: today), hasLength(50));
    expect(await repo.page(filter: today, offset: 50), hasLength(6));
    expect(
      (await repo.page(
        filter: f(
          DateTime.fromMillisecondsSinceEpoch(
            (base - 86400) * 1000,
            isUtc: true,
          ),
          DateTime.fromMillisecondsSinceEpoch(base * 1000, isUtc: true),
        ),
      )).single.id,
      'yesterday',
    );
    expect(
      (await repo.page(
        filter: f(
          DateTime.fromMillisecondsSinceEpoch(
            (base - 86400 * 6) * 1000,
            isUtc: true,
          ),
          DateTime.fromMillisecondsSinceEpoch(
            (base + 86400) * 1000,
            isUtc: true,
          ),
          p: SalePaymentFilter.credit,
        ),
      )).single.id,
      'week',
    );
    expect(
      (await repo.page(
        filter: f(
          DateTime.fromMillisecondsSinceEpoch(
            (base - 86400 * 9) * 1000,
            isUtc: true,
          ),
          DateTime.fromMillisecondsSinceEpoch(
            (base - 86400 * 7) * 1000,
            isUtc: true,
          ),
          p: SalePaymentFilter.split,
        ),
      )).single.id,
      'split',
    );
    expect(
      (await repo.page(
        filter: SaleHistoryFilter(
          range: today.range,
          payment: SalePaymentFilter.digital,
        ),
      )),
      isEmpty,
    );
    expect(
      await repo.page(
        filter: SaleHistoryFilter(
          range: today.range,
          payment: SalePaymentFilter.cash,
        ),
      ),
      hasLength(50),
    );
    expect(
      (await repo.page(
        filter: SaleHistoryFilter(range: today.range, query: 'INV-FAST'),
      )).single.id,
      'today',
    );
    expect(
      (await repo.page(
        filter: SaleHistoryFilter(range: today.range, query: 'Ahmed'),
      )).single.id,
      'today',
    );
    expect(
      (await repo.page(
        filter: SaleHistoryFilter(range: today.range, query: '03001234567'),
      )).single.id,
      'today',
    );
  });
}
