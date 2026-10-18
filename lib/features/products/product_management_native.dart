import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/domain/enums.dart';
import '../../core/ids/id_generator.dart';
import '../../core/errors/safe_error_message.dart';
import '../../core/images/product_image_store.dart';
import '../../database/app_database.dart';
import '../../database/repositories/sync_queue_repository.dart';
import '../../subscription/entitlement_policy.dart';
import '../../subscription/subscription_runtime.dart';
import '../../sync/supabase_sale_upload_gateway.dart';
import '../../sync/sync_health.dart';
import '../../sync/sync_worker.dart';
import '../inventory/inventory_management_native.dart'
    show InventoryAdjustmentDialog;
import '../inventory/inventory_models.dart';
import '../inventory/local_inventory_adjustment_service.dart';
import '../../sync/pull/pull_models.dart';
import '../../sync/pull/reference_pull_service.dart';
import '../../sync/pull/supabase_reference_pull_gateway.dart';
import '../pos/pos_state.dart';
import '../pos/product_thumbnail.dart';
import 'product_image_sync.dart';
import 'custom_product_dialog.dart';
import 'edit_product_dialog.dart';
import 'urdu_name_dialog.dart';
import 'product_duplicates.dart';
import 'drift_product_management_repository.dart';
import 'product_management_gateway.dart';
import 'product_management_models.dart';
import 'product_management_service.dart';
import 'supabase_product_management_gateway.dart';
import '../../core/l10n/digits.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';
import '../../core/l10n/localized_format.dart';
import '../../core/l10n/messages.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
    this.authorizer,
  });
  final SupabaseClient client;
  final String shopId;
  final String deviceId;

  /// Gate for stock adjustments; null means the subscription-checked
  /// production authorizer (always, in the app). Tests inject one.
  final FinancialMutationAuthorizer? authorizer;

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  AppDatabase? db;
  late final gateway = SupabaseProductManagementGateway(widget.client);
  late final service = ProductManagementService(
    gateway,
    const UuidV7Generator(),
  );
  late Future<_ProductData> data = _open();
  bool refreshing = false;
  ProductImageSync? imageSync;

  Future<_ProductData> _open() async {
    final database = db ?? await AppDatabase.open();
    db = database;
    try {
      imageSync ??= ProductImageSync(
        remote: SupabaseProductImageRemote(widget.client),
        store: await ProductImageStore.ensureInitialized(),
      );
    } catch (_) {
      // No local photo store: photos stay on the catalog image only.
    }
    unawaited(_flushImages());
    await _pull(database);
    return _load(database);
  }

  /// Retries photo uploads left from an offline save.
  Future<void> _flushImages() async {
    await imageSync?.flushPending(shopId: widget.shopId);
  }

  /// Sends a photo chosen (or removed) on this device to the cloud in the
  /// background; the local copy already shows here.
  void syncImage(String productId, {required bool removed}) {
    final sync = imageSync;
    if (sync == null) return;
    unawaited(
      removed
          ? sync.clear(shopId: widget.shopId, productId: productId)
          : sync.push(shopId: widget.shopId, productId: productId),
    );
  }

  Future<void> _pull(AppDatabase database) async {
    final pull = ReferencePullService(
      database,
      SupabaseReferencePullGateway(widget.client),
      shopId: widget.shopId,
    );
    for (final entity in const [
      PullEntity.categories,
      PullEntity.masterProducts,
      PullEntity.shopProducts,
      PullEntity.inventoryMovements,
    ]) {
      try {
        await pull.pull(entity).timeout(const Duration(seconds: 8));
      } catch (_) {
        // Cached products remain usable when refresh is unavailable.
      }
    }
  }

  Future<_ProductData> _load(AppDatabase database) async {
    final repository = DriftProductManagementRepository(
      database,
      shopId: widget.shopId,
    );
    return _ProductData(
      products: await repository.products(),
      categories: await repository.categories(),
    );
  }

  Future<void> refresh() async {
    if (refreshing || db == null) return;
    setState(() => refreshing = true);
    unawaited(_flushImages());
    await _pull(db!);
    if (!mounted) return;
    setState(() {
      refreshing = false;
      data = _load(db!);
    });
  }

  Future<void> afterMutation() async {
    await refresh();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.productsSaved)));
    }
  }

  /// Task 1's recorded stock adjustment for [product]: saved locally with
  /// its movement, audit and sync records, uploaded in the background.
  /// Returns the new stock, or null when nothing was saved.
  Future<int?> adjustStock(ManagedProduct product) async {
    final database = db;
    if (database == null) return null;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => InventoryAdjustmentDialog(
        product: InventoryProductRow(
          id: product.id,
          name: product.name,
          unit: product.unit,
          stockQuantity: product.stockQuantity,
          lowStockLevel: product.lowStockLevel,
          isActive: product.isActive,
          measured: product.sellMode == SellMode.measured,
        ),
        onSave: (type, quantity, note) =>
            LocalInventoryAdjustmentService(
              database,
              const UuidV7Generator(),
              authorizer:
                  widget.authorizer ?? productionFinancialMutationAuthorizer(),
            ).record(
              shopId: widget.shopId,
              productId: product.id,
              ownerId: widget.client.auth.currentUser!.id,
              deviceId: widget.deviceId,
              type: type,
              quantity: quantity,
              note: note,
            ),
      ),
    );
    if (saved != true) return null;
    unawaited(_uploadQueued(database));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.inventoryAdjustSaved)),
      );
    }
    final rows = await DriftProductManagementRepository(
      database,
      shopId: widget.shopId,
    ).products(limit: 100000);
    return rows.where((p) => p.id == product.id).firstOrNull?.stockQuantity;
  }

  Future<void> _uploadQueued(AppDatabase database) async {
    try {
      await SyncWorker(
        queue: SyncQueueRepository(database, shopId: widget.shopId),
        gateway: SupabaseSaleUploadGateway(widget.client),
        workerId: uniqueSyncWorkerId('owner-${widget.deviceId}'),
      ).runOnce();
    } catch (_) {
      // Offline: it stays queued and shows under Sync issues.
    }
  }

  @override
  void dispose() {
    db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.productsTitle),
        actions: [
          IconButton(
            onPressed: refreshing ? null : refresh,
            tooltip: context.l10n.commonRefresh,
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          tabs: [
            Tab(text: context.l10n.productsTabMine),
            Tab(text: context.l10n.productsTabAdd),
          ],
        ),
      ),
      body: FutureBuilder<_ProductData>(
        future: data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(child: Text(context.l10n.productsOpenFailed));
            }
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            children: [
              _MyProducts(
                products: snapshot.data!.products,
                categories: snapshot.data!.categories,
                loadProducts:
                    ({
                      query = '',
                      category,
                      limit = 200,
                      offset = 0,
                      status = ProductListStatus.all,
                    }) =>
                        DriftProductManagementRepository(
                          db!,
                          shopId: widget.shopId,
                        ).products(
                          query: query,
                          category: category,
                          limit: limit,
                          offset: offset,
                          status: status,
                        ),
                repository: () => DriftProductManagementRepository(
                  db!,
                  shopId: widget.shopId,
                ),
                gateway: gateway,
                shopId: widget.shopId,
                onChanged: afterMutation,
                onRefresh: refresh,
                adjustStock: adjustStock,
                onImageChanged: syncImage,
              ),
              _AddProduct(
                service: service,
                shopId: widget.shopId,
                deviceId: widget.deviceId,
                categories: snapshot.data!.categories,
                onChanged: afterMutation,
                onImageChanged: syncImage,
                existingProducts: () => DriftProductManagementRepository(
                  db!,
                  shopId: widget.shopId,
                ).products(limit: 100000),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _MyProducts extends StatefulWidget {
  const _MyProducts({
    required this.products,
    required this.categories,
    required this.loadProducts,
    required this.repository,
    required this.gateway,
    required this.shopId,
    required this.onChanged,
    required this.onRefresh,
    required this.adjustStock,
    required this.onImageChanged,
  });
  final List<ManagedProduct> products;
  final List<ProductCategory> categories;
  final Future<List<ManagedProduct>> Function({
    String query,
    String? category,
    int limit,
    int offset,
    ProductListStatus status,
  })
  loadProducts;
  final DriftProductManagementRepository Function() repository;
  final ProductEditGateway gateway;
  final String shopId;
  final Future<void> Function() onChanged;
  final Future<void> Function() onRefresh;
  final Future<int?> Function(ManagedProduct product) adjustStock;
  final void Function(String productId, {required bool removed})
  onImageChanged;

  @override
  State<_MyProducts> createState() => _MyProductsState();
}

class _MyProductsState extends State<_MyProducts> {
  static const pageSize = 200;
  final search = TextEditingController();
  String? category;
  ProductListStatus status = ProductListStatus.all;
  late List<ManagedProduct> products = List.of(widget.products);
  bool loading = false;
  bool hasMore = true;

  /// Product ids with an archive or restore in progress (one at a time each).
  final changing = <String>{};

  @override
  void didUpdateWidget(_MyProducts old) {
    super.didUpdateWidget(old);
    // The screen reloaded after a change: show it with the current filters.
    if (!identical(old.products, widget.products)) _reload();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  controller: search,
                  onSubmitted: (_) => _reload(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    // Mirrors itself in Urdu (matchTextDirection).
                    suffixIcon: const Icon(Icons.arrow_forward),
                    labelText: context.l10n.productsSearchLabel,
                  ),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: context.l10n.productsCategoryLabel,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.l10n.productsAllCategories),
                    ),
                    ...widget.categories.map(
                      (item) => DropdownMenuItem(
                        value: item.name,
                        child: Text(
                          categoryLabel(context, id: item.id, name: item.name),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    category = value;
                    _reload();
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<ProductListStatus>(
                  key: const ValueKey('products-status'),
                  initialValue: status,
                  decoration: InputDecoration(
                    labelText: context.l10n.productsStatusLabel,
                  ),
                  items: [
                    for (final (value, label) in [
                      (ProductListStatus.all, context.l10n.productsStatusAll),
                      (
                        ProductListStatus.active,
                        context.l10n.productsStatusActive,
                      ),
                      (
                        ProductListStatus.archived,
                        context.l10n.productsStatusArchived,
                      ),
                    ])
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (value) {
                    status = value ?? ProductListStatus.all;
                    _reload();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? Center(child: Text(context.l10n.productsNoMatch))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1000
                        ? 3
                        : constraints.maxWidth >= 650
                        ? 2
                        : 1;
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  childAspectRatio: 2.35,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: products.length,
                            itemBuilder: (_, index) => _ManagedProductCard(
                              product: products[index],
                              onEdit: () => _edit(context, products[index]),
                              onRestore:
                                  products[index].isActive ||
                                      changing.contains(products[index].id)
                                  ? null
                                  : () => _restore(products[index]),
                            ),
                          ),
                        ),
                        if (hasMore)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                              child: Center(
                                child: OutlinedButton(
                                  key: const ValueKey('products-load-more'),
                                  onPressed: loading ? null : _loadMore,
                                  child: Text(
                                    loading
                                        ? context.l10n.commonLoading
                                        : context.l10n.productsLoadMore,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _reload() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final rows = await widget.loadProducts(
        query: search.text.trim(),
        category: category,
        limit: pageSize,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        products = rows;
        hasMore = rows.length == pageSize;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (loading || !hasMore) return;
    setState(() => loading = true);
    try {
      final rows = await widget.loadProducts(
        query: search.text.trim(),
        category: category,
        limit: pageSize,
        offset: products.length,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        products.addAll(rows);
        hasMore = rows.length == pageSize;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _edit(BuildContext context, ManagedProduct product) async {
    var imageSaved = true, stockChanged = false, archived = false;
    // Every product of the shop, for the duplicate-barcode and pack-size
    // checks (the server checks barcodes too).
    final all = await widget.loadProducts(limit: 100000);
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => EditProductDialog(
        product: product,
        existingImage: ProductImageStore.instance?.existing(product.id),
        categories: widget.categories,
        barcodeOwners: {for (final other in all) ?other.barcode: other.id},
        familySizes: [
          for (final other in all)
            if (product.familyId != null &&
                other.familyId == product.familyId &&
                other.id != product.id &&
                other.packLabel != null)
              other.packLabel!,
        ],
        onSubmit: (edit) async {
          await widget.gateway.saveEdit(
            shopId: widget.shopId,
            product: product,
            edit: edit,
          );
          // Accepted by the server: show it now, even if the refresh that
          // follows cannot reach the cloud.
          try {
            await widget.repository().applyAcceptedEdit(product, edit);
          } catch (_) {
            // The next refresh brings the same values.
          }
          // Only a changed or removed image is touched; otherwise the
          // product keeps its current one.
          imageSaved = await applyProductImageEdit(
            product.id,
            newImage: edit.newImage,
            remove: edit.removeImage,
          );
          if (imageSaved && (edit.newImage != null || edit.removeImage)) {
            widget.onImageChanged(product.id, removed: edit.newImage == null);
          }
        },
        onAdjustStock: () async {
          final stock = await widget.adjustStock(product);
          if (stock != null) stockChanged = true;
          return stock;
        },
        onDelete: () async {
          archived = await confirmArchiveProduct(
            dialogContext,
            product: product,
            usage: widget.repository().usage(product.id),
            archive: () => _setActive(product, false),
          );
          return archived;
        },
      ),
    );
    if (archived) {
      await widget.onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.archiveDone(
                productDisplayName(
                  context,
                  product.name,
                  productId: product.id,
                ),
              ),
            ),
          ),
        );
      }
      return;
    }
    if (saved != true) {
      if (stockChanged) await widget.onRefresh();
      return;
    }
    if (imageSaved) {
      await widget.onChanged();
      return;
    }
    // The product was saved but its image was not: say exactly that, never
    // a plain "saved".
    await widget.onRefresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productsImageNotUpdated)),
      );
    }
  }

  /// Archives or restores on the server (owner only there), then mirrors it.
  Future<void> _setActive(ManagedProduct product, bool isActive) async {
    await widget.gateway.setActive(
      shopId: widget.shopId,
      productId: product.id,
      isActive: isActive,
    );
    try {
      await widget.repository().applyAcceptedActive(product.id, isActive);
    } catch (_) {
      // The next refresh brings the same value.
    }
  }

  Future<void> _restore(ManagedProduct product) async {
    if (!changing.add(product.id)) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final name = productDisplayName(
      context,
      product.name,
      productId: product.id,
    );
    try {
      await _setActive(product, true);
      await widget.onRefresh();
      messenger.showSnackBar(SnackBar(content: Text(l10n.restoreDone(name))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.restoreFailed)));
    } finally {
      changing.remove(product.id);
      if (mounted) setState(() {});
    }
  }
}

class _ManagedProductCard extends StatelessWidget {
  const _ManagedProductCard({
    required this.product,
    required this.onEdit,
    this.onRestore,
  });
  final ManagedProduct product;
  final VoidCallback onEdit;

  /// Set for an archived product.
  final VoidCallback? onRestore;
  @override
  Widget build(BuildContext context) => Card(
    color: product.isActive
        ? null
        : Theme.of(context).colorScheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ProductThumbnail(
            imagePath: product.imagePath,
            productId: product.id,
            width: 56,
            height: 56,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  productDisplayName(
                    context,
                    product.name,
                    productId: product.id,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${categoryLabel(context, id: product.categoryId, name: product.categoryName)} • '
                  '${product.barcode == null ? context.l10n.posNoBarcode : bidiId(context, product.barcode!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  context.l10n.productsSaleAndPurchase(
                    _price(context, product, product.salePriceMinor),
                    _price(context, product, product.purchasePriceMinor),
                  ),
                ),
                Text(
                  [
                    context.l10n.posStock(
                      bidiQuantity(
                        context,
                        localizedLineQuantity(
                          context.l10n,
                          product.stockQuantity,
                          product.measureUnit,
                        ),
                      ),
                    ),
                    if (product.isLowStock) context.l10n.posLowStock,
                    if (!product.isActive) context.l10n.productsInactive,
                  ].join(' • '),
                  style: TextStyle(
                    color: product.isLowStock ? Colors.orange.shade800 : null,
                  ),
                ),
              ],
            ),
          ),
          if (!product.isActive)
            IconButton(
              key: ValueKey('product-restore-${product.id}'),
              onPressed: onRestore,
              tooltip: context.l10n.restoreAction,
              icon: const Icon(Icons.unarchive_outlined),
            ),
          IconButton(
            key: ValueKey('product-urdu-name-${product.id}'),
            onPressed: () => showUrduNameDialog(
              context,
              productId: product.id,
              englishName: product.name,
            ),
            tooltip: context.l10n.productUrduNameAction,
            icon: const Icon(Icons.translate),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: context.l10n.commonEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    ),
  );
}

class _AddProduct extends StatefulWidget {
  const _AddProduct({
    required this.service,
    required this.shopId,
    required this.deviceId,
    required this.categories,
    required this.onChanged,
    required this.onImageChanged,
    required this.existingProducts,
  });
  final ProductManagementService service;
  final String shopId;
  final String deviceId;
  final List<ProductCategory> categories;
  final Future<void> Function() onChanged;
  final void Function(String productId, {required bool removed})
  onImageChanged;

  /// This shop's local products, for the likely-duplicate warning.
  final Future<List<ManagedProduct>> Function() existingProducts;
  @override
  State<_AddProduct> createState() => _AddProductState();
}

class _AddProductState extends State<_AddProduct> {
  final query = TextEditingController();
  List<MasterCatalogItem> results = const [];
  bool searching = false;
  String? error;

  /// Browsing (empty search) shows the catalog a page at a time; only
  /// names, a few fields and photo keys come down, photos load as shown.
  bool browsing = false, hasMore = false;

  @override
  void initState() {
    super.initState();
    // Open on the catalog itself; offline it just stays empty.
    search(quiet: true);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search({bool more = false, bool quiet = false}) async {
    if (searching) return;
    final text = query.text.trim();
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final rows = await widget.service.search(
        shopId: widget.shopId,
        query: text,
        offset: more ? results.length : 0,
      );
      if (mounted) {
        setState(() {
          results = more ? [...results, ...rows] : rows;
          browsing = text.isEmpty;
          hasMore = browsing && rows.length == masterCatalogPageSize;
          searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          searching = false;
          if (!quiet) {
            error = 'Catalog search failed. Check internet and try again.';
            // Shown through localizedMessage (re-translates on a switch).
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        context.l10n.productsSearchMasterCatalog,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: query,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: context.l10n.productsCatalogQueryLabel,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: searching ? null : search,
            child: Text(
              searching
                  ? context.l10n.commonSearching
                  : context.l10n.commonSearch,
            ),
          ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            localizedMessage(context.l10n, error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      for (final product in results)
        Card(
          child: ListTile(
            leading: ProductThumbnail(
              imagePath: product.imagePath,
              productId: product.shopProductId,
              width: 64,
              height: 64,
            ),
            title: Text(productDisplayName(context, product.name)),
            subtitle: Text(
              '${product.brand.isEmpty ? categoryLabel(context, id: product.categoryId, name: product.categoryName) : bidiName(context, product.brand)} • '
              '${bidiId(context, product.barcode)}\n'
              '${context.l10n.unitName(product.unit, product.unit)}'
              '${product.packLabel == null ? '' : ' • ${bidiName(context, product.packLabel!)}'}',
            ),
            isThreeLine: true,
            trailing: product.alreadyAdded
                ? OutlinedButton(
                    onPressed: () =>
                        DefaultTabController.of(context).animateTo(0),
                    child: Text(context.l10n.productsOpenEdit),
                  )
                : FilledButton(
                    onPressed: () => _addMaster(product),
                    child: Text(context.l10n.posAdd),
                  ),
          ),
        ),
      if (hasMore)
        Center(
          child: TextButton(
            onPressed: searching ? null : () => search(more: true),
            child: Text(context.l10n.productsCatalogShowMore),
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _createCustom,
        icon: const Icon(Icons.add_box_outlined),
        label: Text(context.l10n.productsCreateCustom),
      ),
    ],
  );

  Future<void> _addMaster(MasterCatalogItem product) async {
    final added = await showDialog<_CatalogAdd>(
      context: context,
      builder: (_) => _StockAndPriceDialog(
        title: product.name,
        imagePath: product.imagePath,
      ),
    );
    if (added == null) return;
    void markAdded() => setState(
      () => results = results
          .map(
            (row) => row.id == product.id
                ? MasterCatalogItem(
                    id: row.id,
                    name: row.name,
                    brand: row.brand,
                    barcode: row.barcode,
                    categoryId: row.categoryId,
                    categoryName: row.categoryName,
                    unit: row.unit,
                    alreadyAdded: true,
                    packLabel: row.packLabel,
                    imagePath: row.imagePath,
                  )
                : row,
          )
          .toList(),
    );
    try {
      await widget.service.addMaster(
        shopId: widget.shopId,
        deviceId: widget.deviceId,
        product: product,
        input: added.input,
        name: added.name,
      );
      await widget.onChanged();
      if (!mounted) return;
      markAdded();
    } on MasterProductRenameFailed {
      await widget.onChanged();
      if (!mounted) return;
      markAdded();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productsAddedNameNotSaved)),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = safeUserMessage(
            e,
            fallback: 'Could not save the product. Please try again.',
          ),
        );
      }
    }
  }

  /// Warns when the shop already has a product with the same normalized
  /// name or barcode. The owner may continue; a failed lookup never blocks
  /// creation.
  Future<bool> _confirmNotDuplicate(CustomProductInput input) async {
    final List<ProductDuplicate> matches;
    try {
      matches = findLikelyDuplicates(
        await widget.existingProducts(),
        name: input.name,
        barcode: input.barcode,
      );
    } catch (_) {
      return true;
    }
    if (matches.isEmpty || !mounted) return true;
    return confirmPossibleDuplicate(context, [
      for (final match in matches)
        (name: match.product.name, sameBarcode: match.sameBarcode),
    ]);
  }

  Future<void> _createCustom() async {
    var createdIds = <String>[];
    // U3: barcodes the shop already uses, checked before a family is sent
    // (the server enforces them too). A failed lookup never blocks.
    var barcodes = <String>{};
    try {
      barcodes = {
        for (final product in await widget.existingProducts())
          if (product.barcode?.trim().isNotEmpty ?? false)
            product.barcode!.trim(),
      };
    } catch (_) {}
    // A family retried after a partial failure is not re-confirmed.
    final attemptedFamilies = <String>{};
    if (!mounted) return;
    final draft = await showDialog<CustomProductDraft>(
      context: context,
      // A stray tap while dismissing the keyboard must not discard the form.
      barrierDismissible: false,
      builder: (_) => CustomProductDialog(
        categories: widget.categories,
        existingBarcodes: barcodes,
        // Runs inside the dialog so a failure keeps the entered data open.
        onSubmit: (submitted) async {
          final family = submitted.family;
          if ((family == null || attemptedFamilies.add(family.familyId)) &&
              !await _confirmNotDuplicate(submitted.input)) {
            if (family != null) attemptedFamilies.remove(family.familyId);
            throw const CustomProductSubmitCancelled();
          }
          createdIds = family == null
              ? [
                  await widget.service.createCustom(
                    shopId: widget.shopId,
                    deviceId: widget.deviceId,
                    input: submitted.input,
                  ),
                ]
              : await widget.service.createFamily(
                  shopId: widget.shopId,
                  deviceId: widget.deviceId,
                  family: family,
                  existingBarcodes: barcodes,
                );
        },
      ),
    );
    if (draft == null || createdIds.isEmpty) return;
    // The family's shared image goes to every pack size: stored on this
    // device first, then uploaded once (same content, same storage key).
    var imageSaved = true;
    for (final id in createdIds) {
      final saved = await saveProductImage(id, draft.image);
      if (saved && draft.image != null) {
        widget.onImageChanged(id, removed: false);
      }
      imageSaved = saved && imageSaved;
    }
    await widget.onChanged();
    if (!mounted) return;
    if (!imageSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.productsImageNotSaved)),
      );
    }
    DefaultTabController.of(context).animateTo(0);
  }
}

/// Stores a chosen thumbnail locally after the product exists. Returns false
/// only when an image was chosen but could not be written; never throws, so
/// image storage can never undo or block product creation.
Future<bool> applyProductImageEdit(
  String productId, {
  Uint8List? newImage,
  bool remove = false,
}) async {
  if (newImage != null) return saveProductImage(productId, newImage);
  if (!remove) return true;
  try {
    final store = await ProductImageStore.ensureInitialized();
    await store.remove(productId);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> saveProductImage(String productId, Uint8List? image) async {
  if (image == null) return true;
  try {
    final store = await ProductImageStore.ensureInitialized();
    await store.save(productId, image);
    return true;
  } catch (_) {
    return false;
  }
}

/// What the owner entered to add a catalog product.
final class _CatalogAdd {
  const _CatalogAdd(this.input, this.name);
  final AddProductInput input;
  final String name;
}

class _StockAndPriceDialog extends StatefulWidget {
  const _StockAndPriceDialog({required this.title, this.imagePath});
  final String title;
  final String? imagePath;
  @override
  State<_StockAndPriceDialog> createState() => _StockAndPriceDialogState();
}

class _StockAndPriceDialogState extends State<_StockAndPriceDialog> {
  late final name = TextEditingController(text: widget.title);
  final purchase = TextEditingController();
  final sale = TextEditingController();
  final opening = TextEditingController(text: '0');
  final low = TextEditingController(text: '0');
  String? error;
  @override
  void dispose() {
    name.dispose();
    purchase.dispose();
    sale.dispose();
    opening.dispose();
    low.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(productDisplayName(context, widget.title)),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ProductThumbnail(
                imagePath: widget.imagePath,
                width: 64,
                height: 64,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('catalog-add-name'),
                  controller: name,
                  decoration: InputDecoration(
                    labelText: context.l10n.productsNameInShop,
                  ),
                ),
              ),
            ],
          ),
          TextField(
            controller: purchase,
            inputFormatters: const [AsciiDigitsFormatter()],
            decoration: InputDecoration(
              labelText: context.l10n.fieldPurchasePrice,
            ),
          ),
          TextField(
            controller: sale,
            inputFormatters: const [AsciiDigitsFormatter()],
            decoration: InputDecoration(labelText: context.l10n.fieldSalePrice),
          ),
          TextField(
            controller: opening,
            inputFormatters: const [AsciiDigitsFormatter()],
            decoration: InputDecoration(
              labelText: context.l10n.fieldOpeningStock,
            ),
          ),
          TextField(
            controller: low,
            inputFormatters: const [AsciiDigitsFormatter()],
            decoration: InputDecoration(
              labelText: context.l10n.productsLowStockThreshold,
            ),
          ),
          if (error != null)
            Text(
              localizedMessage(context.l10n, error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.commonCancel),
      ),
      FilledButton(
        onPressed: () {
          final p = parseMoneyMinor(purchase.text),
              s = parseMoneyMinor(sale.text),
              o = parseQuantity(opening.text),
              l = parseQuantity(low.text);
          if (p == null || s == null || o == null || l == null) {
            setState(() => error = 'Enter valid non-negative values.');
            return;
          }
          if (name.text.trim().isEmpty) {
            setState(() => error = 'Product name is required');
            return;
          }
          Navigator.pop(
            context,
            _CatalogAdd(
              AddProductInput(
                purchasePriceMinor: p,
                salePriceMinor: s,
                openingQuantity: o,
                lowStockLevel: l,
              ),
              name.text,
            ),
          );
        },
        child: Text(context.l10n.productsAddToShop),
      ),
    ],
  );
}

final class _ProductData {
  const _ProductData({required this.products, required this.categories});
  final List<ManagedProduct> products;
  final List<ProductCategory> categories;
}

int? parseQuantity(String input) {
  final match = RegExp(
    r'^(\d{1,9})(?:\.(\d{1,3}))?$',
  ).firstMatch(normalizeDigits(input).trim());
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(3, '0');
  return whole * 1000 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

String quantityToInput(int value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  final fraction = absolute % 1000;
  return fraction == 0
      ? '$sign${absolute ~/ 1000}'
      : '$sign${absolute ~/ 1000}.${fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
}

String formatProductMoney(int minor) {
  final absolute = minor.abs();
  return '${minor < 0 ? '-' : ''}Rs ${absolute ~/ 100}.'
      '${(absolute % 100).toString().padLeft(2, '0')}';
}

/// A product price, `/kg` or `/L` after a measured product's (`فی کلو` in
/// Urdu), kept left to right inside Urdu.
String _price(BuildContext context, ManagedProduct product, int minor) {
  final price = bidiMoney(context, formatProductMoney(minor));
  return switch (product.measureUnit) {
    final unit? => localizedUnitPrice(context.l10n, price, unit),
    null => price,
  };
}

/// A category as shown in product screens: built-in categories translated
/// by their stable id, `Uncategorized` translated, any shop category exactly
/// as entered.
String categoryLabel(
  BuildContext context, {
  required String? id,
  required String name,
}) {
  final l10n = context.l10n;
  final label = id == null
      ? (name == 'Uncategorized' ? l10n.productsUncategorized : name)
      : localizedCategoryName(l10n, id, name);
  return bidiName(context, label);
}
