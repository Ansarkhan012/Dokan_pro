import 'product_image_store.dart';
import 'remote_product_image_cache.dart';

/// Resolves the local product image directories. Failure only disables
/// local images or the download cache; it must never block app startup.
Future<void> initializeProductImages() async {
  try {
    await ProductImageStore.ensureInitialized();
  } catch (_) {}
  try {
    await RemoteProductImageCache.ensureInitialized();
  } catch (_) {}
}
