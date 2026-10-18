import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../pos/pos_state.dart';
import '../reports/report_models.dart';
import '../receipts/receipt_model.dart';
import '../receipts/receipt_view.dart';
import '../../core/domain/enums.dart';
import '../../core/format/display_format.dart';
import '../../core/ui/pos_ui.dart';
import 'domain/bill_reference.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';
import '../../core/l10n/localized_format.dart';
import '../../core/l10n/messages.dart';

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
  const SaleDetailLine(
    this.name,
    this.quantity,
    this.unitPrice,
    this.total, {
    this.measureUnit,
  });
  final String name;
  final int quantity, unitPrice, total;

  /// From `measure_unit_snapshot`; null for a count line.
  final MeasureUnit? measureUnit;
}

final class SaleHistoryDetail {
  const SaleHistoryDetail(
    this.sale,
    this.lines,
    this.payments,
    this.subtotal,
    this.discount,
    this.returns,
    this.voidReason, {
    this.returnEntries = const [],
  });
  final SaleHistoryRow sale;

  /// The same returns as [returns], unformatted, so screens can show their
  /// date and amount in the UI language. Display only.
  final List<({DateTime at, String reason, int refund})> returnEntries;
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
          measureUnit: line.measureUnit,
        ),
    ],
    subtotal: subtotal,
    discount: discount,
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
          'select product_name_snapshot,quantity,sale_price_snapshot,line_total,measure_unit_snapshot from sale_items where shop_id=? and sale_id=? order by created_at',
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
              measureUnit: MeasureUnit.tryParse(
                r.data['measure_unit_snapshot'] as String?,
              ),
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
      returnEntries: [
        for (final row in returned)
          (at: row.createdAt, reason: row.reason, refund: row.refundAmount),
      ],
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
        // Translated on screen (localizedMessage).
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
                    Expanded(
                      child: Text(localizedMessage(context.l10n, error!)),
                    ),
                    TextButton(
                      onPressed: _reset,
                      child: Text(context.l10n.commonRetry),
                    ),
                  ],
                ),
              ),
            ),
          if (rows.isEmpty && !loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(context.l10n.billsNoMatch)),
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
                    child: Text(
                      loading
                          ? context.l10n.commonLoading
                          : context.l10n.productsLoadMore,
                    ),
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
                    labelText: context.l10n.billsSearchLabel,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: context.l10n.commonSearch,
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
                        decoration: InputDecoration(
                          labelText: context.l10n.billsCashier,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(context.l10n.billsAllCashiers),
                          ),
                          for (final cashier
                              in snapshot.data ?? const <(String, String)>[])
                            DropdownMenuItem(
                              value: cashier.$1,
                              child: Text(
                                bidiName(context, cashier.$2),
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
                    SaleHistoryPeriod.today => context.l10n.billsToday,
                    SaleHistoryPeriod.yesterday => context.l10n.billsYesterday,
                    SaleHistoryPeriod.week => context.l10n.billsThisWeek,
                    // A chosen range's label is always `Custom`.
                    SaleHistoryPeriod.custom =>
                      customRange == null
                          ? context.l10n.billsCustomDates
                          : context.l10n.billsCustom,
                  }),
                  selected: period == value,
                  onSelected: (_) => _selectPeriod(value),
                ),
              const SizedBox(height: 28, child: VerticalDivider(width: 16)),
              for (final value in SalePaymentFilter.values)
                FilterChip(
                  label: Text(switch (value) {
                    SalePaymentFilter.all => context.l10n.billsAllPayments,
                    SalePaymentFilter.cash => context.l10n.paymentCash,
                    SalePaymentFilter.digital => context.l10n.paymentDigital,
                    SalePaymentFilter.credit => context.l10n.paymentUdhaar,
                    SalePaymentFilter.split => context.l10n.paymentSplit,
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String money(int minor) => bidiMoney(context, formatPkr(minor));
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SummaryTile(
          label: l10n.billsTodaySales,
          value: money(summary.total),
          detail: summary.bills == 1
              ? l10n.billsCountOne('${summary.bills}')
              : l10n.billsCountMany('${summary.bills}'),
          prominent: true,
        ),
        _SummaryTile(label: l10n.paymentCash, value: money(summary.cash)),
        _SummaryTile(label: l10n.paymentDigital, value: money(summary.digital)),
        _SummaryTile(label: l10n.paymentUdhaar, value: money(summary.credit)),
      ],
    );
  }
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
StatusPill saleStatusPill(BuildContext context, String status) => StatusPill(
  localizedSaleStatus(context.l10n, status),
  tone: switch (status) {
    'Completed' => StatusTone.success,
    'Voided' => StatusTone.danger,
    _ => StatusTone.warning,
  },
);

/// Sync state as computed by the history query, in plain wording.
StatusPill saleSyncPill(BuildContext context, String sync) => switch (sync) {
  'Synced' => StatusPill(
    context.l10n.syncStatusSynced,
    tone: StatusTone.success,
    icon: Icons.cloud_done_outlined,
  ),
  'Needs attention' => StatusPill(
    context.l10n.syncStatusNeedsAttention,
    tone: StatusTone.danger,
    icon: Icons.sync_problem,
  ),
  _ => StatusPill(
    context.l10n.billWaitingToSync,
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
    final l10n = context.l10n;
    final details = [
      localizedDateTime(l10n, row.at),
      localizedPaymentMethod(l10n, row.method),
      bidiName(context, row.cashier),
      if (row.customer != null) bidiName(context, row.customer!),
    ].join(' • ');
    return PosCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // The amount and pills keep their natural width, but never more than
      // 55% of the row: on a narrow phone at a large text size the pills
      // wrap instead of overflowing.
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bidiId(context, row.reference),
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
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * .55),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bidiMoney(context, formatPkr(row.total)),
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
                    children: [
                      saleStatusPill(context, row.status),
                      saleSyncPill(context, row.sync),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget amount(String label, int minor, {bool strong = false}) =>
        _amountRow(label, bidiMoney(context, formatPkr(minor)), strong: strong);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(bidiId(context, detail.sale.reference))),
          saleStatusPill(context, detail.sale.status),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              '${bidiName(context, shop)} • ${localizedDateTime(l10n, detail.sale.at)}',
              style: const TextStyle(color: posMuted),
            ),
            Text(
              l10n.billCashier(bidiName(context, detail.sale.cashier)),
              style: const TextStyle(color: posMuted),
            ),
            if (detail.sale.customer != null)
              Text(
                l10n.receiptCustomer(bidiName(context, detail.sale.customer!)),
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
                        '${productDisplayName(context, l.name)}\n'
                        '${bidiQuantity(context, localizedLineQuantity(l10n, l.quantity, l.measureUnit))} × '
                        '${bidiMoney(context, formatPkr(l.unitPrice))}',
                      ),
                    ),
                    Text(
                      bidiMoney(context, formatPkr(l.total)),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            amount(l10n.posSubtotal, detail.subtotal),
            if (detail.discount > 0) amount(l10n.posDiscount, detail.discount),
            amount(l10n.posTotal, detail.sale.total, strong: true),
            if (detail.sale.returnedAmount > 0) ...[
              amount(l10n.billReturned, detail.sale.returnedAmount),
              amount(l10n.billNet, detail.sale.effectiveTotal, strong: true),
            ],
            for (final p in detail.payments.entries)
              amount(
                l10n.billPaidBy(localizedPaymentMethod(l10n, p.key)),
                p.value,
              ),
            for (final r in detail.returnEntries)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.billReturnLine(
                    localizedDateTime(l10n, r.at),
                    bidiName(context, r.reason),
                    bidiMoney(context, formatPkr(r.refund)),
                  ),
                ),
              ),
            if (detail.voidReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.billVoidReason(bidiName(context, detail.voidReason!)),
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: saleSyncPill(context, detail.sale.sync),
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
            child: Text(l10n.billVoid),
          ),
        if (onReturn != null)
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(context);
              await onReturn!(detail);
            },
            child: Text(l10n.billReturnItems),
          ),
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            showPrintableReceipt(context, receipt);
          },
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(l10n.posViewReprint),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonClose),
        ),
      ],
    );
  }
}

Widget _amountRow(String label, String amount, {bool strong = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            amount,
            style: TextStyle(fontWeight: strong ? FontWeight.w800 : null),
          ),
        ],
      ),
    );
