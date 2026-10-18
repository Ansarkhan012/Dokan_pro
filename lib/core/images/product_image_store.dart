import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Device-local cache of shopkeeper-chosen product images.
///
/// Images live in app-owned storage keyed by shop product id, never in
/// SQLite and never in the synced `image_path` column, so they survive
/// restarts, display offline and cannot affect sync or billing.
///
/// The set of stored ids is indexed once when opened so thumbnail lookups
/// during POS grid rebuilds never touch the filesystem.
final class ProductImageStore {
  ProductImageStore._(this.root, this._ids);

  final Directory root;
  final Set<String> _ids;

  /// Set once at startup; null (e.g. in tests or on web) means no local
  /// images are available and thumbnails fall back to their placeholder.
  static ProductImageStore? instance;
  static Future<ProductImageStore>? _initializing;

  static Future<ProductImageStore> ensureInitialized() {
    final existing = instance;
    if (existing != null) return Future.value(existing);
    return _initializing ??= () async {
      try {
        final support = await getApplicationSupportDirectory();
        return instance = await open(
          Directory(p.join(support.path, 'product_images')),
        );
      } finally {
        _initializing = null;
      }
    }();
  }

  /// Opens a store rooted at [root], indexing the images already on disk.
  static Future<ProductImageStore> open(Directory root) async {
    final ids = <String>{};
    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File || p.extension(entity.path) != '.jpg') continue;
        final id = p.basenameWithoutExtension(entity.path);
        if (_safeId.hasMatch(id) && await entity.length() > 0) ids.add(id);
      }
    }
    return ProductImageStore._(root, ids);
  }

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  File fileFor(String productId) {
    if (!_safeId.hasMatch(productId)) {
      throw ArgumentError.value(productId, 'productId', 'unsafe identifier');
    }
    return File(p.join(root.path, '$productId.jpg'));
  }

  bool has(String productId) => _ids.contains(productId);

  /// The stored image for [productId], or null when there is none. Uses the
  /// in-memory index only; a file that later fails to decode falls back to
  /// the thumbnail placeholder.
  File? existing(String productId) =>
      has(productId) ? fileFor(productId) : null;

  /// Atomically writes already-processed JPEG bytes for [productId].
  Future<File> save(String productId, Uint8List jpegBytes) async {
    final target = fileFor(productId);
    await root.create(recursive: true);
    final temp = File('${target.path}.tmp');
    try {
      await temp.writeAsBytes(jpegBytes, flush: true);
      await temp.rename(target.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    }
    _ids.add(productId);
    _evict(target);
    return target;
  }

  Future<void> remove(String productId) async {
    if (!_safeId.hasMatch(productId)) return;
    _ids.remove(productId);
    final file = fileFor(productId);
    _evict(file);
    if (await file.exists()) await file.delete();
  }

  /// Drops decoded copies so a replaced image is not served from memory.
  /// Thumbnails decode through [ResizeImage], whose keys vary by size and
  /// cannot be enumerated, so the (cheap, rebuildable) cache is cleared.
  /// Saves only happen on product create, never during billing.
  static void _evict(File file) {
    final cache = PaintingBinding.instance.imageCache;
    cache.evict(FileImage(file), includeLive: true);
    cache.clear();
  }
}
