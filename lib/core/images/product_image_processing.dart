import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest edge of a stored POS thumbnail. Large enough for the product
/// image card, small enough that a grocery catalogue stays a few MB.
const int productImageMaxSide = 512;
const int productImageJpegQuality = 80;

/// Inputs above this size are rejected before decoding so a mistaken pick
/// (e.g. a huge scan) cannot exhaust tablet memory.
const int productImageMaxInputBytes = 25 * 1024 * 1024;

/// Pixel-count ceiling checked from the header before full decode; a small
/// compressed file can still expand to gigabytes of RGBA.
const int productImageMaxInputPixels = 40 * 1000 * 1000;

final class ProductImageException implements Exception {
  const ProductImageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Decodes a JPG/PNG/WebP, applies EXIF orientation, flattens transparency
/// onto white, downsizes to [productImageMaxSide] and re-encodes as JPEG.
Uint8List prepareProductThumbnail(Uint8List source) {
  if (source.isEmpty) {
    throw const ProductImageException('The selected file is empty.');
  }
  if (source.length > productImageMaxInputBytes) {
    throw const ProductImageException('The selected image is too large.');
  }
  final decoded = _decode(source);
  if (decoded == null) {
    throw const ProductImageException(
      'Choose a JPG, PNG or WebP product image.',
    );
  }
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > productImageMaxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: productImageMaxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: productImageMaxSide,
            interpolation: img.Interpolation.average,
          );
  }
  if (image.hasAlpha) {
    final background = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 3,
    )..clear(img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(background, image);
  }
  return img.encodeJpg(image, quality: productImageJpegQuality);
}

/// Runs [prepareProductThumbnail] off the UI isolate.
Future<Uint8List> prepareProductThumbnailInBackground(Uint8List source) =>
    compute(prepareProductThumbnail, source);

img.Image? _decode(Uint8List bytes) {
  final decoder = img.JpegDecoder().isValidFile(bytes)
      ? img.JpegDecoder()
      : img.PngDecoder().isValidFile(bytes)
      ? img.PngDecoder()
      : img.WebPDecoder().isValidFile(bytes)
      ? img.WebPDecoder()
      : null;
  if (decoder == null) return null;
  final img.DecodeInfo? info;
  try {
    info = decoder.startDecode(bytes);
  } catch (_) {
    return null;
  }
  if (info == null || info.width <= 0 || info.height <= 0) return null;
  if (info.width * info.height > productImageMaxInputPixels) {
    throw const ProductImageException('The selected image is too large.');
  }
  try {
    // First frame only: animated WebP/PNG must not decode every frame.
    return decoder.decode(bytes, frame: 0);
  } catch (_) {
    return null;
  }
}
