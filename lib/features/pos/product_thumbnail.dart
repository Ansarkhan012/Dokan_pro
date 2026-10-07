import 'package:flutter/material.dart';
import 'product_thumbnail_provider.dart'
    if (dart.library.io) 'product_thumbnail_provider_native.dart';

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    this.imagePath,
    this.productId,
    this.width = 68,
    this.height = 56,
  });

  final String? imagePath;

  /// Shop product id used to find a shopkeeper-chosen local image, which
  /// takes precedence over [imagePath].
  final String? productId;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      key: const ValueKey('product-image-placeholder'),
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xffe8f1ed),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.inventory_2_outlined, color: Color(0xff7c9189)),
    );
    final local = productId == null ? null : localProductImagePath(productId!);
    final path = local ?? imagePath?.trim();
    if (path == null || path.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: buildProductImage(
        path: path,
        width: width,
        height: height,
        fallback: placeholder,
      ),
    );
  }
}
