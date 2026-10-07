import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

/// Lets the shopkeeper choose a product photo. Returns the raw bytes so the
/// temporary picker URI is never kept; null when the picker is cancelled.
abstract interface class ProductImagePicker {
  Future<Uint8List?> pick();
}

final class GalleryProductImagePicker implements ProductImagePicker {
  const GalleryProductImagePicker();

  @override
  Future<Uint8List?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Let the platform pre-shrink large camera photos before we decode.
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}
