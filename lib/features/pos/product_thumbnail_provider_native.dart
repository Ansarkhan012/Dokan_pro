import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/images/product_image_store.dart';

String? localProductImagePath(String productId) =>
    ProductImageStore.instance?.existing(productId)?.path;

Widget buildProductImage({
  required String path,
  required double width,
  required double height,
  required Widget fallback,
}) {
  final local = !path.startsWith('http://') && !path.startsWith('https://');
  if (local && !File(path).existsSync()) return fallback;
  final cacheWidth = (width * 2).round();
  final cacheHeight = (height * 2).round();
  return local
      ? Image.file(
          File(path),
          key: const ValueKey('product-image'),
          width: width,
          height: height,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          errorBuilder: (_, _, _) => fallback,
        )
      : Image.network(
          path,
          key: const ValueKey('product-image'),
          width: width,
          height: height,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          errorBuilder: (_, _, _) => fallback,
        );
}
