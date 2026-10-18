import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/images/product_image_store.dart';
import '../../core/images/product_image_url.dart';
import '../../core/images/remote_product_image_cache.dart';

String? localProductImagePath(String productId) =>
    ProductImageStore.instance?.existing(productId)?.path;

/// [path] is a file on this device, a storage key or an http(s) URL.
Widget buildProductImage({
  required String path,
  required double width,
  required double height,
  required Widget fallback,
}) {
  final url = productImageUrl(path);
  if (url == null) {
    if (!File(path).isAbsolute || !File(path).existsSync()) return fallback;
    return _fileImage(File(path), width, height, fallback);
  }
  final cache = RemoteProductImageCache.instance;
  if (cache == null) {
    return Image.network(
      url,
      key: const ValueKey('product-image'),
      width: width,
      height: height,
      fit: BoxFit.cover,
      cacheWidth: (width * 2).round(),
      cacheHeight: (height * 2).round(),
      errorBuilder: (_, _, _) => fallback,
    );
  }
  final cached = cache.cached(url);
  if (cached != null) return _fileImage(cached, width, height, fallback);
  return _DownloadedImage(
    key: ValueKey(url),
    url: url,
    cache: cache,
    width: width,
    height: height,
    fallback: fallback,
  );
}

Widget _fileImage(File file, double width, double height, Widget fallback) =>
    Image.file(
      file,
      key: const ValueKey('product-image'),
      width: width,
      height: height,
      fit: BoxFit.cover,
      cacheWidth: (width * 2).round(),
      cacheHeight: (height * 2).round(),
      errorBuilder: (_, _, _) => fallback,
    );

/// Shows the placeholder while a photo downloads into the disk cache, then
/// the cached file. Offline, the placeholder simply stays.
class _DownloadedImage extends StatefulWidget {
  const _DownloadedImage({
    super.key,
    required this.url,
    required this.cache,
    required this.width,
    required this.height,
    required this.fallback,
  });
  final String url;
  final RemoteProductImageCache cache;
  final double width, height;
  final Widget fallback;

  @override
  State<_DownloadedImage> createState() => _DownloadedImageState();
}

class _DownloadedImageState extends State<_DownloadedImage> {
  File? file;

  @override
  void initState() {
    super.initState();
    widget.cache.fetch(widget.url).then((downloaded) {
      if (mounted && downloaded != null) setState(() => file = downloaded);
    });
  }

  @override
  Widget build(BuildContext context) => switch (file) {
    final file? => _fileImage(file, widget.width, widget.height, widget.fallback),
    null => widget.fallback,
  };
}
