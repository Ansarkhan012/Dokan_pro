import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Device disk cache of synced product images (catalog photos and photos
/// uploaded from another device).
///
/// A photo is downloaded the first time a thumbnail shows it and then read
/// from disk, offline included. Storage keys are content hashes, so a cached
/// file never goes stale. The cache is capped at [maxBytes]; the oldest
/// downloads are deleted first. Nothing here touches SQLite or sync.
final class RemoteProductImageCache {
  RemoteProductImageCache._(
    this.root,
    this._files,
    this._client, {
    required this.maxBytes,
    required this.maxConcurrent,
  }) : _bytes = _files.values.fold(0, (sum, size) => sum + size);

  final Directory root;
  final http.Client _client;
  final int maxBytes;
  final int maxConcurrent;

  /// File name -> size, oldest first.
  final LinkedHashMap<String, int> _files;
  int _bytes;
  final _inFlight = <String, Future<File?>>{};
  final _names = <String, String>{};
  final _waiting = Queue<Completer<void>>();
  int _running = 0;

  /// A downloaded file larger than this is refused; the app's own uploads
  /// are about 30-60 KB and the bucket accepts at most 512 KB.
  static const maxImageBytes = 2 * 1024 * 1024;
  static const defaultMaxBytes = 100 * 1024 * 1024;

  /// Set once at startup; null (tests, web) means thumbnails load straight
  /// from the network without a disk copy.
  static RemoteProductImageCache? instance;
  static Future<RemoteProductImageCache>? _initializing;

  static Future<RemoteProductImageCache> ensureInitialized() {
    final existing = instance;
    if (existing != null) return Future.value(existing);
    return _initializing ??= () async {
      try {
        final cache = await getApplicationCacheDirectory();
        return instance = await open(
          Directory(p.join(cache.path, 'product_image_cache')),
        );
      } finally {
        _initializing = null;
      }
    }();
  }

  /// Opens a cache rooted at [root], indexing files already on disk.
  static Future<RemoteProductImageCache> open(
    Directory root, {
    http.Client? client,
    int maxBytes = defaultMaxBytes,
    int maxConcurrent = 4,
  }) async {
    final found = <(String, int, DateTime)>[];
    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File || p.extension(entity.path) != '.img') continue;
        final stat = await entity.stat();
        if (stat.size <= 0) continue;
        found.add((p.basename(entity.path), stat.size, stat.modified));
      }
    }
    found.sort((a, b) => a.$3.compareTo(b.$3));
    return RemoteProductImageCache._(
      root,
      LinkedHashMap.fromEntries(found.map((f) => MapEntry(f.$1, f.$2))),
      client ?? http.Client(),
      maxBytes: maxBytes,
      maxConcurrent: maxConcurrent,
    );
  }

  int get totalBytes => _bytes;

  /// The cached copy of [url], or null. Uses the in-memory index only, so
  /// POS grid rebuilds never touch the filesystem.
  File? cached(String url) {
    final name = _nameFor(url);
    return _files.containsKey(name) ? File(p.join(root.path, name)) : null;
  }

  /// Downloads [url] into the cache unless it is already there. Returns
  /// null when it cannot be fetched (offline, missing, not an image); never
  /// throws, so a photo can never break a screen. At most [maxConcurrent]
  /// downloads run at once, so a large uncached grid does not flood the
  /// connection.
  Future<File?> fetch(String url) {
    final existing = cached(url);
    if (existing != null) return Future.value(existing);
    // Block body: returning the removed future would make whenComplete
    // wait on itself.
    return _inFlight[url] ??= _download(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  Future<File?> _download(String url) async {
    await _acquire();
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          bytes.isEmpty ||
          bytes.length > maxImageBytes ||
          !looksLikeImage(bytes)) {
        return null;
      }
      return await _store(_nameFor(url), bytes);
    } catch (_) {
      return null;
    } finally {
      _release();
    }
  }

  Future<File> _store(String name, Uint8List bytes) async {
    await root.create(recursive: true);
    final target = File(p.join(root.path, name));
    final temp = File('${target.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    }
    _bytes += bytes.length - (_files.remove(name) ?? 0);
    _files[name] = bytes.length;
    await _evict(keep: name);
    return target;
  }

  Future<void> _evict({required String keep}) async {
    while (_bytes > maxBytes && _files.length > 1) {
      final oldest = _files.keys.first;
      if (oldest == keep) break;
      _bytes -= _files.remove(oldest)!;
      try {
        await File(p.join(root.path, oldest)).delete();
      } catch (_) {}
    }
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  String _nameFor(String url) => _names[url] ??= cacheFileName(url);

  /// FNV-1a 64-bit of [url]: a stable, filesystem-safe name.
  static String cacheFileName(String url) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final unit in url.codeUnits) {
      hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
    }
    return '${hash.toRadixString(16).padLeft(16, '0')}.img';
  }
}

/// JPEG, PNG or WebP magic bytes; anything else (an HTML error page, a
/// truncated body) is not cached.
bool looksLikeImage(Uint8List b) =>
    (b.length > 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) ||
    (b.length > 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4e &&
        b[3] == 0x47) ||
    (b.length > 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50);
