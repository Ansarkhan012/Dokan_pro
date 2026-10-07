import 'package:flutter/material.dart';

String? localProductImagePath(String productId) => null;

Widget buildProductImage({
  required String path,
  required double width,
  required double height,
  required Widget fallback,
}) => Image.network(
  path,
  key: const ValueKey('product-image'),
  width: width,
  height: height,
  fit: BoxFit.cover,
  cacheWidth: (width * 2).round(),
  cacheHeight: (height * 2).round(),
  errorBuilder: (_, _, _) => fallback,
);
