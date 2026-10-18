import '../config/app_environment.dart';

/// Supabase Storage bucket holding every product photo (see migration
/// 202610180001_product_image_storage.sql).
const productImageBucket = 'product-images';

final _storageKey = RegExp(
  r'^(catalog/[0-9a-f]{64}|shops/[0-9a-f-]{36}/[0-9a-f]{64})\.jpg$',
);

/// Whether [path] is a product image key in [productImageBucket].
bool isProductImageKey(String path) => _storageKey.hasMatch(path);

/// The URL to download a synced product image from: a full http(s) URL as
/// is, a storage key under [baseUrl]'s public bucket, otherwise null.
String? productImageUrl(
  String? path, {
  String baseUrl = AppEnvironment.supabaseUrl,
}) {
  final value = path?.trim() ?? '';
  if (value.startsWith('https://') || value.startsWith('http://')) {
    return value;
  }
  if (baseUrl.isEmpty || !isProductImageKey(value)) return null;
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return '$base/storage/v1/object/public/$productImageBucket/$value';
}

/// The storage key for a shop's own photo with content hash [sha256Hex].
String shopProductImageKey(String shopId, String sha256Hex) =>
    'shops/${shopId.toLowerCase()}/$sha256Hex.jpg';
