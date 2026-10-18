import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import 'update_manifest.dart';

/// Why a download did not produce a verified APK.
enum DownloadFailure {
  network,
  timeout,
  httpStatus,
  sizeMismatch,
  hashMismatch,
  cancelled,
  storage,
}

final class ApkDownloadException implements Exception {
  const ApkDownloadException(this.failure, [this.detail = '']);
  final DownloadFailure failure;
  final String detail;
  @override
  String toString() => 'ApkDownloadException(${failure.name}) $detail';
}

/// Cancels an in-flight download.
final class DownloadCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void _onCancel(void Function() l) => _listeners.add(l);
}

/// Downloads a release APK into its own cache folder and verifies it.
///
/// Scope: only `<cacheDir>/app_update/dokan_pro_<versionCode>.apk[.part]`.
/// It never reads or writes anything else (databases, preferences, images,
/// backups), and [cleanObsolete] deletes only files matching that pattern.
final class ApkDownloader {
  ApkDownloader({
    required this.cacheDirectory,
    http.Client Function()? clientFactory,
    this.stallTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 20),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  /// The app's cache directory (path_provider getApplicationCacheDirectory).
  final Future<Directory> Function() cacheDirectory;
  final http.Client Function() _clientFactory;
  final Duration stallTimeout, connectTimeout;

  static final _ownFile = RegExp(r'^dokan_pro_\d+\.apk(\.part)?$');

  Future<Directory> _dir() async {
    final dir = Directory('${(await cacheDirectory()).path}/app_update');
    await dir.create(recursive: true);
    return dir;
  }

  static String fileName(int versionCode) => 'dokan_pro_$versionCode.apk';

  /// Removes this feature's leftovers except the APK for [keepVersionCode].
  Future<int> cleanObsolete({int? keepVersionCode}) async {
    final dir = await _dir();
    var removed = 0;
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is! File || !_ownFile.hasMatch(name)) continue;
      if (keepVersionCode != null && name == fileName(keepVersionCode)) {
        continue;
      }
      await entity.delete();
      removed++;
    }
    return removed;
  }

  /// A previously verified APK for [manifest], re-hashed before reuse.
  Future<File?> verifiedExisting(UpdateManifest manifest) async {
    final file = File(
      '${(await _dir()).path}/${fileName(manifest.versionCode)}',
    );
    if (!await file.exists()) return null;
    try {
      await _verify(file, manifest);
      return file;
    } on ApkDownloadException {
      await file.delete();
      return null;
    }
  }

  /// Downloads and verifies. [onProgress] gets (received, total) bytes.
  Future<File> download(
    UpdateManifest manifest, {
    required void Function(int received, int total) onProgress,
    DownloadCancelToken? cancel,
  }) async {
    final dir = await _dir();
    final target = File('${dir.path}/${fileName(manifest.versionCode)}');
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();
    if (await target.exists()) await target.delete();

    final client = _clientFactory();
    cancel?._onCancel(client.close);
    IOSink? sink;
    try {
      if (cancel?.isCancelled ?? false) {
        throw const ApkDownloadException(DownloadFailure.cancelled);
      }
      final http.StreamedResponse response;
      try {
        response = await client
            .send(http.Request('GET', manifest.apkUrl)..followRedirects = false)
            .timeout(connectTimeout);
      } on TimeoutException {
        throw const ApkDownloadException(DownloadFailure.timeout);
      }
      if (response.statusCode != 200) {
        throw ApkDownloadException(
          DownloadFailure.httpStatus,
          '${response.statusCode}',
        );
      }
      final declared = response.contentLength;
      if (declared != null && declared != manifest.apkSizeBytes) {
        throw const ApkDownloadException(DownloadFailure.sizeMismatch);
      }
      sink = part.openWrite();
      final digest = SHA256Digest();
      var received = 0;
      onProgress(0, manifest.apkSizeBytes);
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        if (cancel?.isCancelled ?? false) {
          throw const ApkDownloadException(DownloadFailure.cancelled);
        }
        received += chunk.length;
        if (received > manifest.apkSizeBytes) {
          throw const ApkDownloadException(DownloadFailure.sizeMismatch);
        }
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        digest.update(bytes, 0, bytes.length);
        sink.add(bytes);
        onProgress(received, manifest.apkSizeBytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != manifest.apkSizeBytes) {
        throw const ApkDownloadException(DownloadFailure.sizeMismatch);
      }
      final out = Uint8List(digest.digestSize);
      digest.doFinal(out, 0);
      if (_hex(out) != manifest.apkSha256) {
        throw const ApkDownloadException(DownloadFailure.hashMismatch);
      }
      return await part.rename(target.path);
    } on ApkDownloadException {
      await _discard(sink, part);
      rethrow;
    } on TimeoutException {
      await _discard(sink, part);
      throw const ApkDownloadException(DownloadFailure.timeout);
    } on FileSystemException catch (e) {
      await _discard(sink, part);
      throw ApkDownloadException(DownloadFailure.storage, e.message);
    } catch (e) {
      await _discard(sink, part);
      if (cancel?.isCancelled ?? false) {
        throw const ApkDownloadException(DownloadFailure.cancelled);
      }
      throw ApkDownloadException(DownloadFailure.network, '${e.runtimeType}');
    } finally {
      client.close();
    }
  }

  Future<void> _discard(IOSink? sink, File part) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  Future<void> _verify(File file, UpdateManifest manifest) async {
    if (await file.length() != manifest.apkSizeBytes) {
      throw const ApkDownloadException(DownloadFailure.sizeMismatch);
    }
    final digest = SHA256Digest();
    await for (final chunk in file.openRead()) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
    }
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    if (_hex(out) != manifest.apkSha256) {
      throw const ApkDownloadException(DownloadFailure.hashMismatch);
    }
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
