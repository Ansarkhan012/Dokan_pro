import 'product_image_store.dart';

/// Resolves the local product image directory. Failure only disables local
/// images; it must never block app startup.
Future<void> initializeProductImages() async {
  try {
    await ProductImageStore.ensureInitialized();
  } catch (_) {}
}
