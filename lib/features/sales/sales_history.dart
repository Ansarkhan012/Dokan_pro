import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../pos/pos_state.dart';
import '../reports/report_models.dart';
import '../receipts/receipt_model.dart';
import '../receipts/receipt_view.dart';

enum SaleHistoryPeriod { today, yesterday, week, custom }

enum SalePaymentFilter { all, cash, digital, credit, split }

final class SaleHistoryFilter {
  const SaleHistoryFilter({
    required this.range,
    this.payment = SalePaymentFilter.all,
    this.query = '',
    this.cashierId,
  });
  final ReportRange range;
  final SalePaymentFilter payment;
  final String query;
  final String? cashierId;
}

final class SalesTodaySummary {
  const SalesTodaySummary(
    this.total,
    this.bills,
    this.cash,
    this.digital,
    this.credit,
  );
  final int total, bills, cash, digital, credit;
}

final class SaleHistoryRow {
  const SaleHistoryRow({
    required this.id,
    required this.reference,
    required this.at,
    required this.total,
    required this.method,
    required this.cashier,
    this.customer,
    required this.sync,
    required this.status,
    required this.returnedAmount,
  });
  final String id, reference, method, cashier, sync;
  final String status;
  final String? customer;
  final DateTime at;
  final int total;
  final int returnedAmount;
  int get effectiveTotal => total - returnedAmount;
}

final class SaleDetailLine {
  const SaleDetailLine(this.name, this.quantity, this.unitPrice, this.total);
  final String name;
  final int quantity, unitPrice, total;
}

final class SaleHistoryDetail {
  const SaleHistoryDetail(
    this.sale,
    this.lines,
    this.payments,
    this.subtotal,
    this.discount,
    this.returns,
    this.voidReason,
  );
  final SaleHistoryRow sale;
  final List<SaleDetailLine> lines;
  final Map<String, int> payments;
  final int subtotal, discount;
  final List<String> returns;
  final String? voidReason;

  ReceiptModel toReceipt(
    String shopName, {
    String? phone,
    String? address,
    String? footer,
  }) => ReceiptModel(
    shopName: shopName,
    phone: phone,
    address: address,
    footer: footer,
    reference: sale.reference,
    dateTime: sale.at,
    cashier: sale.cashier,
    customer: sale.customer,
    lines: [
      for (final line in lines)
        ReceiptLine(
          name: line.name,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          total: line.total,
        ),
    ],
    subtotal: subtotal,
    total: sale.total,
    returned: sale.returnedAmount,
    status: sale.status,
    payments: Map.unmodifiable(payments),
  );
}

final class DriftSalesHistoryRepository {
  DriftSalesHistoryRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  Stream<SalesTodaySummary> watchToday() {
    final range = ReportRange.forPreset(
      ReportRangePreset.today,
      DateTime.now().toUtc(),
    );
    return db
        .customSelect(
          "with eligible as (select id,grand_total from sales where shop_id=? and sale_status='completed' and created_at>=? and created_at<?) select coalesce(sum(grand_total),0) total,count(*) bills,coalesce((select sum(case when p.payment_method='cash' then p.amount else 0 end) from sale_payments p join eligible e on e.id=p.sale_id),0) cash,coalesce((select sum(case when p.payment_method='digital' then p.amount else 0 end) from sale_payments p join eligible e on e.id=p.sale_id),0) digital,coalesce((select sum(case when p.payment_method='credit' then p.amount else 0 end) from sale_payments p join eligible e on e.id=p.sale_id),0) credit from eligible",
          variables: [
            Variable(shopId),
            Variable(range.startUtc),
            Variable(range.endUtc),
          ],
          readsFrom: {db.sales, db.salePayments},
        )
        .watchSingle()
        .map(
          (r) => SalesTodaySummary(
            r.data['total'] as int,
            r.data['bills'] as int,
            r.data['cash'] as int,
            r.data['digital'] as int,
            r.data['credit'] as int,
          ),
        );
  }

  Future<List<SaleHistoryRow>> page({
    required SaleHistoryFilter filter,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = filter.query.trim().toLowerCase();
    String? exactSaleId;
    if (query.isNotEmpty) {
      final invoiceMatch = await db
          .customSelect(
            'select id from sales where shop_id=? and invoice_number=? limit 1',
            variables: [Variable(shopId), Variable(filter.query.trim())],
          )
          .getSingleOrNull();
      final idMatch = invoiceMatch == null
          ? await db
                .customSelect(
                  'select id from sales where shop_id=? and id=? limit 1',
                  variables: [Variable(shopId), Variable(filter.query.trim())],
                )
                .getSingleOrNull()
          : null;
      exactSaleId = (invoiceMatch ?? idMatch)?.data['id'] as String?;
    }
    final where = StringBuffer(
      "s.shop_id=? and s.sale_status='completed' and s.created_at>=? and s.created_at<?",
    );
    final variables = <Variable<Object>>[
      Variable(shopId),
      Variable(filter.range.startUtc),
      Variable(filter.range.endUtc),
    ];
    if (exactSaleId != null) {
      where.write(' and s.id=?');
      variables.add(Variable(exactSaleId));
    } else if (query.isNotEmpty) {
      where.write(
        " and (lower(coalesce(s.invoice_number,'')) like ? or lower(coalesce(cu.name,'')) like ? or lower(coalesce(cu.phone,'')) like ?)",
      );
      final contains = '%$query%';
      variables.addAll([
        Variable(contains),
        Variable(contains),
        Variable(contains),
      ]);
    }
    if (filter.cashierId != null) {
      where.write(' and s.cashier_id=?');
      variables.add(Variable(filter.cashierId!));
    }
    final having = switch (filter.payment) {
      SalePaymentFilter.all => '',
      SalePaymentFilter.split =>
        ' having count(distinct case when p.amount>0 then p.payment_method end)>1',
      final method =>
        ' having count(distinct case when p.amount>0 then p.payment_method end)=1 and max(case when p.amount>0 then p.payment_method end)=\'${method.name}\'',
    };
    variables.addAll([Variable(limit), Variable(offset)]);
    final rows = await db.customSelect(
      '''select s.id,coalesce(s.invoice_number,s.id) reference,s.created_at,s.grand_total,
      case when count(distinct p.payment_method)>1 then 'Split' else coalesce(max(p.payment_method),'Unknown') end method,
      coalesce(ca.display_name,s.cashier_id) cashier,cu.name customer,
      case when so.status='failed' then 'Failed' when so.status='synced' or s.synced_at is not null then 'Synced' else 'Pending' end sync,
      case when sv.id is not null then 'Voided' when coalesce((select sum(refund_amount) from sale_returns where shop_id=s.shop_id and original_sale_id=s.id),0)>=s.grand_total then 'Fully Returned' when coalesce((select sum(refund_amount) from sale_returns where shop_id=s.shop_id and original_sale_id=s.id),0)>0 then 'Partially Returned' else 'Completed' end status,
      case when sv.id is not null then s.grand_total else coalesce((select sum(refund_amount) from sale_returns where shop_id=s.shop_id and original_sale_id=s.id),0) end returned_amount
      from sales s left join sale_payments p on p.sale_id=s.id and p.shop_id=s.shop_id
      left join cashiers ca on ca.id=s.cashier_id and ca.shop_id=s.shop_id left join customers cu on cu.id=s.customer_id and cu.shop_id=s.shop_id
      left join sync_operations so on so.entity_id=s.id and so.shop_id=s.shop_id
      left join sale_voids sv on sv.original_sale_id=s.id and sv.shop_id=s.shop_id
      where $where group by s.id$having order by s.created_at desc,s.id desc limit ? offset ?''',
      variables: variables,
    ).get();
    return rows.map(_row).toList();
  }

  /// The newest completed sale this device committed at or after [since],
  /// read only from local data (POS "last sale saved" after a restart).
  Future<SaleHistoryRow?> lastSaleOnDevice(
    String deviceId, {
    required DateTime since,
  }) async {
    final latest =
        await (db.select(db.sales)
              ..where(
                (s) =>
                    s.shopId.equals(shopId) &
                    s.deviceId.equals(deviceId) &
                    s.createdAt.isBiggerOrEqualValue(since),
              )
              ..orderBy([
                (s) => OrderingTerm.desc(s.createdAt),
                (s) => OrderingTerm.desc(s.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    return latest == null ? null : sale(latest.id);
  }

  /// The history row of one completed local sale, whatever its age or sync
  /// state: the same row the Bills list shows and reprints from.
  Future<SaleHistoryRow?> sale(String saleId) async {
    final stored =
        await (db.select(db.sales)
              ..where((s) => s.shopId.equals(shopId) & s.id.equals(saleId)))
            .getSingleOrNull();
    if (stored == null) return null;
    final rows = await page(
      filter: SaleHistoryFilter(
        range: ReportRange(
          stored.createdAt,
          stored.createdAt.add(const Duration(seconds: 1)),
          label: 'Sale',
        ),
        query: stored.id,
      ),
      limit: 1,
    );
    return rows.firstOrNull;
  }

  Future<List<(String, String)>> cashiers() async {
    final rows =
        await (db.select(db.cashiers)
              ..where((t) => t.shopId.equals(shopId))
              ..orderBy([(t) => OrderingTerm.asc(t.displayName)]))
            .get();
    return rows.map((row) => (row.id, row.displayName)).toList();
  }

  SaleHistoryRow _row(QueryRow r) => SaleHistoryRow(
    id: r.data['id'] as String,
    reference: r.data['reference'] as String,
    at: DateTime.fromMillisecondsSinceEpoch(
      (r.data['created_at'] as int) * 1000,
      isUtc: true,
    ),
    total: r.data['grand_total'] as int,
    method: r.data['method'] as String,
    cashier: r.data['cashier'] as String,
    customer: r.data['customer'] as String?,
    sync: r.data['sync'] as String,
    status: r.data['status'] as String,
    returnedAmount: r.data['returned_amount'] as int,
  );

  Future<SaleHistoryDetail> detail(SaleHistoryRow sale) async {
    final lines = await db
        .customSelect(
          'select product_name_snapshot,quantity,sale_price_snapshot,line_total from sale_items where shop_id=? and sale_id=? order by created_at',
          variables: [Variable(shopId), Variable(sale.id)],
        )
        .get();
    final payments = await db
        .customSelect(
          'select payment_method,sum(amount) amount from sale_payments where shop_id=? and sale_id=? group by payment_method',
          variables: [Variable(shopId), Variable(sale.id)],
        )
        .get();
    final s =
        await (db.select(db.sales)
              ..where((x) => x.shopId.equals(shopId) & x.id.equals(sale.id)))
            .getSingle();
    final returned =
        await (db.select(db.saleReturns)
              ..where(
                (x) =>
                    x.shopId.equals(shopId) & x.originalSaleId.equals(sale.id),
              )
              ..orderBy([(x) => OrderingTerm.asc(x.createdAt)]))
            .get();
    final voided =
        await (db.select(db.saleVoids)..where(
              (x) => x.shopId.equals(shopId) & x.originalSaleId.equals(sale.id),
            ))
            .getSingleOrNull();
    return SaleHistoryDetail(
      sale,
      lines
          .map(
            (r) => SaleDetailLine(
              r.data['product_name_snapshot'] as String,
              r.data['quantity'] as int,
              r.data['sale_price_snapshot'] as int,
              r.data['line_total'] as int,
            ),
          )
          .toList(),
      {
        for (final p in payments)
          p.data['payment_method'] as String: p.data['amount'] as int,
      },
      s.subtotal,
      s.discountTotal,
      [
        for (final row in returned)
          '${row.createdAt.toLocal()} • ${row.reason} • ${formatPkr(row.refundAmount)}',
      ],
      voided?.reason,
    );
  }

  Future<ReceiptModel> receipt(SaleHistoryDetail detail) async {
    final shop = await (db.select(
      db.shops,
    )..where((row) => row.id.equals(shopId))).getSingle();
    return detail.toReceipt(
      shop.name,
      phone: shop.receiptShowPhone && shop.phone.isNotEmpty ? shop.phone : null,
      address: shop.receiptShowAddress && shop.address.isNotEmpty
          ? shop.address
          : null,
      footer: shop.receiptFooter.isEmpty ? null : shop.receiptFooter,
    );
  }
}

class SalesHistoryView extends StatefulWidget {
  const SalesHistoryView({
    super.key,
    required this.repository,
    required this.shopName,
    this.onReturn,
    this.onVoid,
  });
  final DriftSalesHistoryRepository repository;
  final String shopName;
  final Future<void> Function(SaleHistoryDetail detail)? onReturn;
  final Future<void> Function(SaleHistoryDetail detail)? onVoid;
  @override
  State<SalesHistoryView> createState() => _SalesHistoryViewState();
}

class _SalesHistoryViewState extends State<SalesHistoryView> {
  static const _pageSize = 50;
  final rows = <SaleHistoryRow>[];
  final search = TextEditingController();
  bool loading = false, more = true;
  String? error;
  SaleHistoryPeriod period = SaleHistoryPeriod.today;
  SalePaymentFilter payment = SalePaymentFilter.all;
  String? cashierId;
  ReportRange? customRange;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (loading || !more) return;
    final request = generation;
    setState(() => loading = true);
    try {
      final next = await widget.repository.page(
        filter: SaleHistoryFilter(
          range: _range,
          payment: payment,
          query: search.text,
          cashierId: cashierId,
        ),
        limit: _pageSize,
        offset: rows.length,
      );
      if (!mounted || request != generation) return;
      setState(() {
        rows.addAll(next);
        more = next.length == _pageSize;
        error = null;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = 'Sales could not be loaded. Please try again.');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  ReportRange get _range {
    final now = DateTime.now().toUtc();
    switch (period) {
      case SaleHistoryPeriod.today:
        return ReportRange.forPreset(ReportRangePreset.today, now);
      case SaleHistoryPeriod.week:
        return ReportRange.forPreset(ReportRangePreset.week, now);
      case SaleHistoryPeriod.yesterday:
        final today = ReportRange.forPreset(ReportRangePreset.today, now);
        return ReportRange(
          today.startUtc.subtract(const Duration(days: 1)),
          today.startUtc,
          label: 'Yesterday',
        );
      case SaleHistoryPeriod.custom:
        return customRange ??
            ReportRange.forPreset(ReportRangePreset.today, now);
    }
  }

  Future<void> _reset() async {
    generation++;
    setState(() {
      rows.clear();
      more = true;
      loading = false;
      error = null;
    });
    await _load();
  }

  Future<void> _selectPeriod(SaleHistoryPeriod value) async {
    if (value == SaleHistoryPeriod.custom) {
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (selected == null || !mounted) return;
      customRange = ReportRange.custom(selected.start, selected.end);
    }
    period = value;
    await _reset();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      StreamBuilder<SalesTodaySummary>(
        stream: widget.repository.watchToday(),
        builder: (c, s) {
          final x = s.data ?? const SalesTodaySummary(0, 0, 0, 0, 0);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 24,
                children: [
                  Text("Today's Sales ${formatPkr(x.total)}"),
                  Text('Bills ${x.bills}'),
                  Text('Cash ${formatPkr(x.cash)}'),
                  Text('Digital ${formatPkr(x.digital)}'),
                  Text('Udhaar ${formatPkr(x.credit)}'),
                ],
              ),
            ),
          );
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reset(),
              decoration: InputDecoration(
                labelText: 'Receipt, customer name or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: _reset,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final value in SaleHistoryPeriod.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (value) {
                          SaleHistoryPeriod.today => 'Today',
                          SaleHistoryPeriod.yesterday => 'Yesterday',
                          SaleHistoryPeriod.week => 'This Week',
                          SaleHistoryPeriod.custom =>
                            customRange == null
                                ? 'Custom dates'
                                : customRange!.label,
                        }),
                        selected: period == value,
                        onSelected: (_) => _selectPeriod(value),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            FutureBuilder<List<(String, String)>>(
              future: widget.repository.cashiers(),
              builder: (context, snapshot) => DropdownButtonFormField<String?>(
                initialValue: cashierId,
                decoration: const InputDecoration(labelText: 'Cashier'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All cashiers'),
                  ),
                  for (final cashier
                      in snapshot.data ?? const <(String, String)>[])
                    DropdownMenuItem(
                      value: cashier.$1,
                      child: Text(cashier.$2),
                    ),
                ],
                onChanged: (value) {
                  cashierId = value;
                  _reset();
                },
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final value in SalePaymentFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(switch (value) {
                          SalePaymentFilter.all => 'All payments',
                          SalePaymentFilter.cash => 'Cash',
                          SalePaymentFilter.digital => 'Digital',
                          SalePaymentFilter.credit => 'Udhaar',
                          SalePaymentFilter.split => 'Split',
                        }),
                        selected: payment == value,
                        onSelected: (_) {
                          payment = value;
                          _reset();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text(error!)),
              TextButton(onPressed: _reset, child: const Text('Retry')),
            ],
          ),
        ),
      Expanded(
        child: rows.isEmpty && !loading
            ? const Center(child: Text('No sales match these filters.'))
            : ListView.builder(
                itemCount: rows.length + (more ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i == rows.length) {
                    return TextButton(
                      onPressed: loading ? null : _load,
                      child: Text(loading ? 'Loading…' : 'Load more'),
                    );
                  }
                  final r = rows[i];
                  return ListTile(
                    title: Text('${r.reference} • ${formatPkr(r.total)}'),
                    subtitle: Text(
                      '${r.at.toLocal()} • ${r.method} • ${r.cashier}${r.customer == null ? '' : ' • ${r.customer}'}',
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [Text(r.status), Text(r.sync)],
                    ),
                    onTap: () async {
                      final d = await widget.repository.detail(r);
                      final receipt = await widget.repository.receipt(d);
                      if (c.mounted) {
                        showDialog<void>(
                          context: c,
                          builder: (_) => _SaleDetailDialog(
                            shop: widget.shopName,
                            detail: d,
                            receipt: receipt,
                            onReturn: widget.onReturn,
                            onVoid: widget.onVoid,
                          ),
                        );
                      }
                    },
                  );
                },
              ),
      ),
    ],
  );
}

class _SaleDetailDialog extends StatelessWidget {
  const _SaleDetailDialog({
    required this.shop,
    required this.detail,
    required this.receipt,
    this.onReturn,
    this.onVoid,
  });
  final String shop;
  final SaleHistoryDetail detail;
  final ReceiptModel receipt;
  final Future<void> Function(SaleHistoryDetail detail)? onReturn;
  final Future<void> Function(SaleHistoryDetail detail)? onVoid;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('$shop • ${detail.sale.reference}'),
    content: SizedBox(
      width: 480,
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('${detail.sale.at.toLocal()} • ${detail.sale.cashier}'),
          if (detail.sale.customer != null)
            Text('Customer: ${detail.sale.customer}'),
          const Divider(),
          for (final l in detail.lines)
            Text(
              '${l.name}  ${l.quantity / 1000} × ${formatPkr(l.unitPrice)} = ${formatPkr(l.total)}',
            ),
          const Divider(),
          Text('Subtotal ${formatPkr(detail.subtotal)}'),
          if (detail.discount > 0)
            Text('Discount ${formatPkr(detail.discount)}'),
          Text('Total ${formatPkr(detail.sale.total)}'),
          Text('Returned ${formatPkr(detail.sale.returnedAmount)}'),
          Text('Net ${formatPkr(detail.sale.effectiveTotal)}'),
          for (final value in detail.returns) Text('Return: $value'),
          if (detail.voidReason != null) Text('Void: ${detail.voidReason}'),
          for (final p in detail.payments.entries)
            Text('${p.key}: ${formatPkr(p.value)}'),
          Text('Sync: ${detail.sale.sync}'),
        ],
      ),
    ),
    actions: [
      if (onVoid != null)
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await onVoid!(detail);
          },
          child: const Text('Void'),
        ),
      if (onReturn != null)
        OutlinedButton(
          onPressed: () async {
            Navigator.pop(context);
            await onReturn!(detail);
          },
          child: const Text('Return items'),
        ),
      TextButton.icon(
        onPressed: () {
          Navigator.pop(context);
          showPrintableReceipt(context, receipt);
        },
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('View / Reprint'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
