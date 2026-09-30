import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../subscription/entitlement_policy.dart';
import '../sales/domain/sale_draft.dart';
import '../sales/sales_history.dart';
import '../receipts/receipt_model.dart';
import '../receipts/receipt_view.dart';
import '../customers/customer_khata_view.dart';
import 'pos_catalog.dart';
import 'pos_state.dart';
import 'product_thumbnail.dart';

abstract interface class PosSaleCommitter implements CustomerKhataActions {
  /// Commits checkout [checkoutId] in one local transaction. Completes once it
  /// has committed (then the sale is final) and throws only if it did not;
  /// never waits for the network. Replaying the id returns the same sale.
  Future<CreatedSale> complete(
    String checkoutId,
    PosCart cart,
    PosPaymentPlan payment,
  );
  Future<PosCatalogSnapshot> reloadCatalog();
  Stream<bool> watchHasPendingSync();
  Future<bool> triggerSync();
}

class PosWorkspace extends StatefulWidget {
  const PosWorkspace({
    super.key,
    required this.shopName,
    required this.cashierName,
    required this.initialCatalog,
    required this.committer,
    required this.salesHistory,
    required this.offline,
    required this.initialHasPendingSync,
    required this.onLogout,
    this.entitlement,
    this.checkoutIds = const UuidV7Generator(),
    this.lastSavedSale,
  });

  final String shopName;
  final String cashierName;
  final PosCatalogSnapshot initialCatalog;
  final PosSaleCommitter committer;
  final DriftSalesHistoryRepository salesHistory;
  final bool offline;
  final bool initialHasPendingSync;
  final Future<void> Function() onLogout;
  final EntitlementEvaluation? entitlement;

  /// Mints one checkout id per payment-confirmation attempt.
  final IdGenerator checkoutIds;

  /// A sale committed on this device shortly before the app last closed.
  final SaleHistoryRow? lastSavedSale;

  @override
  State<PosWorkspace> createState() => _PosWorkspaceState();
}

class _PosWorkspaceState extends State<PosWorkspace>
    with WidgetsBindingObserver {
  final cart = PosCart();
  final search = TextEditingController();
  late PosCatalogSnapshot catalog = widget.initialCatalog;
  String? categoryId;
  int destination = 0;
  bool completing = false;
  bool paymentOpen = false;
  ({String id, String cart})? checkoutAttempt;
  late SaleHistoryRow? lastSavedSale = widget.lastSavedSale;
  late bool hasPendingSync = widget.initialHasPendingSync;
  late bool isOffline = widget.offline;
  StreamSubscription<bool>? syncStatusSubscription;
  Timer? retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncStatusSubscription = widget.committer.watchHasPendingSync().listen((
      pending,
    ) {
      if (!mounted) return;
      setState(() {
        hasPendingSync = pending;
        if (!pending) isOffline = false;
      });
    });
    retryTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _retrySync(),
    );
  }

  Future<void> _retrySync() async {
    if (!hasPendingSync) return;
    final bool synced;
    try {
      synced = await widget.committer.triggerSync();
    } catch (_) {
      return; // Sync problems stay in the queue; they are never POS errors.
    }
    if (!mounted) return;
    setState(() {
      hasPendingSync = !synced;
      if (synced) isOffline = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retrySync();
  }

  List<PosProduct> get filteredProducts {
    final query = search.text.trim().toLowerCase();
    return catalog.products.where((product) {
      if (categoryId != null && product.categoryId != categoryId) return false;
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.barcode?.toLowerCase() == query;
    }).toList();
  }

  void addProduct(PosProduct product) => setState(() => cart.add(product));

  void submitBarcode(String value) {
    final code = value.trim();
    if (code.isEmpty) return;
    for (final product in catalog.products) {
      if (product.barcode == code) {
        addProduct(product);
        search.clear();
        return;
      }
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No product matches that barcode.')),
    );
  }

  /// The checkout id for the current cart: minted once when payment
  /// confirmation begins and reused until that cart is committed, so a double
  /// tap or a retry after a failure can never become a second sale.
  String _checkoutIdFor(PosCart cart) {
    final content = [
      for (final line in cart.lines) '${line.product.id}:${line.quantity}',
    ]..sort();
    final key = content.join(',');
    if (checkoutAttempt case final attempt? when attempt.cart == key) {
      return attempt.id;
    }
    final id = widget.checkoutIds.next();
    checkoutAttempt = (id: id, cart: key);
    return id;
  }

  Future<void> checkout() async {
    if (cart.isEmpty ||
        completing ||
        paymentOpen ||
        widget.entitlement?.permitsMutation == false) {
      return;
    }
    final checkoutId = _checkoutIdFor(cart);
    paymentOpen = true;
    PosPaymentPlan? plan;
    try {
      plan = await showDialog<PosPaymentPlan>(
        context: context,
        builder: (_) => PaymentDialog(
          totalMinor: cart.subtotalMinor,
          customers: catalog.customers,
        ),
      );
    } finally {
      paymentOpen = false;
    }
    if (plan == null || !mounted) return;
    final payment = plan;
    setState(() => completing = true);
    final receiptLines = List<PosCartLine>.from(cart.lines);
    final CreatedSale sale;
    try {
      sale = await const PosCheckoutController().complete(
        cart: cart,
        payment: payment,
        commit: () => widget.committer.complete(checkoutId, cart, payment),
      );
    } catch (error) {
      // Only reachable when the local transaction did not commit.
      if (!mounted) return;
      setState(() => completing = false);
      final message = switch (error) {
        SaleValidationException(:final message) => message,
        SubscriptionMutationBlocked(:final message) => message,
        CheckoutConflict() =>
          'This sale was already saved with different details. Nothing new was recorded.',
        _ => 'Sale could not be completed. Nothing was charged.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    // Committed locally: the checkout is complete and nothing below (sync,
    // catalog refresh) can turn it into a failure.
    checkoutAttempt = null;
    if (!mounted) return;
    setState(() {
      completing = false;
      hasPendingSync = true;
      lastSavedSale = null;
    });
    unawaited(_reloadCatalog());
    await showDialog<void>(
      context: context,
      builder: (_) => ReceiptDialog(
        receipt: ReceiptModel(
          shopName: widget.shopName,
          reference: sale.saleId,
          dateTime: DateTime.now().toUtc(),
          cashier: widget.cashierName,
          customer: catalog.customers
              .where((customer) => customer.id == payment.customerId)
              .firstOrNull
              ?.name,
          lines: [
            for (final line in receiptLines)
              ReceiptLine(
                name: line.product.name,
                quantity: line.quantity,
                unitPrice: line.product.salePriceMinor,
                total: line.totalMinor,
              ),
          ],
          subtotal: sale.grandTotalMinor,
          total: sale.grandTotalMinor,
          payments: {
            for (final row in payment.payments)
              row.method.name: row.amountMinor,
          },
          received: payment.cashReceivedMinor,
          change: payment.changeDueFor(sale.grandTotalMinor),
        ),
        synced: false,
        onView: () => setState(() => destination = 2),
      ),
    );
  }

  Future<void> _reloadCatalog() async {
    try {
      final refreshed = await widget.committer.reloadCatalog();
      if (mounted) setState(() => catalog = refreshed);
    } catch (_) {
      // Stock figures refresh on the next load; the sale is already saved.
    }
  }

  Future<void> _reprint(SaleHistoryRow sale) async {
    try {
      final history = widget.salesHistory;
      final receipt = await history.receipt(await history.detail(sale));
      if (!mounted) return;
      await showPrintableReceipt(context, receipt);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The receipt could not be opened. Find it in Bills.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    retryTimer?.cancel();
    syncStatusSubscription?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const destinations = [
      ('Sale', Icons.point_of_sale),
      ('Products', Icons.inventory_2_outlined),
      ('Bills', Icons.receipt_long_outlined),
      ('Khata', Icons.people_outline),
      ('Inventory', Icons.warehouse_outlined),
    ];
    return Scaffold(
      backgroundColor: const Color(0xfff4f6f7),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            if (widget.entitlement case final entitlement?
                when entitlement.decision != MutationDecision.allow)
              Material(
                color: entitlement.permitsMutation
                    ? const Color(0xfffff3cd)
                    : const Color(0xffffe0e0),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    entitlement.permitsMutation
                        ? Icons.warning_amber
                        : Icons.lock_outline,
                  ),
                  title: Text(entitlement.message),
                ),
              ),
            if (lastSavedSale case final last?) _lastSavedSaleBanner(last),
            Expanded(
              child: Row(
                children: [
                  _PosSidebar(
                    items: destinations,
                    selected: destination,
                    onSelected: (value) => setState(() => destination = value),
                  ),
                  Expanded(
                    child: destination == 0
                        ? _buildPos()
                        : destination == 1
                        ? _CashierProductLookup(catalog: catalog)
                        : destination == 2
                        ? SalesHistoryView(
                            repository: widget.salesHistory,
                            shopName: widget.shopName,
                          )
                        : destination == 3
                        ? CustomerKhataView(actions: widget.committer)
                        : _Placeholder(title: destinations[destination].$1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lastSavedSaleBanner(SaleHistoryRow sale) {
    final at = sale.at.toLocal();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Material(
      color: const Color(0xffe7f4ee),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.check_circle, color: Color(0xff176b52)),
        title: Text(
          'Last sale saved on this device: ${formatPkr(sale.total)} at $time',
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _reprint(sale),
              child: const Text('View / Reprint'),
            ),
            TextButton(
              onPressed: () => setState(() => lastSavedSale = null),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPos() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final cartWidth = (constraints.maxWidth * .34).clamp(310.0, 430.0);
      final catalogPane = _catalogPane();
      final cartPane = SizedBox(
        width: wide ? cartWidth : null,
        height: wide ? null : constraints.maxHeight,
        child: _cartPane(),
      );
      if (wide) {
        return Row(
          children: [
            Expanded(child: catalogPane),
            cartPane,
          ],
        );
      }
      return Stack(
        children: [
          catalogPane,
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: FilledButton(
              key: const ValueKey('open-cart-button'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: const Color(0xff07966d),
                foregroundColor: Colors.white,
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * .82,
                    child: StatefulBuilder(
                      builder: (context, updateSheet) =>
                          _cartPane(updateParent: updateSheet),
                    ),
                  ),
                ),
              ),
              child: Text(
                cart.isEmpty
                    ? 'Open Current Bill'
                    : 'Current Bill • ${cart.lines.length} • ${formatPkr(cart.subtotalMinor)}',
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _topBar() => Container(
    height: 58,
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    child: Row(
      children: [
        const Text(
          'Dukaan Pro',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Text(
            widget.shopName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xff6c7680), fontSize: 15),
          ),
        ),
        _StatusChip(
          icon: isOffline
              ? Icons.cloud_off
              : hasPendingSync
              ? Icons.cloud_queue
              : Icons.cloud_done,
          label: isOffline
              ? 'Offline'
              : hasPendingSync
              ? 'Pending sync'
              : 'Synced',
          color: isOffline
              ? Colors.orange
              : hasPendingSync
              ? Colors.blueGrey
              : const Color(0xff176b52),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: widget.onLogout,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.person_outline, size: 18),
            label: Text(widget.cashierName),
          ),
        ),
      ],
    ),
  );

  Widget _catalogPane() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'New Sale',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        StreamBuilder<SalesTodaySummary>(
          stream: widget.salesHistory.watchToday(),
          builder: (context, snapshot) {
            final value = snapshot.data;
            return Text(
              'Today: ${formatPkr(value?.total ?? 0)}  •  ${value?.bills ?? 0} bills',
              style: const TextStyle(color: Color(0xff6c7680), fontSize: 13),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: submitBarcode,
          decoration: InputDecoration(
            hintText: 'Search product or scan barcode',
            filled: true,
            fillColor: const Color(0xffffffff),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: const BorderSide(color: Color(0xffdce2e6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: const BorderSide(color: Color(0xff176b52), width: 2),
            ),
            constraints: const BoxConstraints(minHeight: 48, maxHeight: 52),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selectedColor: const Color(0xff0d1b26),
                  labelStyle: TextStyle(
                    color: categoryId == null ? Colors.white : null,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  selected: categoryId == null,
                  onSelected: (_) => setState(() => categoryId = null),
                ),
              ),
              for (final category in catalog.categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category.name),
                    selectedColor: const Color(0xff0d1b26),
                    labelStyle: TextStyle(
                      color: categoryId == category.id ? Colors.white : null,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    selected: categoryId == category.id,
                    onSelected: (_) => setState(() => categoryId = category.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (filteredProducts.isEmpty)
          const Expanded(child: Center(child: Text('No local products found.')))
        else
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 270,
                mainAxisExtent: 150,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: filteredProducts.length,
              itemBuilder: (_, index) => PosProductCard(
                product: filteredProducts[index],
                onTap: () => addProduct(filteredProducts[index]),
              ),
            ),
          ),
      ],
    ),
  );

  void _updateCart(VoidCallback action, [StateSetter? updateParent]) {
    setState(action);
    updateParent?.call(() {});
  }

  Widget _cartPane({StateSetter? updateParent}) => Container(
    margin: const EdgeInsets.fromLTRB(0, 18, 12, 18),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffdce2e6)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Current Bill',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${cart.lines.length} items',
              style: const TextStyle(color: Color(0xff6c7680)),
            ),
          ],
        ),
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Tap a product to begin a sale.'))
              : ListView(
                  children: [
                    for (final line in cart.lines)
                      _cartLine(line, updateParent),
                  ],
                ),
        ),
        const Divider(),
        _totalRow('Subtotal', cart.subtotalMinor),
        _totalRow('Discount', 0),
        _totalRow('Total', cart.subtotalMinor, prominent: true),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('pay-button'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            backgroundColor: const Color(0xff07966d),
            foregroundColor: Colors.white,
          ),
          onPressed:
              cart.isEmpty ||
                  completing ||
                  widget.entitlement?.permitsMutation == false
              ? null
              : checkout,
          child: Text(
            completing ? 'Completing…' : 'Pay ${formatPkr(cart.subtotalMinor)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: const Text('Hold Bill'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: cart.isEmpty
                    ? null
                    : () => _updateCart(cart.clear, updateParent),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: const Text('Clear'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _cartLine(PosCartLine line, [StateSetter? updateParent]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                line.product.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              formatPkr(line.totalMinor),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox.square(
              dimension: 44,
              child: OutlinedButton(
                onPressed: () => _updateCart(
                  () => cart.decrement(line.product.id),
                  updateParent,
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: const Icon(Icons.remove),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('${line.quantity ~/ quantityScale}'),
            ),
            SizedBox.square(
              dimension: 44,
              child: OutlinedButton(
                onPressed: () => _updateCart(
                  () => cart.increment(line.product.id),
                  updateParent,
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: const Icon(Icons.add),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () =>
                  _updateCart(() => cart.remove(line.product.id), updateParent),
              child: const Text(
                'Remove',
                style: TextStyle(color: Color(0xffd92d20)),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _totalRow(String label, int amount, {bool prominent = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: prominent
                    ? Theme.of(context).textTheme.titleMedium
                    : null,
              ),
            ),
            Text(
              formatPkr(amount),
              style: prominent
                  ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xff176b52),
                    )
                  : null,
            ),
          ],
        ),
      );
}

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({
    super.key,
    required this.totalMinor,
    required this.customers,
  });
  final int totalMinor;
  final List<PosCustomer> customers;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  PaymentMethod mode = PaymentMethod.cash;
  final cash = TextEditingController();
  final digital = TextEditingController();
  final credit = TextEditingController();
  String? customerId;
  String? error;
  bool confirmed = false;
  PosCustomer? get selectedCustomer => customerId == null
      ? null
      : widget.customers.where((c) => c.id == customerId).firstOrNull;
  int get creditAmount => mode == PaymentMethod.credit
      ? widget.totalMinor
      : mode == PaymentMethod.other
      ? (parseMoneyMinor(credit.text) ?? 0)
      : 0;

  @override
  void initState() {
    super.initState();
    cash.text = minorToInput(widget.totalMinor);
  }

  void confirm() {
    // A second tap while the dialog is closing must not confirm again.
    if (confirmed) return;
    // A Rs 0 sale is paid by nothing: it carries no payment row at all.
    final due = widget.totalMinor > 0;
    late PosPaymentPlan plan;
    if (mode == PaymentMethod.cash) {
      final received = parseMoneyMinor(cash.text);
      plan = PosPaymentPlan(
        payments: [
          if (due)
            PosPayment(
              method: PaymentMethod.cash,
              amountMinor: widget.totalMinor,
            ),
        ],
        cashReceivedMinor: received,
      );
    } else if (mode == PaymentMethod.digital) {
      plan = PosPaymentPlan(
        payments: [
          if (due)
            PosPayment(
              method: PaymentMethod.digital,
              amountMinor: widget.totalMinor,
            ),
        ],
      );
    } else if (mode == PaymentMethod.credit) {
      plan = PosPaymentPlan(
        payments: [
          if (due)
            PosPayment(
              method: PaymentMethod.credit,
              amountMinor: widget.totalMinor,
            ),
        ],
        customerId: customerId,
      );
    } else {
      plan = PosPaymentPlan(
        payments: [
          PosPayment(
            method: PaymentMethod.cash,
            amountMinor: parseMoneyMinor(cash.text) ?? -1,
          ),
          PosPayment(
            method: PaymentMethod.digital,
            amountMinor: parseMoneyMinor(digital.text) ?? -1,
          ),
          PosPayment(
            method: PaymentMethod.credit,
            amountMinor: parseMoneyMinor(credit.text) ?? -1,
          ),
        ].where((row) => row.amountMinor != 0).toList(),
        customerId: customerId,
      );
    }
    final validation = plan.validate(widget.totalMinor);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    final customer = selectedCustomer;
    final limit = customer?.creditLimitMinor;
    if (creditAmount > 0 && limit != null) {
      if (customer!.balanceMinor + creditAmount > limit) {
        setState(
          () => error =
              'Credit limit exceeded. Ask the owner to increase the limit.',
        );
        return;
      }
    }
    confirmed = true;
    Navigator.pop(context, plan);
  }

  @override
  void dispose() {
    cash.dispose();
    digital.dispose();
    credit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Payment • ${formatPkr(widget.totalMinor)}'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<PaymentMethod>(
              segments: const [
                ButtonSegment(value: PaymentMethod.cash, label: Text('Cash')),
                ButtonSegment(
                  value: PaymentMethod.digital,
                  label: Text('Digital'),
                ),
                ButtonSegment(
                  value: PaymentMethod.credit,
                  label: Text('Udhaar'),
                ),
                ButtonSegment(value: PaymentMethod.other, label: Text('Split')),
              ],
              selected: {mode},
              onSelectionChanged: (value) => setState(() {
                mode = value.single;
                error = null;
                if (mode == PaymentMethod.cash) {
                  cash.text = minorToInput(widget.totalMinor);
                }
              }),
            ),
            const SizedBox(height: 18),
            if (mode == PaymentMethod.cash)
              _moneyField(cash, 'Cash received')
            else if (mode == PaymentMethod.digital)
              const Text('Digital payment will be recorded without a gateway.')
            else if (mode == PaymentMethod.credit) ...[
              _customerField(),
              _creditProjection(),
            ] else ...[
              _moneyField(cash, 'Cash amount'),
              _moneyField(digital, 'Digital amount'),
              _moneyField(credit, 'Udhaar amount'),
              _customerField(),
              _creditProjection(),
            ],
            if (mode == PaymentMethod.cash &&
                parseMoneyMinor(cash.text) != null)
              Text(
                'Change: ${formatPkr(((parseMoneyMinor(cash.text) ?? 0) - widget.totalMinor).clamp(0, 1 << 62))}',
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: confirm, child: const Text('Complete Sale')),
    ],
  );

  Widget _moneyField(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() => error = null),
      decoration: InputDecoration(labelText: label, prefixText: 'Rs '),
    ),
  );

  Widget _customerField() => DropdownButtonFormField<String>(
    initialValue: customerId,
    decoration: const InputDecoration(labelText: 'Udhaar customer'),
    items: widget.customers
        .map(
          (customer) =>
              DropdownMenuItem(value: customer.id, child: Text(customer.name)),
        )
        .toList(),
    onChanged: (value) => setState(() => customerId = value),
  );

  Widget _creditProjection() {
    final customer = selectedCustomer;
    if (customer == null) return const SizedBox.shrink();
    final projected = customer.balanceMinor + creditAmount;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Existing balance: ${formatPkr(customer.balanceMinor)}'),
          Text('This sale on Udhaar: ${formatPkr(creditAmount)}'),
          Text(
            'New balance: ${formatPkr(projected)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (customer.creditLimitMinor case final limit?)
            Text(
              'Credit limit: ${formatPkr(limit)}',
              style: TextStyle(color: projected > limit ? Colors.red : null),
            ),
        ],
      ),
    );
  }
}

class ReceiptDialog extends StatelessWidget {
  const ReceiptDialog({
    super.key,
    required this.receipt,
    required this.synced,
    required this.onView,
  });
  final ReceiptModel receipt;
  final bool synced;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.check_circle, color: Color(0xff176b52)),
        SizedBox(width: 10),
        Text('Sale completed'),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReceiptView(receipt: receipt),
          const SizedBox(height: 8),
          Text(
            synced ? 'Saved locally • Synced' : 'Saved locally • Pending sync',
          ),
        ],
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () {
          Navigator.pop(context);
          onView();
        },
        child: const Text('View receipt'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('New sale'),
      ),
    ],
  );
}

class PosProductCard extends StatelessWidget {
  const PosProductCard({super.key, required this.product, required this.onTap});
  final PosProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: Color(0xffdce2e6)),
      borderRadius: BorderRadius.circular(9),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProductThumbnail(imagePath: product.imagePath),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatPkr(product.salePriceMinor),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Stock ${formatQuantity(product.stockQuantity)}${product.isLowStock ? ' • Low' : ''}',
                        maxLines: 1,
                        style: TextStyle(
                          color: product.isLowStock
                              ? const Color(0xffb42318)
                              : const Color(0xff6c7680),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff07966d),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CashierProductLookup extends StatelessWidget {
  const _CashierProductLookup({required this.catalog});
  final PosCatalogSnapshot catalog;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(20),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 280,
      mainAxisExtent: 150,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: catalog.products.length,
    itemBuilder: (context, index) {
      final product = catalog.products[index];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(product.barcode ?? 'No barcode'),
              Text(
                '${formatPkr(product.salePriceMinor)} • '
                'Stock ${formatQuantity(product.stockQuantity)}',
              ),
              if (product.isLowStock)
                const Text('Low stock', style: TextStyle(color: Colors.orange)),
            ],
          ),
        ),
      );
    },
  );
}

class _PosSidebar extends StatelessWidget {
  const _PosSidebar({
    required this.items,
    required this.selected,
    required this.onSelected,
  });
  final List<(String, IconData)> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('cashier-sidebar'),
    width: 76,
    color: const Color(0xff0d1b26),
    child: Column(
      children: [
        const SizedBox(height: 18),
        const Text(
          'DP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 24),
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(index),
              child: Container(
                constraints: const BoxConstraints(minHeight: 54),
                decoration: BoxDecoration(
                  color: index == selected ? const Color(0xff07966d) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                child: Text(
                  items[index].$1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: index == selected
                        ? Colors.white
                        : const Color(0xffc8d4dd),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.construction, size: 52, color: Color(0xff176b52)),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const Text('Coming in the next Dukaan Pro phase.'),
      ],
    ),
  );
}

String formatPkr(int minor) {
  final absolute = minor.abs();
  final rupees = absolute ~/ 100;
  final paisa = absolute % 100;
  return '${minor < 0 ? '-' : ''}Rs $rupees.${paisa.toString().padLeft(2, '0')}';
}

String formatQuantity(int quantity) {
  if (quantity % quantityScale == 0) return '${quantity ~/ quantityScale}';
  final sign = quantity < 0 ? '-' : '';
  final absolute = quantity.abs();
  return '$sign${absolute ~/ quantityScale}.${(absolute % quantityScale).toString().padLeft(3, '0')}';
}
