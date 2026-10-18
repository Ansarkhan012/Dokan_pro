import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/sha256.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/images/product_image_store.dart';
import '../../core/images/product_image_url.dart';

/// The server side of a product photo: the file in Storage and the short
/// key in `shop_products.image_path`.
abstract interface class ProductImageRemote {
  /// Uploads [jpeg] at [key]. A file already there is success: keys are
  /// content hashes, so it is the same photo.
  Future<void> upload(String key, Uint8List jpeg);

  /// Points the product at [key], or back to its catalog photo (if any)
  /// when null.
  Future<void> setImagePath({
    required String shopId,
    required String productId,
    required String? key,
  });
}

final class SupabaseProductImageRemote implements ProductImageRemote {
  SupabaseProductImageRemote(this.client);
  final SupabaseClient client;

  @override
  Future<void> upload(String key, Uint8List jpeg) async {
    try {
      await client.storage
          .from(productImageBucket)
          .uploadBinary(
            key,
            jpeg,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '31536000',
            ),
          );
    } on StorageException catch (e) {
      final exists =
          e.statusCode == '409' ||
          e.message.toLowerCase().contains('already exists');
      if (!exists) rethrow;
    }
  }

  @override
  Future<void> setImagePath({
    required String shopId,
    required String productId,
    required String? key,
  }) => client
      .from('shop_products')
      .update({'image_path': key})
      .eq('shop_id', shopId)
      .eq('id', productId);
}

/// Sends photos chosen on this device to the cloud so every device of the
/// shop shows them, without ever putting image bytes in a table row.
///
/// The local copy in [ProductImageStore] is written first and is what this
/// device shows, so an upload can never block or undo a product save. When
/// offline, the work is remembered in a small JSON file next to the photos
/// and [flushPending] finishes it later.
final class ProductImageSync {
  ProductImageSync({required this.remote, required this.store});

  final ProductImageRemote remote;
  final ProductImageStore store;
  Future<void> _lock = Future.value();

  File get _pendingFile => File(p.join(store.root.path, 'pending_sync.json'));

  /// Uploads [productId]'s local photo and links it. Returns false when it
  /// stays pending (offline, server error); never throws.
  Future<bool> push({required String shopId, required String productId}) =>
      _locked(() async {
        try {
          await _setPending(productId, shopId, upload: true);
        } catch (_) {
          // Still tried now; only an offline retry is lost.
        }
        return _run(productId, shopId, upload: true);
      });

  /// Unlinks [productId]'s uploaded photo (the catalog photo, if any, shows
  /// again). Returns false when it stays pending; never throws.
  Future<bool> clear({required String shopId, required String productId}) =>
      _locked(() async {
        try {
          await _setPending(productId, shopId, upload: false);
        } catch (_) {
          // Still tried now; only an offline retry is lost.
        }
        return _run(productId, shopId, upload: false);
      });

  /// Retries every remembered upload or unlink for [shopId]. Returns how
  /// many are still pending.
  Future<int> flushPending({required String shopId}) => _locked(() async {
    final pending = await _readPending();
    var left = 0;
    for (final MapEntry(key: productId, value: entry) in pending.entries) {
      if (entry['shop'] != shopId) continue;
      if (!await _run(productId, shopId, upload: entry['op'] == 'upload')) {
        left++;
      }
    }
    return left;
  });

  Future<bool> _run(
    String productId,
    String shopId, {
    required bool upload,
  }) async {
    try {
      String? key;
      if (upload) {
        final file = store.existing(productId);
        // The photo was removed meanwhile: nothing left to send.
        if (file == null) {
          await _removePending(productId);
          return true;
        }
        final bytes = await file.readAsBytes();
        key = shopProductImageKey(shopId, sha256Hex(bytes));
        await remote.upload(key, bytes);
      }
      await remote.setImagePath(
        shopId: shopId,
        productId: productId,
        key: key,
      );
      await _removePending(productId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, Map<String, dynamic>>> _readPending() async {
    try {
      if (!await _pendingFile.exists()) return {};
      final decoded = jsonDecode(await _pendingFile.readAsString());
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (value is Map<String, dynamic>) key: value,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writePending(Map<String, Map<String, dynamic>> pending) async {
    await store.root.create(recursive: true);
    final temp = File('${_pendingFile.path}.tmp');
    await temp.writeAsString(jsonEncode(pending), flush: true);
    await temp.rename(_pendingFile.path);
  }

  Future<void> _setPending(
    String productId,
    String shopId, {
    required bool upload,
  }) async {
    final pending = await _readPending();
    pending[productId] = {'shop': shopId, 'op': upload ? 'upload' : 'clear'};
    await _writePending(pending);
  }

  Future<void> _removePending(String productId) async {
    final pending = await _readPending();
    if (pending.remove(productId) != null) await _writePending(pending);
  }
}

String sha256Hex(Uint8List bytes) {
  final digest = SHA256Digest().process(bytes);
  final out = StringBuffer();
  for (final b in digest) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}
