import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../database/app_database.dart';
import '../pos/pos_state.dart';
import 'drift_reporting_repository.dart';
import 'report_models.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.shopName,
  });
  final SupabaseClient client;
  final String shopId, shopName;
  @override
  State<OwnerDashboardScreen> createState() => _State();
}

class _State extends State<OwnerDashboardScreen> {
  AppDatabase? db;
  ReportRangePreset preset = ReportRangePreset.today;
  late Future<OwnerReport> report = _open();
  ReportRange? custom;
  Future<OwnerReport> _open() async {
    db ??= await AppDatabase.open();
    return load();
  }

  Future<OwnerReport> load() =>
      DriftReportingRepository(db!, shopId: widget.shopId).load(
        custom ?? ReportRange.forPreset(preset, DateTime.now().toUtc()),
        preset: preset,
      );
  @override
  void dispose() {
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.dashTitle(bidiName(context, widget.shopName))),
    ),
    body: FutureBuilder<OwnerReport>(
      future: report,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.dashReportFailed),
                  const SizedBox(height: 8),
                  Text('${s.error}', textAlign: TextAlign.center),
                  FilledButton(
                    // Block body: returning the Future made setState throw
                    // in debug builds, so Retry did nothing.
                    onPressed: () => setState(() {
                      report = load();
                    }),
                    child: Text(context.l10n.commonRetry),
                  ),
                ],
              ),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final r = s.data!, m = r.summary;
        final l10n = context.l10n;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in ReportRangePreset.values)
                  ChoiceChip(
                    label: Text(l10n.reportPreset(p.name, p.name)),
                    selected: preset == p,
                    onSelected: (_) => select(p),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(l10n.dashCachedNote),
            if (m.partialReturnCount > 0)
              Text(
                l10n.dashPartialReturns('${m.partialReturnCount}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) => GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: c.maxWidth > 1000
                    ? 4
                    : c.maxWidth > 600
                    ? 3
                    : 2,
                childAspectRatio: 1.8,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  _card(l10n.dashNetSalesCard, m.sales),
                  _card(l10n.purchasesTabPurchases, m.purchases),
                  _card(l10n.dashGrossProfit, m.grossProfit),
                  _card(l10n.ownerNavExpenses, m.expenses),
                  _card(l10n.dashNetProfit, m.netProfit),
                  _card(l10n.dashCustomerUdhaar, m.receivables),
                  _card(l10n.dashSupplierPayable, m.payables),
                  _card(l10n.navBills, m.billCount, money: false),
                  _card(l10n.dashLowStockCard, m.lowStockCount, money: false),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _section(l10n.dashSales, [
              _row(l10n.dashGrossSales, m.grossSales),
              _row(l10n.dashReturnsVoids, m.returns),
              _row(l10n.dashNetSales, m.sales),
              _row(l10n.dashAverageBill, m.averageBill),
              _row(l10n.paymentCash, m.cash),
              _row(l10n.paymentDigital, m.digital),
              _row(l10n.dashUdhaarCreated, m.credit),
            ]),
            _section(l10n.purchasesTabPurchases, [
              _row(l10n.dashPeriodPurchases, m.purchases),
              _row(l10n.purchaseStatusPaid, m.purchasePaid),
              _row(l10n.dashCreditCreated, m.purchaseCredit),
              _row(l10n.dashTransactions, m.purchaseCount, money: false),
            ]),
            Text(
              l10n.dashSalesVsPurchases,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            // Charts stay left to right (time runs left to right) in Urdu.
            SizedBox(
              height: 230,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: _TrendChart(r.trend),
              ),
            ),
            _rank(
              l10n.dashTopSales,
              r.topSalesProducts,
              label: (v) => productDisplayName(context, v),
            ),
            _rank(
              l10n.dashTopQuantity,
              r.topQuantityProducts,
              money: false,
              label: (v) => productDisplayName(context, v),
            ),
            _rank(
              l10n.dashTopProfit,
              r.topProfitProducts,
              label: (v) => productDisplayName(context, v),
            ),
            _rank(l10n.dashExpensesByCategory, r.expensesByCategory),
            _rank(
              l10n.dashExpensesByMethod,
              r.expensesByMethod,
              label: (v) => l10n.paymentStored(v, v),
            ),
            _rank(l10n.dashTopDebtors, r.topDebtors),
            _rank(l10n.dashTopSupplierPayable, r.topSuppliers),
            _rank(
              l10n.dashLowStockList,
              r.lowStock,
              money: false,
              secondary: true,
              label: (v) => productDisplayName(context, v),
            ),
            if (m.missingCostLines > 0)
              Text(
                l10n.dashMissingCost('${m.missingCostLines}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              l10n.dashCashierPerformance,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final c in r.cashiers)
              ListTile(
                title: Text(bidiName(context, c.name)),
                subtitle: Text(
                  l10n.dashCashierLine(
                    '${c.bills}',
                    bidiMoney(context, formatPkr(c.cash)),
                    bidiMoney(context, formatPkr(c.digital)),
                    bidiMoney(context, formatPkr(c.credit)),
                  ),
                ),
                trailing: Text(bidiMoney(context, formatPkr(c.sales))),
              ),
          ],
        );
      },
    ),
  );
  // The grid gives every card a fixed height. When the label and amount do
  // not fit (a narrow phone, a large text size, or taller Urdu script) they
  // scale down instead of overflowing; when they fit nothing changes.
  Widget _card(String l, int v, {bool money = true}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: box.maxWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l, textAlign: TextAlign.center),
                Text(
                  money ? bidiMoney(context, formatPkr(v)) : '$v',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _row(String l, int v, {bool money = true}) => ListTile(
    dense: true,
    title: Text(l),
    trailing: Text(money ? bidiMoney(context, formatPkr(v)) : '$v'),
  );
  Widget _section(String t, List<Widget> rows) => Card(
    child: ExpansionTile(
      initiallyExpanded: true,
      title: Text(t),
      children: rows,
    ),
  );
  Widget _rank(
    String t,
    List<RankedValue> rows, {
    bool money = true,
    bool secondary = false,
    String Function(String label)? label,
  }) => Card(
    child: ExpansionTile(
      title: Text(t),
      children: rows.isEmpty
          ? [ListTile(title: Text(context.l10n.dashNoData))]
          : [
              for (final r in rows)
                ListTile(
                  title: Text(
                    label == null ? bidiName(context, r.label) : label(r.label),
                  ),
                  trailing: Text(
                    bidiQuantity(
                      context,
                      '${money ? formatPkr(r.value) : r.value}${secondary ? ' / ${r.secondary}' : ''}',
                    ),
                  ),
                ),
            ],
    ),
  );
  Future<void> select(ReportRangePreset p) async {
    if (p == ReportRangePreset.custom) {
      final first = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDate: DateTime.now(),
      );
      if (first == null || !mounted) return;
      final last = await showDatePicker(
        context: context,
        firstDate: first,
        lastDate: DateTime.now(),
        initialDate: first,
      );
      if (last == null || !mounted) return;
      custom = ReportRange.custom(first, last);
    } else {
      custom = null;
    }
    setState(() {
      preset = p;
      report = load();
    });
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart(this.rows);
  final List<ReportBucket> rows;
  @override
  Widget build(BuildContext context) => rows.isEmpty
      ? Center(child: Text(context.l10n.dashNoActivity))
      : CustomPaint(painter: _Bars(rows), child: const SizedBox.expand());
}

class _Bars extends CustomPainter {
  _Bars(this.rows);
  final List<ReportBucket> rows;
  @override
  void paint(Canvas c, Size s) {
    final maxValue = rows
        .expand((r) => [r.sales, r.purchases])
        .fold<int>(1, (a, b) => a > b ? a : b);
    final width = s.width / rows.length;
    final sales = Paint()..color = const Color(0xff176b52),
        purchases = Paint()..color = Colors.orange;
    for (var i = 0; i < rows.length; i++) {
      final x = i * width,
          h1 = (rows[i].sales / maxValue) * (s.height - 30),
          h2 = (rows[i].purchases / maxValue) * (s.height - 30);
      c.drawRect(
        Rect.fromLTWH(x + width * .15, s.height - h1 - 20, width * .28, h1),
        sales,
      );
      c.drawRect(
        Rect.fromLTWH(x + width * .52, s.height - h2 - 20, width * .28, h2),
        purchases,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: rows[i].label.substring(rows[i].label.length > 5 ? 5 : 0),
          style: const TextStyle(fontSize: 9, color: Colors.black),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      tp.paint(c, Offset(x, s.height - 15));
    }
  }

  @override
  bool shouldRepaint(covariant _Bars old) => old.rows != rows;
}
