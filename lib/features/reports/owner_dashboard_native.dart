import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../database/app_database.dart';
import '../pos/pos_state.dart';
import 'drift_reporting_repository.dart';
import 'report_models.dart';

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
    appBar: AppBar(title: Text('${widget.shopName} • Dashboard')),
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
                  const Text('Could not calculate this report.'),
                  const SizedBox(height: 8),
                  Text('${s.error}', textAlign: TextAlign.center),
                  FilledButton(
                    onPressed: () => setState(() => report = load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final r = s.data!, m = r.summary;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in ReportRangePreset.values)
                  ChoiceChip(
                    label: Text(p.name),
                    selected: preset == p,
                    onSelected: (_) => select(p),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Cached device data • pending operations may not be reflected on other devices.',
            ),
            if (m.partialReturnCount > 0)
              Text(
                '${m.partialReturnCount} partially returned sale(s) are excluded. Profit is provisional until returns accounting is implemented.',
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
                  _card('Net Sales', m.sales),
                  _card('Purchases', m.purchases),
                  _card('Gross Profit', m.grossProfit),
                  _card('Expenses', m.expenses),
                  _card('Net Profit', m.netProfit),
                  _card('Customer Udhaar', m.receivables),
                  _card('Supplier Payable', m.payables),
                  _card('Bills', m.billCount, money: false),
                  _card('Low Stock', m.lowStockCount, money: false),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _section('Sales', [
              _row('Gross sales', m.grossSales),
              _row('Returns / voids', m.returns),
              _row('Net sales', m.sales),
              _row('Average bill', m.averageBill),
              _row('Cash', m.cash),
              _row('Digital', m.digital),
              _row('Udhaar created', m.credit),
            ]),
            _section('Purchases', [
              _row('Period purchases', m.purchases),
              _row('Paid', m.purchasePaid),
              _row('Credit created', m.purchaseCredit),
              _row('Transactions', m.purchaseCount, money: false),
            ]),
            Text(
              'Sales vs Purchases',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 230, child: _TrendChart(r.trend)),
            _rank('Top products by sales', r.topSalesProducts),
            _rank(
              'Top products by quantity',
              r.topQuantityProducts,
              money: false,
            ),
            _rank('Highest gross profit products', r.topProfitProducts),
            _rank('Expenses by category', r.expensesByCategory),
            _rank('Expenses by payment method', r.expensesByMethod),
            _rank('Top customer debtors', r.topDebtors),
            _rank('Top supplier payable', r.topSuppliers),
            _rank(
              'Low stock (current / threshold)',
              r.lowStock,
              money: false,
              secondary: true,
            ),
            if (m.missingCostLines > 0)
              Text(
                '${m.missingCostLines} sale lines excluded from profit because cost snapshots were invalid.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Text(
              'Cashier performance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final c in r.cashiers)
              ListTile(
                title: Text(c.name),
                subtitle: Text(
                  '${c.bills} bills • Cash ${formatPkr(c.cash)} • Digital ${formatPkr(c.digital)} • Udhaar ${formatPkr(c.credit)}',
                ),
                trailing: Text(formatPkr(c.sales)),
              ),
          ],
        );
      },
    ),
  );
  Widget _card(String l, int v, {bool money = true}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l, textAlign: TextAlign.center),
          Text(
            money ? formatPkr(v) : '$v',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
  Widget _row(String l, int v, {bool money = true}) => ListTile(
    dense: true,
    title: Text(l),
    trailing: Text(money ? formatPkr(v) : '$v'),
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
  }) => Card(
    child: ExpansionTile(
      title: Text(t),
      children: rows.isEmpty
          ? [const ListTile(title: Text('No data'))]
          : [
              for (final r in rows)
                ListTile(
                  title: Text(r.label),
                  trailing: Text(
                    '${money ? formatPkr(r.value) : r.value}${secondary ? ' / ${r.secondary}' : ''}',
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
      ? const Center(child: Text('No period activity'))
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
