import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/billing_activity.dart';
import '../../core/domain/enums.dart';
import '../../core/l10n/language_switcher.dart';
import '../../core/format/measure_format.dart';
import '../../core/ids/id_generator.dart';
import '../../core/ui/pos_ui.dart';
import '../../subscription/entitlement_policy.dart';
import '../../sync/pull/remote_refresh.dart';
import '../../sync/sync_health.dart';
import '../sales/domain/sale_draft.dart';
import '../sales/sales_history.dart';
import '../receipts/receipt_model.dart';
import '../receipts/receipt_view.dart';
import '../customers/customer_khata_view.dart';
import 'measured_quantity_picker.dart';
import 'pack_selector.dart';
import 'pos_catalog.dart';
import 'pos_state.dart';
import 'product_thumbnail.dart';
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';
import '../../core/l10n/localized_format.dart';
import '../../core/l10n/messages.dart';

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

  /// Sync status of this shop's outbox; never `synced` while an operation
  /// needs attention.
  Stream<SyncHealth> watchSyncHealth();
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
    this.catalogRefresh,
    this.remoteRefresh,
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

  /// Completes when a background pull that started with this screen has
  /// applied; the catalog (prices, stock, products) is then reloaded.
  final Future<void>? catalogRefresh;

  /// B-4: fetches other devices' changes on resume and when connectivity
  /// returns (guarded against overlap and repetition); null in tests and the
  /// web preview, where only the local catalog is reloaded.
  final RemoteRefresh? remoteRefresh;

  @override
  State<PosWorkspace> createState() => _PosWorkspaceState();
}

class _PosWorkspaceState extends State<PosWorkspace>
    with WidgetsBindingObserver {
  final cart = PosCart();
  final search = TextEditingController();

  /// The search field takes focus (and the soft keyboard opens) only when the
  /// cashier taps it.
  final searchFocus = FocusNode(debugLabel: 'pos-search');

  /// Holds focus on the Sale screen while the search field does not, so a
  /// hardware barcode scanner (a keyboard device) keeps working without the
  /// soft keyboard: it is not a text input, so it never shows the keyboard.
  final scanFocus = FocusNode(debugLabel: 'pos-hardware-scan');
  late PosCatalogSnapshot catalog = widget.initialCatalog;
  String? categoryId;
  int destination = 0;
  bool completing = false;
  bool paymentOpen = false;
  ({String id, String cart})? checkoutAttempt;
  late SaleHistoryRow? lastSavedSale = widget.lastSavedSale;
  late SyncHealth syncHealth = widget.initialHasPendingSync
      ? SyncHealth.pending
      : SyncHealth.synced;
  bool get hasPendingSync =>
      syncHealth == SyncHealth.pending || syncHealth == SyncHealth.syncing;
  late bool isOffline = widget.offline;
  StreamSubscription<SyncHealth>? syncStatusSubscription;
  Timer? retryTimer;

  /// Cart lines whose price changed after they were added, by product id;
  /// the old price is the one the cart first showed (B-4).
  final priceChanges = <String, PosPriceChange>{};

  /// Changes for lines still in the cart, in cart order.
  List<PosPriceChange> get visiblePriceChanges => [
    for (final line in cart.lines) ?priceChanges[line.product.id],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncStatusSubscription = widget.committer.watchSyncHealth().listen((
      health,
    ) {
      if (!mounted) return;
      setState(() {
        syncHealth = health;
        if (health == SyncHealth.synced) isOffline = false;
      });
    });
    retryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _retrySync();
      // Only while the last pull failed: waiting for connectivity to return.
      _pullThenReload(widget.remoteRefresh?.onTick);
    });
    widget.catalogRefresh?.then((_) => _reloadCatalog(), onError: (_) {});
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
      if (syncHealth != SyncHealth.needsAttention) {
        syncHealth = synced ? SyncHealth.synced : SyncHealth.pending;
      }
      if (synced) isOffline = false;
    });
    // An upload got through: if pulls were failing, connectivity is back.
    if (synced) _pullThenReload(widget.remoteRefresh?.onUploadSucceeded);
  }

  /// Runs one guarded pull and reloads the catalog when it applied. Without
  /// a [pull] (tests, web) only the local catalog is reloaded. Never throws;
  /// offline the POS keeps selling from its cached catalog.
  Future<void> _pullThenReload(Future<bool> Function()? pull) async {
    if (pull == null) return _reloadCatalog();
    final applied = await pull();
    if (!mounted) return;
    final waiting = widget.remoteRefresh?.waitingForConnectivity ?? false;
    if (isOffline != waiting && (applied || waiting)) {
      setState(() => isOffline = waiting);
    }
    if (applied) await _reloadCatalog();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retrySync();
      unawaited(_pullThenReload(widget.remoteRefresh?.onResume));
    }
  }

  List<PosProduct> get filteredProducts => catalog.products
      .where(
        (product) =>
            (categoryId == null || product.categoryId == categoryId) &&
            matchesPosSearch(product, search.text),
      )
      .toList();

  /// U3: the sale grid, with each pack family's sizes on one card.
  List<PosCatalogEntry> get catalogEntries => groupCatalog(filteredProducts);

  /// U3: the cashier picks one size; exactly one pack of it is added, on
  /// that size's own bill line.
  Future<void> _addFromFamily(PosCatalogEntry family) async {
    _releaseSearchFocus();
    final variant = await showPackSelector(
      context,
      familyName: family.name,
      variants: family.variants,
      allowNegativeStock: catalog.allowNegativeStock,
      inCart: cart.quantityOf,
    );
    if (variant == null || !mounted) return;
    setState(() => cart.add(variant));
  }

  /// A piece product adds one unit at once; a measured product (U2) asks for
  /// its quantity first and adds it to the product's single bill line.
  Future<void> addProduct(PosProduct product) async {
    _releaseSearchFocus();
    if (!product.isMeasured) {
      if (_refuseOversell(
        product,
        cart.quantityOf(product.id) + quantityScale,
      )) {
        return;
      }
      setState(() => cart.add(product));
      return;
    }
    final quantity = await showMeasuredQuantityPicker(
      context,
      product: product,
      allowNegativeStock: catalog.allowNegativeStock,
      alreadyInCart: cart.quantityOf(product.id),
    );
    if (quantity == null || !mounted) return;
    setState(() => cart.addQuantity(product, quantity));
  }

  /// Sets a measured line to an exact quantity picked again (U2).
  Future<void> _editMeasuredLine(
    PosCartLine line, [
    StateSetter? updateParent,
  ]) async {
    _releaseSearchFocus();
    final quantity = await showMeasuredQuantityPicker(
      context,
      product: line.product,
      allowNegativeStock: catalog.allowNegativeStock,
      editing: line.quantity,
    );
    if (quantity == null || !mounted) return;
    _updateCart(
      () => cart.setQuantity(line.product.id, quantity),
      updateParent,
    );
  }

  /// True (and the cashier is told why) when [requested] thousandths of
  /// [product] would sell more tracked stock than the shop has. Checkout
  /// checks the same rule again inside its transaction.
  bool _refuseOversell(PosProduct product, int requested) {
    if (catalog.allowNegativeStock ||
        !product.stockTrackingEnabled ||
        requested <= product.stockQuantity) {
      return false;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            insufficientStockMessage(
              context,
              productName: product.name,
              available: product.stockQuantity,
              unit: product.measureUnit,
            ),
          ),
        ),
      );
    return true;
  }

  /// Moves focus from the search field to the Sale screen: the soft keyboard
  /// closes and hardware-scanner input keeps arriving.
  void _releaseSearchFocus() {
    if (searchFocus.hasFocus) scanFocus.requestFocus();
  }

  /// Hardware keyboard / barcode-scanner input while the Sale screen itself
  /// holds focus (the search field is not focused): printable characters go
  /// into the search text, Backspace edits it, Enter submits it as a barcode,
  /// exactly as when the old auto-focused field received them. Everything
  /// else (Tab, arrows, shortcuts) passes through untouched.
  KeyEventResult _onScanKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (search.text.trim().isEmpty) return KeyEventResult.ignored;
      submitBarcode(search.text);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (search.text.isEmpty) return KeyEventResult.ignored;
      setState(
        () => search.text = search.text.substring(0, search.text.length - 1),
      );
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character == null ||
        character.isEmpty ||
        character.codeUnitAt(0) < 0x20 ||
        character.codeUnitAt(0) == 0x7f) {
      return KeyEventResult.ignored;
    }
    setState(() => search.text += character);
    return KeyEventResult.handled;
  }

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.posNoBarcodeMatch)));
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
    _releaseSearchFocus();
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
          activeCustomerCount: catalog.activeCustomerCount,
          priceChanges: visiblePriceChanges,
        ),
      );
    } finally {
      paymentOpen = false;
    }
    if (plan == null || !mounted) return;
    final payment = plan;
    setState(() => completing = true);
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
      // Checkout prices lines from the database. If a price, stock figure or
      // product changed since the catalog was loaded (a background pull),
      // the cart is refreshed so the next attempt shows what will be charged.
      if (error is SaleValidationException) unawaited(_reloadCatalog());
      final l10n = context.l10n;
      final message = switch (error) {
        InsufficientStockException() => insufficientStockMessage(
          context,
          productName: error.productName,
          available: error.availableQuantity,
          unit: MeasureUnit.tryParse(error.measureUnitName),
        ),
        SaleValidationException(:final message) => localizedSaleError(
          l10n,
          message,
        ),
        // The policy's refusal stands; only its wording is translated.
        SubscriptionMutationBlocked(:final message) => localizedMessage(
          l10n,
          message,
        ),
        CheckoutConflict() => l10n.saleCheckoutConflict,
        _ => l10n.saleFailed,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    // Committed locally: the checkout is complete and nothing below (sync,
    // catalog refresh) can turn it into a failure.
    checkoutAttempt = null;
    priceChanges.clear();
    if (!mounted) return;
    setState(() {
      completing = false;
      if (syncHealth != SyncHealth.needsAttention) {
        syncHealth = SyncHealth.pending;
      }
      lastSavedSale = null;
    });
    unawaited(_reloadCatalog());
    final receipt = await _committedReceipt(sale.saleId, payment);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ReceiptDialog(
        receipt: receipt,
        synced: false,
        onView: () => setState(() => destination = 2),
      ),
    );
  }

  /// The receipt of the committed sale, read back from the local database
  /// through the same path as Bills reprints. Cash received and change are
  /// not stored with the sale, so they come from this confirmation. Null if
  /// it cannot be read: the sale stays saved and is reprintable from Bills.
  Future<ReceiptModel?> _committedReceipt(
    String saleId,
    PosPaymentPlan payment,
  ) async {
    try {
      final history = widget.salesHistory;
      final row = await history.sale(saleId);
      if (row == null) return null;
      final stored = await history.receipt(await history.detail(row));
      return ReceiptModel(
        shopName: stored.shopName,
        phone: stored.phone,
        address: stored.address,
        footer: stored.footer,
        reference: stored.reference,
        dateTime: stored.dateTime,
        cashier: stored.cashier,
        customer: stored.customer,
        lines: stored.lines,
        subtotal: stored.subtotal,
        discount: stored.discount,
        total: stored.total,
        returned: stored.returned,
        status: stored.status,
        payments: stored.payments,
        received: payment.cashReceivedMinor,
        change: payment.changeDueFor(stored.total),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _reloadCatalog() async {
    try {
      final refreshed = await widget.committer.reloadCatalog();
      if (!mounted) return;
      var changed = const <PosPriceChange>[];
      setState(() {
        catalog = refreshed;
        changed = cart.refreshProducts(refreshed.products);
        for (final change in changed) {
          final first = priceChanges[change.productId];
          final oldPrice = first?.oldPriceMinor ?? change.oldPriceMinor;
          if (oldPrice == change.newPriceMinor) {
            priceChanges.remove(change.productId); // Back where it started.
          } else {
            priceChanges[change.productId] = PosPriceChange(
              productId: change.productId,
              productName: change.productName,
              oldPriceMinor: oldPrice,
              newPriceMinor: change.newPriceMinor,
            );
          }
        }
      });
      if (changed.isNotEmpty && visiblePriceChanges.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.posPricesChangedTitle)),
          );
      }
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
        SnackBar(content: Text(context.l10n.posReceiptUnavailable)),
      );
    }
  }

  @override
  void dispose() {
    BillingActivity.report(this, busy: false);
    WidgetsBinding.instance.removeObserver(this);
    retryTimer?.cancel();
    syncStatusSubscription?.cancel();
    search.dispose();
    searchFocus.dispose();
    scanFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lets the update prompt wait until the cart is empty.
    BillingActivity.report(this, busy: !cart.isEmpty);
    final l10n = context.l10n;
    final destinations = [
      (l10n.navSale, Icons.point_of_sale),
      (l10n.navProducts, Icons.inventory_2_outlined),
      (l10n.navBills, Icons.receipt_long_outlined),
      (l10n.navKhata, Icons.people_outline),
    ];
    // The soft keyboard overlays the shell instead of resizing it: the header,
    // sidebar, product grid and Current Bill keep their geometry, and the
    // bottom safe-area padding is held so nothing jumps as the keyboard opens.
    return Scaffold(
      backgroundColor: const Color(0xfff4f6f7),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        maintainBottomViewPadding: true,
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
                  title: Text(
                    localizedMessage(context.l10n, entitlement.message),
                  ),
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
                        ? Focus(
                            key: const ValueKey('pos-sale-focus'),
                            focusNode: scanFocus,
                            autofocus: true,
                            onKeyEvent: _onScanKey,
                            child: _buildPos(),
                          )
                        : destination == 1
                        ? _CashierProductLookup(catalog: catalog)
                        : destination == 2
                        ? SalesHistoryView(
                            repository: widget.salesHistory,
                            shopName: widget.shopName,
                          )
                        : CustomerKhataView(actions: widget.committer),
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
    final l10n = context.l10n;
    final time = localizedTime(l10n, sale.at);
    return Material(
      color: const Color(0xffe7f4ee),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.check_circle, color: Color(0xff176b52)),
        title: Text(
          l10n.posLastSaleSaved(
            bidiMoney(context, formatPkr(sale.total)),
            bidiId(context, time),
          ),
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _reprint(sale),
              child: Text(l10n.posViewReprint),
            ),
            TextButton(
              onPressed: () => setState(() => lastSavedSale = null),
              child: Text(l10n.posDismiss),
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
                    ? context.l10n.posOpenCurrentBill
                    : context.l10n.posCurrentBillSummary(
                        '${cart.lines.length}',
                        bidiMoney(context, formatPkr(cart.subtotalMinor)),
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _topBar() => Container(
    key: const ValueKey('pos-top-bar'),
    height: 58,
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    // On a phone held upright (under 480 px) the brand gives its room to the
    // shop name, sync status and cashier; wider screens are unchanged.
    child: LayoutBuilder(
      builder: (context, constraints) =>
          _topBarRow(compact: constraints.maxWidth < 480),
    ),
  );

  Widget _topBarRow({required bool compact}) => Row(
    children: [
      if (!compact) ...[
        const Text(
          'Dukaan Pro',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 28),
      ],
      Expanded(
        child: Text(
          widget.shopName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xff6c7680), fontSize: 15),
        ),
      ),
      // A problem the owner must see wins over Offline and never shows as
      // Synced; cashiers get no technical detail.
      Tooltip(
        message: syncHealth == SyncHealth.needsAttention
            ? context.l10n.syncStatusNeedsAttentionHint
            : '',
        child: _StatusChip(
          icon: syncHealth == SyncHealth.needsAttention
              ? Icons.sync_problem
              : isOffline
              ? Icons.cloud_off
              : syncHealth == SyncHealth.syncing
              ? Icons.cloud_sync
              : hasPendingSync
              ? Icons.cloud_queue
              : Icons.cloud_done,
          label: syncHealth == SyncHealth.needsAttention
              ? context.l10n.syncStatusNeedsAttention
              : isOffline
              ? context.l10n.syncStatusOffline
              : syncHealth == SyncHealth.syncing
              ? context.l10n.syncStatusSyncing
              : hasPendingSync
              ? context.l10n.syncStatusPending
              : context.l10n.syncStatusSynced,
          color: syncHealth == SyncHealth.needsAttention
              ? const Color(0xffb3261e)
              : isOffline
              ? Colors.orange
              : hasPendingSync
              ? Colors.blueGrey
              : const Color(0xff176b52),
        ),
      ),
      const LanguageSwitcher(),
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
          label: compact
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: Text(
                    widget.cashierName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : Text(widget.cashierName),
        ),
      ),
    ],
  );

  Widget _catalogPane() => LayoutBuilder(
    builder: (context, constraints) {
      final entries = catalogEntries;
      // In a short window the heading and today line give their height to
      // the product grid; category chips go only when space is tiny.
      final showHeading = constraints.maxHeight >= 330;
      final showChips = constraints.maxHeight >= 220;
      return Padding(
        padding: EdgeInsets.fromLTRB(18, showHeading ? 14 : 8, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeading) ...[
              Text(
                context.l10n.posNewSaleHeading,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              StreamBuilder<SalesTodaySummary>(
                stream: widget.salesHistory.watchToday(),
                builder: (context, snapshot) {
                  final value = snapshot.data;
                  return Text(
                    context.l10n.posTodaySummary(
                      bidiMoney(context, formatPkr(value?.total ?? 0)),
                      '${value?.bills ?? 0}',
                    ),
                    style: const TextStyle(
                      color: Color(0xff6c7680),
                      fontSize: 13,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            if (catalog.productsTruncated) ...[
              _TruncationNotice(
                key: const ValueKey('pos-catalog-truncated'),
                message: context.l10n.posCatalogTruncated(
                  '${catalog.products.length}',
                  '${catalog.activeProductCount}',
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              key: const ValueKey('pos-search-field'),
              controller: search,
              focusNode: searchFocus,
              inputFormatters: const [AsciiDigitsFormatter()],
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) {
                // Hand focus back to the Sale screen first: the keyboard
                // closes and the next hardware scan is still received.
                scanFocus.requestFocus();
                submitBarcode(value);
              },
              decoration: InputDecoration(
                hintText: context.l10n.posSearchHint,
                filled: true,
                fillColor: const Color(0xffffffff),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: Color(0xffdce2e6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(
                    color: Color(0xff176b52),
                    width: 2,
                  ),
                ),
                constraints: const BoxConstraints(minHeight: 48, maxHeight: 52),
              ),
            ),
            if (showChips) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(context.l10n.posCategoryAll),
                        selectedColor: const Color(0xff0d1b26),
                        labelStyle: TextStyle(
                          color: categoryId == null ? Colors.white : null,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        selected: categoryId == null,
                        onSelected: (_) {
                          _releaseSearchFocus();
                          setState(() => categoryId = null);
                        },
                      ),
                    ),
                    for (final category in catalog.categories)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(
                            bidiName(
                              context,
                              localizedCategoryName(
                                context.l10n,
                                category.id,
                                category.name,
                              ),
                            ),
                          ),
                          selectedColor: const Color(0xff0d1b26),
                          labelStyle: TextStyle(
                            color: categoryId == category.id
                                ? Colors.white
                                : null,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                          selected: categoryId == category.id,
                          onSelected: (_) {
                            _releaseSearchFocus();
                            setState(() => categoryId = category.id);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Expanded(child: Center(child: Text(context.l10n.posNoProducts)))
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
                  itemCount: entries.length,
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    final product = entry.product;
                    return product == null
                        ? PosFamilyCard(
                            entry: entry,
                            onTap: () => _addFromFamily(entry),
                          )
                        : PosProductCard(
                            product: product,
                            onTap: () => addProduct(product),
                          );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );

  void _updateCart(VoidCallback action, [StateSetter? updateParent]) {
    setState(action);
    updateParent?.call(() {});
  }

  Widget _cartPane({StateSetter? updateParent}) => Container(
    key: const ValueKey('current-bill-panel'),
    margin: const EdgeInsetsDirectional.fromSTEB(0, 18, 12, 18),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffdce2e6)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final header = Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.posCurrentBill,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              context.l10n.posItemCount('${cart.lines.length}'),
              style: const TextStyle(color: Color(0xff6c7680)),
            ),
          ],
        );
        final empty = Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(child: Text(context.l10n.posEmptyBill)),
        );
        final lines = [
          for (final line in cart.lines) _cartLine(line, updateParent),
        ];
        final totals = [
          if (visiblePriceChanges.isNotEmpty)
            PriceChangeNotice(
              key: const ValueKey('cart-price-changes'),
              changes: visiblePriceChanges,
            ),
          const Divider(),
          _totalRow(context.l10n.posSubtotal, cart.subtotalMinor),
          _totalRow(context.l10n.posDiscount, 0),
          _totalRow(context.l10n.posTotal, cart.subtotalMinor, prominent: true),
        ];
        final pay = _payButton();
        final secondary = _secondaryCartActions(updateParent);
        if (constraints.maxHeight >= 380) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: cart.isEmpty ? empty : ListView(children: lines)),
              ...totals,
              const SizedBox(height: 12),
              pay,
              const SizedBox(height: 8),
              secondary,
            ],
          );
        }
        // Short window: the bill scrolls as one list while Pay stays pinned,
        // so totals and lines never push anything off the pane.
        final scrolling = ListView(
          children: [
            header,
            if (cart.isEmpty) empty else ...lines,
            ...totals,
            const SizedBox(height: 8),
            secondary,
          ],
        );
        if (constraints.maxHeight < 150) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                if (cart.isEmpty) empty else ...lines,
                ...totals,
                const SizedBox(height: 8),
                pay,
                const SizedBox(height: 8),
                secondary,
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: scrolling),
            const SizedBox(height: 8),
            pay,
          ],
        );
      },
    ),
  );

  Widget _payButton() => FilledButton(
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
      completing
          ? context.l10n.posCompleting
          : context.l10n.posPay(
              bidiMoney(context, formatPkr(cart.subtotalMinor)),
            ),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _secondaryCartActions(StateSetter? updateParent) => Row(
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
          child: Text(context.l10n.posHoldBill),
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
          child: Text(context.l10n.commonClear),
        ),
      ),
    ],
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
                productDisplayName(
                  context,
                  line.product.name,
                  productId: line.product.id,
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              bidiMoney(context, formatPkr(line.totalMinor)),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (line.product.familyId != null && line.product.measureUnit == null)
          Text(
            '${bidiQuantity(context, localizedPackCount(context.l10n, line.quantity))} × '
            '${bidiMoney(context, formatPkr(line.product.salePriceMinor))}',
            key: ValueKey('cart-packs-${line.product.id}'),
            style: const TextStyle(color: Color(0xff6c7680)),
          ),
        if (line.product.measureUnit case final unit?)
          Row(
            children: [
              OutlinedButton(
                key: ValueKey('cart-quantity-${line.product.id}'),
                onPressed: () => _editMeasuredLine(line, updateParent),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: Text(
                  bidiQuantity(
                    context,
                    localizedLineQuantity(context.l10n, line.quantity, unit),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '× ${localizedUnitPrice(context.l10n, bidiMoney(context, formatPkr(line.product.salePriceMinor)), unit)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xff6c7680)),
                ),
              ),
              TextButton(
                onPressed: () => _updateCart(
                  () => cart.remove(line.product.id),
                  updateParent,
                ),
                child: Text(
                  context.l10n.commonRemove,
                  style: const TextStyle(color: Color(0xffd92d20)),
                ),
              ),
            ],
          )
        else
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
                child: Text(
                  bidiQuantity(
                    context,
                    localizedLineQuantity(
                      context.l10n,
                      line.quantity,
                      line.product.measureUnit,
                    ),
                  ),
                ),
              ),
              SizedBox.square(
                dimension: 44,
                child: OutlinedButton(
                  onPressed: () {
                    if (_refuseOversell(
                      line.product,
                      line.quantity + quantityScale,
                    )) {
                      return;
                    }
                    _updateCart(
                      () => cart.increment(line.product.id),
                      updateParent,
                    );
                  },
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
                onPressed: () => _updateCart(
                  () => cart.remove(line.product.id),
                  updateParent,
                ),
                child: Text(
                  context.l10n.commonRemove,
                  style: const TextStyle(color: Color(0xffd92d20)),
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
              bidiMoney(context, formatPkr(amount)),
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
    this.activeCustomerCount,
    this.priceChanges = const [],
  });
  final int totalMinor;
  final List<PosCustomer> customers;

  /// Cart prices that changed since their lines were added (B-4), shown
  /// above the payment choice so the cashier confirms the new total.
  final List<PosPriceChange> priceChanges;

  /// All active customers when [customers] was cut at [posCustomerLimit].
  final int? activeCustomerCount;

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
    late PosPaymentPlan plan;
    if (widget.totalMinor == 0) {
      // A Rs 0 sale is paid by nothing: no payment row and no amount to
      // enter, whichever payment mode is selected.
      plan = PosPaymentPlan(payments: const [], customerId: customerId);
    } else if (mode == PaymentMethod.cash) {
      final received = parseMoneyMinor(cash.text);
      plan = PosPaymentPlan(
        payments: [
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
          PosPayment(
            method: PaymentMethod.digital,
            amountMinor: widget.totalMinor,
          ),
        ],
      );
    } else if (mode == PaymentMethod.credit) {
      plan = PosPaymentPlan(
        payments: [
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
      setState(() => error = localizedSaleError(context.l10n, validation));
      return;
    }
    final customer = selectedCustomer;
    final limit = customer?.creditLimitMinor;
    if (creditAmount > 0 && limit != null) {
      if (customer!.balanceMinor + creditAmount > limit) {
        setState(() => error = context.l10n.payCreditLimitExceeded);
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
  Widget build(BuildContext context) => Theme(
    data: posFormTheme(Theme.of(context)),
    child: AlertDialog(
      title: Text(
        context.l10n.payTitle(bidiMoney(context, formatPkr(widget.totalMinor))),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.priceChanges.isNotEmpty) ...[
                PriceChangeNotice(
                  key: const ValueKey('payment-price-changes'),
                  changes: widget.priceChanges,
                ),
                const SizedBox(height: 12),
              ],
              SegmentedButton<PaymentMethod>(
                segments: [
                  ButtonSegment(
                    value: PaymentMethod.cash,
                    label: Text(context.l10n.paymentCash),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.digital,
                    label: Text(context.l10n.paymentDigital),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.credit,
                    label: Text(context.l10n.paymentUdhaar),
                  ),
                  ButtonSegment(
                    value: PaymentMethod.other,
                    label: Text(context.l10n.paymentSplit),
                  ),
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
                _moneyField(cash, context.l10n.payCashReceived)
              else if (mode == PaymentMethod.digital)
                Text(context.l10n.payDigitalNote)
              else if (mode == PaymentMethod.credit) ...[
                _customerField(),
                _creditProjection(),
              ] else ...[
                _moneyField(cash, context.l10n.payCashAmount),
                _moneyField(digital, context.l10n.payDigitalAmount),
                _moneyField(credit, context.l10n.payUdhaarAmount),
                _customerField(),
                _creditProjection(),
              ],
              if (mode == PaymentMethod.cash &&
                  parseMoneyMinor(cash.text) != null)
                Text(
                  context.l10n.payChange(
                    bidiMoney(
                      context,
                      formatPkr(
                        ((parseMoneyMinor(cash.text) ?? 0) - widget.totalMinor)
                            .clamp(0, 1 << 62),
                      ),
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: posAccent,
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(onPressed: confirm, child: Text(context.l10n.payComplete)),
      ],
    ),
  );

  Widget _moneyField(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      inputFormatters: const [AsciiDigitsFormatter()],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() => error = null),
      decoration: InputDecoration(labelText: label, prefixText: 'Rs '),
    ),
  );

  Widget _customerField() => DropdownButtonFormField<String>(
    initialValue: customerId,
    decoration: InputDecoration(
      labelText: context.l10n.payUdhaarCustomer,
      helperMaxLines: 3,
      helperText: (widget.activeCustomerCount ?? 0) > widget.customers.length
          ? context.l10n.posCustomersTruncated(
              '${widget.customers.length}',
              '${widget.activeCustomerCount}',
            )
          : null,
    ),
    items: widget.customers
        .map(
          (customer) => DropdownMenuItem(
            value: customer.id,
            child: Text(bidiName(context, customer.name)),
          ),
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
          Text(
            context.l10n.payExistingBalance(
              bidiMoney(context, formatPkr(customer.balanceMinor)),
            ),
          ),
          Text(
            context.l10n.payThisSaleUdhaar(
              bidiMoney(context, formatPkr(creditAmount)),
            ),
          ),
          Text(
            context.l10n.payNewBalance(
              bidiMoney(context, formatPkr(projected)),
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (customer.creditLimitMinor case final limit?)
            Text(
              context.l10n.payCreditLimit(bidiMoney(context, formatPkr(limit))),
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

  /// Null when the saved sale could not be read back; it is still in Bills.
  final ReceiptModel? receipt;
  final bool synced;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.check_circle, color: Color(0xff176b52)),
        const SizedBox(width: 10),
        Expanded(child: Text(context.l10n.saleCompleted)),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (receipt case final receipt?)
              ReceiptView(receipt: receipt)
            else
              Text(context.l10n.saleSavedOpenFromBills),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: synced
                  ? StatusPill(
                      context.l10n.saleSavedSynced,
                      tone: StatusTone.success,
                      icon: Icons.cloud_done_outlined,
                    )
                  : StatusPill(
                      context.l10n.saleSavedWaiting,
                      tone: StatusTone.info,
                      icon: Icons.cloud_queue,
                    ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () {
          Navigator.pop(context);
          onView();
        },
        child: Text(context.l10n.saleViewReceipt),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.saleNew),
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
                // Square image area: real photos and placeholders line up.
                ProductThumbnail(
                  imagePath: product.imagePath,
                  productId: product.id,
                  width: 64,
                  height: 64,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    productDisplayName(
                      context,
                      product.name,
                      productId: product.id,
                    ),
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
                      // Price never wraps on narrow cards; it scales down.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          localizedProductPrice(context, product),
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        localizedProductStockLine(context, product),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                const SizedBox(width: 6),
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
                    child: Text(context.l10n.posAdd),
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

/// U3: one card for a pack family: its name, how many sizes, the lowest
/// price; Add opens the pack selector.
class PosFamilyCard extends StatelessWidget {
  const PosFamilyCard({super.key, required this.entry, required this.onTap});
  final PosCatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final low = entry.variants.any((v) => v.isLowStock);
    return Material(
      key: ValueKey('family-card-${entry.variants.first.familyId}'),
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
                  ProductThumbnail(
                    imagePath: entry.variants.first.imagePath,
                    productId: entry.variants.first.id,
                    width: 64,
                    height: 64,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      productDisplayName(context, entry.name),
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
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            context.l10n.posFromPrice(
                              bidiMoney(
                                context,
                                formatPkr(entry.fromPriceMinor),
                              ),
                            ),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          low
                              ? context.l10n.posPackSizesLow(
                                  '${entry.variants.length}',
                                )
                              : context.l10n.posPackSizes(
                                  '${entry.variants.length}',
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: low
                                ? const Color(0xffb42318)
                                : const Color(0xff6c7680),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
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
                      child: Text(context.l10n.posAdd),
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
}

/// Lists cart prices that changed after their lines were added (B-4).
class PriceChangeNotice extends StatelessWidget {
  const PriceChangeNotice({super.key, required this.changes});
  final List<PosPriceChange> changes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.posPricesChangedTitle,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.onTertiaryContainer,
            ),
          ),
          for (final change in changes)
            Text(
              context.l10n.posPriceChangeLine(
                productDisplayName(context, change.productName),
                bidiMoney(context, formatPkr(change.oldPriceMinor)),
                bidiMoney(context, formatPkr(change.newPriceMinor)),
              ),
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
        ],
      ),
    );
  }
}

/// A plain warning strip: part of a list could not be loaded (B-2).
class _TruncationNotice extends StatelessWidget {
  const _TruncationNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
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
                productDisplayName(
                  context,
                  product.name,
                  productId: product.id,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                product.barcode == null
                    ? context.l10n.posNoBarcode
                    : bidiId(context, product.barcode!),
              ),
              Text(
                context.l10n.posPriceAndStock(
                  localizedProductPrice(context, product),
                  bidiQuantity(
                    context,
                    localizedLineQuantity(
                      context.l10n,
                      product.stockQuantity,
                      product.measureUnit,
                    ),
                  ),
                ),
              ),
              if (product.isLowStock)
                Text(
                  context.l10n.posLowStock,
                  style: const TextStyle(color: Colors.orange),
                ),
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
    width: 84,
    color: const Color(0xff0d1b26),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // A short window can leave very little height: tighten the spacing,
        // and scroll as a last resort rather than overflow.
        final compact = constraints.maxHeight < 420;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 16),
          child: Column(
            children: [
              if (!compact) ...[
                const Text(
                  'DP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              for (var index = 0; index < items.length; index++)
                _SidebarItem(
                  icon: items[index].$2,
                  label: items[index].$1,
                  selected: index == selected,
                  compact: compact,
                  onTap: () => onSelected(index),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected, compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xffc8d4dd);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 2 : 3),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? const Color(0xff07966d) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: compact ? 48 : 58,
                minWidth: double.infinity,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: compact ? 5 : 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: compact ? 20 : 22, color: color),
                    const SizedBox(height: 3),
                    // One line always: long labels scale down, never wrap.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(color: color),
        ),
      ],
    ),
  );
}

/// Why a product cannot be sold: not enough stock, or stock already below
/// zero from earlier sales. The name is shown as entered and the quantity
/// keeps Western digits and its unit.
String insufficientStockMessage(
  BuildContext context, {
  required String productName,
  required int available,
  MeasureUnit? unit,
}) {
  final l10n = context.l10n;
  final name = productDisplayName(context, productName);
  final quantity = bidiQuantity(
    context,
    localizedLineQuantity(l10n, available, unit),
  );
  return available < 0
      ? l10n.saleErrStockBelowZero(name, quantity)
      : l10n.saleErrNotEnoughStock(name, quantity);
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

/// `Rs 130.00/kg` for a measured product, `Rs 95.00` for a piece product.
String productPriceLabel(PosProduct product) => switch (product.measureUnit) {
  final unit? => measureUnitPriceLabel(formatPkr(product.salePriceMinor), unit),
  null => formatPkr(product.salePriceMinor),
};

/// `40 kg` / `750 g` for a measured product, a count otherwise.
String productStockLabel(PosProduct product) =>
    formatLineQuantity(product.stockQuantity, product.measureUnit);

/// [productPriceLabel] in the UI language, kept left to right in Urdu.
String localizedProductPrice(BuildContext context, PosProduct product) {
  final price = bidiMoney(context, formatPkr(product.salePriceMinor));
  return switch (product.measureUnit) {
    final unit? => localizedUnitPrice(context.l10n, price, unit),
    null => price,
  };
}

/// `Stock 40 kg`, or `Stock 2 • Low` when low, in the UI language.
String localizedProductStockLine(BuildContext context, PosProduct product) {
  final stock = bidiQuantity(
    context,
    localizedLineQuantity(
      context.l10n,
      product.stockQuantity,
      product.measureUnit,
    ),
  );
  return product.isLowStock
      ? context.l10n.posStockLow(stock)
      : context.l10n.posStock(stock);
}
