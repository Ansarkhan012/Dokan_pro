import 'package:flutter/material.dart';
import '../../core/images/product_image_url.dart';

String? localProductImagePath(String productId) => null;

Widget buildProductImage({
  required String path,
  required double width,
  required double height,
  required Widget fallback,
}) {
  final url = productImageUrl(path);
  if (url == null) return fallback;
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
