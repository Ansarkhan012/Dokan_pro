import 'dart:io';
import 'dart:typed_data';

import 'package:dukaan_pro/core/images/product_image_store.dart';
import 'package:dukaan_pro/core/images/product_image_url.dart';
import 'package:dukaan_pro/core/images/remote_product_image_cache.dart';
import 'package:dukaan_pro/features/products/product_image_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _shop = '0192aaaa-bbbb-7ccc-8ddd-eeeeffff0000';
final _hash = 'a' * 64;

Uint8List _jpeg(int size) =>
    Uint8List(size)
      ..[0] = 0xff
      ..[1] = 0xd8
      ..[2] = 0xff;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('dukaan-img-sync-'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('productImageUrl', () {
    const base = 'https://x.supabase.co';
    test('resolves storage keys to the public bucket', () {
      expect(
        productImageUrl('catalog/$_hash.jpg', baseUrl: base),
        '$base/storage/v1/object/public/product-images/catalog/$_hash.jpg',
      );
      expect(
        productImageUrl(shopProductImageKey(_shop, _hash), baseUrl: '$base/'),
        '$base/storage/v1/object/public/product-images/shops/$_shop/$_hash.jpg',
      );
    });

    test('keeps URLs and rejects anything else', () {
      expect(
        productImageUrl('https://cdn.example/a.jpg', baseUrl: base),
        'https://cdn.example/a.jpg',
      );
      for (final bad in [
        null,
        '',
        'missing/local/file.png',
        'catalog/../secret.jpg',
        'catalog/abc.jpg',
        'shops/$_shop/$_hash.png',
      ]) {
        expect(productImageUrl(bad, baseUrl: base), equals(null), reason: bad);
      }
      expect(productImageUrl('catalog/$_hash.jpg', baseUrl: ''), equals(null));
    });
  });

  group('RemoteProductImageCache', () {
    test('downloads once, then serves from disk across restarts', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response.bytes(_jpeg(100), 200);
      });
      final cache = await RemoteProductImageCache.open(temp, client: client);
      const url = 'https://x/a.jpg';
      expect(cache.cached(url), equals(null));
      final results = await Future.wait([cache.fetch(url), cache.fetch(url)]);
      expect(results.every((f) => f != null && f.existsSync()), isTrue);
      expect(calls, 1);
      expect(cache.cached(url), isNotNull);

      final reopened = await RemoteProductImageCache.open(temp, client: client);
      expect(reopened.cached(url), isNotNull);
      expect(reopened.totalBytes, 100);
    });

    test('never caches errors, non-images or oversized bodies', () async {
      final client = MockClient((request) async {
        return switch (request.url.path) {
          '/missing' => http.Response('not found', 404),
          '/html' => http.Response('<html>', 200),
          '/huge' => http.Response.bytes(
            _jpeg(RemoteProductImageCache.maxImageBytes + 1),
            200,
          ),
          _ => throw const SocketException('offline'),
        };
      });
      final cache = await RemoteProductImageCache.open(temp, client: client);
      for (final path in ['/missing', '/html', '/huge', '/offline']) {
        expect(await cache.fetch('https://x$path'), equals(null), reason: path);
      }
      expect(cache.totalBytes, 0);
    });

    test('evicts the oldest photos above the size cap', () async {
      final client = MockClient(
        (request) async => http.Response.bytes(_jpeg(400), 200),
      );
      final cache = await RemoteProductImageCache.open(
        temp,
        client: client,
        maxBytes: 1000,
      );
      for (final name in ['a', 'b', 'c']) {
        await cache.fetch('https://x/$name');
      }
      expect(cache.cached('https://x/a'), equals(null));
      expect(cache.cached('https://x/b'), isNotNull);
      expect(cache.cached('https://x/c'), isNotNull);
      expect(cache.totalBytes, 800);
    });
  });

  group('ProductImageSync', () {
    late ProductImageStore store;
    late _Remote remote;
    late ProductImageSync sync;
    setUp(() async {
      store = await ProductImageStore.open(temp);
      remote = _Remote();
      sync = ProductImageSync(remote: remote, store: store);
    });

    test('uploads by content hash and links the product', () async {
      final bytes = _jpeg(50);
      await store.save('p1', bytes);
      await store.save('p2', bytes);
      expect(await sync.push(shopId: _shop, productId: 'p1'), isTrue);
      expect(await sync.push(shopId: _shop, productId: 'p2'), isTrue);
      final key = shopProductImageKey(_shop, sha256Hex(bytes));
      expect(isProductImageKey(key), isTrue);
      expect(remote.uploads, {key});
      expect(remote.paths, {'p1': key, 'p2': key});
    });

    test('remembers offline work and finishes it later', () async {
      await store.save('p1', _jpeg(50));
      await store.save('p2', _jpeg(60));
      remote.offline = true;
      expect(await sync.push(shopId: _shop, productId: 'p1'), isFalse);
      expect(await sync.clear(shopId: _shop, productId: 'p2'), isFalse);
      expect(await sync.flushPending(shopId: _shop), 2);

      remote.offline = false;
      // Another shop's pending work is left alone.
      expect(await sync.flushPending(shopId: 'other'), 0);
      expect(await sync.flushPending(shopId: _shop), 0);
      expect(remote.paths['p1'], isNotNull);
      expect(remote.paths.containsKey('p2'), isTrue);
      expect(remote.paths['p2'], equals(null));
      expect(await sync.flushPending(shopId: _shop), 0);
    });

    test('a photo removed before upload is dropped', () async {
      await store.save('p1', _jpeg(50));
      remote.offline = true;
      await sync.push(shopId: _shop, productId: 'p1');
      await store.remove('p1');
      remote.offline = false;
      expect(await sync.flushPending(shopId: _shop), 0);
      expect(remote.uploads, isEmpty);
    });
  });
}

final class _Remote implements ProductImageRemote {
  bool offline = false;
  final uploads = <String>{};
  final paths = <String, String?>{};

  @override
  Future<void> upload(String key, Uint8List jpeg) async {
    if (offline) throw const SocketException('offline');
    uploads.add(key);
  }

  @override
  Future<void> setImagePath({
    required String shopId,
    required String productId,
    required String? key,
  }) async {
    if (offline) throw const SocketException('offline');
    paths[productId] = key;
  }
}
