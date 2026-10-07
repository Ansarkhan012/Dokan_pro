import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../pos/pos_state.dart';
import '../reports/report_models.dart';
import '../receipts/receipt_model.dart';
import '../receipts/receipt_view.dart';
import '../../core/format/display_format.dart';
import '../../core/ui/pos_ui.dart';
import 'domain/bill_reference.dart';

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
        " and (lower(coalesce(s.invoice_number,'')) like ? or lower(coalesce(cu.name,'')) like ? or lower(coalesce(cu.phone,'')) like ?",
      );
      final contains = '%$query%';
      variables.addAll([
        Variable(contains),
        Variable(contains),
        Variable(contains),
      ]);
      // The printed bill code is the UUID tail (see billReference).
      if (searchedBillCode(query) case final code?) {
        where.write(' or lower(s.id) like ?');
        variables.add(Variable('%$code'));
      }
      where.write(')');
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
      '''select s.id,s.invoice_number,s.created_at,s.grand_total,
      case when count(distinct p.payment_method)>1 then 'Split' else coalesce(max(p.payment_method),'Unknown') end method,
      coalesce(ca.display_name,s.cashier_id) cashier,cu.name customer,
      case when so.status in ('needsAttention','blockedAuth') or (so.error_class='flagged' and so.acknowledged_at is null) then 'Needs attention' when so.status='synced' or s.synced_at is not null then 'Synced' else 'Pending' end sync,
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
    reference: billReference(
      r.data['id'] as String,
      invoiceNumber: r.data['invoice_number'] as String?,
    ),
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
          '${formatDisplayDateTime(row.createdAt)} • ${row.reason} • ${formatPkr(row.refundAmount)}',
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

  Future<void> _open(BuildContext c, SaleHistoryRow r) async {
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
  }

  // One scroll view for summary, filters and bills: in a short window nothing
  // is pinned that could overflow the remaining height.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = constraints.maxWidth > 1132
          ? (constraints.maxWidth - 1100) / 2
          : 16.0;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 14, side, 0),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<SalesTodaySummary>(
                stream: widget.repository.watchToday(),
                builder: (c, s) => _TodaySummary(
                  s.data ?? const SalesTodaySummary(0, 0, 0, 0, 0),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 8),
            sliver: SliverToBoxAdapter(child: _filters(context)),
          ),
          if (error != null)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: side),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: Text(error!)),
                    TextButton(onPressed: _reset, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          if (rows.isEmpty && !loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No sales match these filters.')),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 4, side, 8),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (c, i) =>
                    _BillRow(row: rows[i], onTap: () => _open(c, rows[i])),
              ),
            ),
          if (more)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 4, side, 20),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: OutlinedButton(
                    onPressed: loading ? null : _load,
                    child: Text(loading ? 'Loading…' : 'Load more'),
                  ),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      );
    },
  );

  Widget _filters(BuildContext context) => Theme(
    data: posFormTheme(Theme.of(context)),
    child: PosCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  controller: search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _reset(),
                  decoration: InputDecoration(
                    labelText: 'Bill #, customer name or phone',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: _reset,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: FutureBuilder<List<(String, String)>>(
                  future: widget.repository.cashiers(),
                  builder: (context, snapshot) =>
                      DropdownButtonFormField<String?>(
                        initialValue: cashierId,
                        isExpanded: true,
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
                              child: Text(
                                cashier.$2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          cashierId = value;
                          _reset();
                        },
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final value in SaleHistoryPeriod.values)
                ChoiceChip(
                  label: Text(switch (value) {
                    SaleHistoryPeriod.today => 'Today',
                    SaleHistoryPeriod.yesterday => 'Yesterday',
                    SaleHistoryPeriod.week => 'This Week',
                    SaleHistoryPeriod.custom =>
                      customRange == null ? 'Custom dates' : customRange!.label,
                  }),
                  selected: period == value,
                  onSelected: (_) => _selectPeriod(value),
                ),
              const SizedBox(height: 28, child: VerticalDivider(width: 16)),
              for (final value in SalePaymentFilter.values)
                FilterChip(
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
            ],
          ),
        ],
      ),
    ),
  );
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary(this.summary);
  final SalesTodaySummary summary;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      _SummaryTile(
        label: "Today's sales",
        value: formatPkr(summary.total),
        detail: '${summary.bills} ${summary.bills == 1 ? 'bill' : 'bills'}',
        prominent: true,
      ),
      _SummaryTile(label: 'Cash', value: formatPkr(summary.cash)),
      _SummaryTile(label: 'Digital', value: formatPkr(summary.digital)),
      _SummaryTile(label: 'Udhaar', value: formatPkr(summary.credit)),
    ],
  );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    this.detail,
    this.prominent = false,
  });
  final String label, value;
  final String? detail;
  final bool prominent;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: prominent ? 220 : 150),
    child: PosCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: posMuted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: prominent ? 22 : 16,
              fontWeight: FontWeight.w800,
              color: prominent ? posAccent : null,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: const TextStyle(color: posMuted, fontSize: 12),
            ),
        ],
      ),
    ),
  );
}

/// Bill status as computed by the history query, shown as a pill.
StatusPill saleStatusPill(String status) => StatusPill(
  status,
  tone: switch (status) {
    'Completed' => StatusTone.success,
    'Voided' => StatusTone.danger,
    _ => StatusTone.warning,
  },
);

/// Sync state as computed by the history query, in plain wording.
StatusPill saleSyncPill(String sync) => switch (sync) {
  'Synced' => const StatusPill(
    'Synced',
    tone: StatusTone.success,
    icon: Icons.cloud_done_outlined,
  ),
  'Needs attention' => const StatusPill(
    'Needs attention',
    tone: StatusTone.danger,
    icon: Icons.sync_problem,
  ),
  _ => const StatusPill(
    'Waiting to sync',
    tone: StatusTone.info,
    icon: Icons.cloud_queue,
  ),
};

class _BillRow extends StatelessWidget {
  const _BillRow({required this.row, required this.onTap});
  final SaleHistoryRow row;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final details = [
      formatDisplayDateTime(row.at),
      paymentMethodLabel(row.method),
      row.cashier,
      if (row.customer != null) row.customer!,
    ].join(' • ');
    return PosCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.reference,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: posMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatPkr(row.total),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [saleStatusPill(row.status), saleSyncPill(row.sync)],
              ),
            ],
          ),
        ],
      ),
    );
  }
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
    title: Row(
      children: [
        Expanded(child: Text(detail.sale.reference)),
        saleStatusPill(detail.sale.status),
      ],
    ),
    content: SizedBox(
      width: 480,
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            '$shop • ${formatDisplayDateTime(detail.sale.at)}',
            style: const TextStyle(color: posMuted),
          ),
          Text(
            'Cashier: ${detail.sale.cashier}',
            style: const TextStyle(color: posMuted),
          ),
          if (detail.sale.customer != null)
            Text(
              'Customer: ${detail.sale.customer}',
              style: const TextStyle(color: posMuted),
            ),
          const Divider(height: 20),
          for (final l in detail.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${l.name}\n${formatDisplayQuantity(l.quantity)} × ${formatPkr(l.unitPrice)}',
                    ),
                  ),
                  Text(
                    formatPkr(l.total),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const Divider(height: 20),
          _amountRow('Subtotal', detail.subtotal),
          if (detail.discount > 0) _amountRow('Discount', detail.discount),
          _amountRow('Total', detail.sale.total, strong: true),
          if (detail.sale.returnedAmount > 0) ...[
            _amountRow('Returned', detail.sale.returnedAmount),
            _amountRow('Net', detail.sale.effectiveTotal, strong: true),
          ],
          for (final p in detail.payments.entries)
            _amountRow('Paid by ${paymentMethodLabel(p.key)}', p.value),
          for (final value in detail.returns)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Return: $value'),
            ),
          if (detail.voidReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Void reason: ${detail.voidReason}'),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: saleSyncPill(detail.sale.sync),
          ),
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

Widget _amountRow(String label, int amount, {bool strong = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        formatPkr(amount),
        style: TextStyle(fontWeight: strong ? FontWeight.w800 : null),
      ),
    ],
  ),
);
