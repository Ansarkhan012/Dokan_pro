sealed class ProductImageSource {
  const ProductImageSource();
}

final class CachedProductImage extends ProductImageSource {
  const CachedProductImage(this.localPath);
  final String localPath;
}

final class RemoteProductImage extends ProductImageSource {
  const RemoteProductImage(this.storagePath);
  final String storagePath;
}

final class MissingProductImage extends ProductImageSource {
  const MissingProductImage();
}

abstract interface class ProductImageCache {
  Future<ProductImageSource> resolve(String? remoteStoragePath);
}
