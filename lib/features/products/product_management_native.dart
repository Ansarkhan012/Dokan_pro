import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/ids/id_generator.dart';
import '../../core/errors/safe_error_message.dart';
import '../../core/images/product_image_store.dart';
import '../../database/app_database.dart';
import '../../sync/pull/pull_models.dart';
import '../../sync/pull/reference_pull_service.dart';
import '../../sync/pull/supabase_reference_pull_gateway.dart';
import '../pos/pos_state.dart';
import '../pos/product_thumbnail.dart';
import 'custom_product_dialog.dart';
import 'edit_product_dialog.dart';
import 'product_duplicates.dart';
import 'drift_product_management_repository.dart';
import 'product_management_models.dart';
import 'product_management_service.dart';
import 'supabase_product_management_gateway.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({
    super.key,
    required this.client,
    required this.shopId,
    required this.deviceId,
  });
  final SupabaseClient client;
  final String shopId;
  final String deviceId;

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

  Future<_ProductData> _open() async {
    final database = db ?? await AppDatabase.open();
    db = database;
    await _pull(database);
    return _load(database);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product saved to My Products.')),
      );
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
        title: const Text('Products'),
        actions: [
          IconButton(
            onPressed: refreshing ? null : refresh,
            tooltip: 'Refresh',
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'My Products'),
            Tab(text: 'Add Product'),
          ],
        ),
      ),
      body: FutureBuilder<_ProductData>(
        future: data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return const Center(
                child: Text('Could not open products. Please try again.'),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            children: [
              _MyProducts(
                products: snapshot.data!.products,
                categories: snapshot.data!.categories,
                loadProducts:
                    ({query = '', category, limit = 200, offset = 0}) =>
                        DriftProductManagementRepository(
                          db!,
                          shopId: widget.shopId,
                        ).products(
                          query: query,
                          category: category,
                          limit: limit,
                          offset: offset,
                        ),
                gateway: gateway,
                shopId: widget.shopId,
                onChanged: afterMutation,
              ),
              _AddProduct(
                service: service,
                shopId: widget.shopId,
                deviceId: widget.deviceId,
                categories: snapshot.data!.categories,
                onChanged: afterMutation,
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
    required this.gateway,
    required this.shopId,
    required this.onChanged,
  });
  final List<ManagedProduct> products;
  final List<ProductCategory> categories;
  final Future<List<ManagedProduct>> Function({
    String query,
    String? category,
    int limit,
    int offset,
  })
  loadProducts;
  final SupabaseProductManagementGateway gateway;
  final String shopId;
  final Future<void> Function() onChanged;

  @override
  State<_MyProducts> createState() => _MyProductsState();
}

class _MyProductsState extends State<_MyProducts> {
  static const pageSize = 200;
  final search = TextEditingController();
  String? category;
  late List<ManagedProduct> products = List.of(widget.products);
  bool loading = false;
  bool hasMore = true;

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
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: Icon(Icons.arrow_forward),
                    labelText: 'Search name or barcode',
                  ),
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All categories'),
                    ),
                    ...widget.categories.map(
                      (item) => DropdownMenuItem(
                        value: item.name,
                        child: Text(item.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    category = value;
                    _reload();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? const Center(child: Text('No products match this filter.'))
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
                                    loading ? 'Loading…' : 'Load more',
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
    var imageSaved = true;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => EditProductDialog(
        product: product,
        existingImage: ProductImageStore.instance?.existing(product.id),
        onSubmit: (edit) async {
          await widget.gateway.updateProduct(
            shopId: widget.shopId,
            productId: product.id,
            purchasePriceMinor: edit.purchasePriceMinor,
            salePriceMinor: edit.salePriceMinor,
            lowStockLevel: edit.lowStockLevel,
            isActive: edit.isActive,
          );
          imageSaved = await applyProductImageEdit(
            product.id,
            newImage: edit.newImage,
            remove: edit.removeImage,
          );
        },
      ),
    );
    if (saved != true) return;
    await widget.onChanged();
    if (!imageSaved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Product saved. The image could not be updated on this tablet.',
          ),
        ),
      );
    }
  }
}

class _ManagedProductCard extends StatelessWidget {
  const _ManagedProductCard({required this.product, required this.onEdit});
  final ManagedProduct product;
  final VoidCallback onEdit;
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
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${product.categoryName} • ${product.barcode ?? 'No barcode'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Sale ${formatProductMoney(product.salePriceMinor)} • '
                  'Purchase ${formatProductMoney(product.purchasePriceMinor)}',
                ),
                Text(
                  'Stock ${quantityToInput(product.stockQuantity)}${product.isLowStock ? ' • Low stock' : ''}${product.isActive ? '' : ' • Inactive'}',
                  style: TextStyle(
                    color: product.isLowStock ? Colors.orange.shade800 : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Edit',
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
    required this.existingProducts,
  });
  final ProductManagementService service;
  final String shopId;
  final String deviceId;
  final List<ProductCategory> categories;
  final Future<void> Function() onChanged;

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

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (searching) return;
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final rows = await widget.service.search(
        shopId: widget.shopId,
        query: query.text,
      );
      if (mounted) {
        setState(() {
          results = rows;
          searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          searching = false;
          error = 'Catalog search failed. Check internet and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Search Master Catalog',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: query,
              onSubmitted: (_) => search(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Product name, brand, or barcode',
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: searching ? null : search,
            child: Text(searching ? 'Searching…' : 'Search'),
          ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            error!,
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
              width: 56,
              height: 56,
            ),
            title: Text(product.name),
            subtitle: Text(
              '${product.brand.isEmpty ? product.categoryName : product.brand} • ${product.barcode}\n${product.unit}${product.packLabel == null ? '' : ' • ${product.packLabel}'}',
            ),
            isThreeLine: true,
            trailing: product.alreadyAdded
                ? OutlinedButton(
                    onPressed: () =>
                        DefaultTabController.of(context).animateTo(0),
                    child: const Text('Open / edit'),
                  )
                : FilledButton(
                    onPressed: () => _addMaster(product),
                    child: const Text('Add'),
                  ),
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _createCustom,
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Create Custom Product'),
      ),
    ],
  );

  Future<void> _addMaster(MasterCatalogItem product) async {
    final input = await showDialog<AddProductInput>(
      context: context,
      builder: (_) => _StockAndPriceDialog(title: product.name),
    );
    if (input == null) return;
    try {
      await widget.service.addMaster(
        shopId: widget.shopId,
        deviceId: widget.deviceId,
        product: product,
        input: input,
      );
      await widget.onChanged();
      if (!mounted) return;
      setState(
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
    String? productId;
    final draft = await showDialog<CustomProductDraft>(
      context: context,
      // A stray tap while dismissing the keyboard must not discard the form.
      barrierDismissible: false,
      builder: (_) => CustomProductDialog(
        categories: widget.categories,
        // Runs inside the dialog so a failure keeps the entered data open.
        onSubmit: (submitted) async {
          if (!await _confirmNotDuplicate(submitted.input)) {
            throw const CustomProductSubmitCancelled();
          }
          productId = await widget.service.createCustom(
            shopId: widget.shopId,
            deviceId: widget.deviceId,
            input: submitted.input,
          );
        },
      ),
    );
    final createdId = productId;
    if (draft == null || createdId == null) return;
    final imageSaved = await saveProductImage(createdId, draft.image);
    await widget.onChanged();
    if (!mounted) return;
    if (!imageSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Product created. The image could not be saved on this tablet.',
          ),
        ),
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

class _StockAndPriceDialog extends StatefulWidget {
  const _StockAndPriceDialog({required this.title});
  final String title;
  @override
  State<_StockAndPriceDialog> createState() => _StockAndPriceDialogState();
}

class _StockAndPriceDialogState extends State<_StockAndPriceDialog> {
  final purchase = TextEditingController();
  final sale = TextEditingController();
  final opening = TextEditingController(text: '0');
  final low = TextEditingController(text: '0');
  String? error;
  @override
  void dispose() {
    purchase.dispose();
    sale.dispose();
    opening.dispose();
    low.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: purchase,
            decoration: const InputDecoration(labelText: 'Purchase price'),
          ),
          TextField(
            controller: sale,
            decoration: const InputDecoration(labelText: 'Sale price'),
          ),
          TextField(
            controller: opening,
            decoration: const InputDecoration(labelText: 'Opening stock'),
          ),
          TextField(
            controller: low,
            decoration: const InputDecoration(labelText: 'Low-stock threshold'),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
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
          Navigator.pop(
            context,
            AddProductInput(
              purchasePriceMinor: p,
              salePriceMinor: s,
              openingQuantity: o,
              lowStockLevel: l,
            ),
          );
        },
        child: const Text('Add to My Shop'),
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
  final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(input.trim());
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
