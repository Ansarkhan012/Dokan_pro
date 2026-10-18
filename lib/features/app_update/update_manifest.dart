import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../subscription/entitlement.dart' show canonicalJson;

/// A published APK release, as described by the signed update manifest.
///
/// The manifest is trusted only when its RS256 signature verifies against
/// the update public key compiled into the app ([UpdateConfig]). A
/// compromised web host can therefore serve old or broken files, but never
/// authorise an APK the release key did not sign off: the APK's SHA-256 is
/// part of the signed payload, and its URL must be on the compiled-in host
/// allow-list.
///
/// Signed form (`manifest.json`):
/// ```json
/// {"payload": {...fields below...}, "algorithm": "RS256",
///  "keyId": "update-1", "signature": "<base64url>"}
/// ```
/// The signature covers `canonicalJson(payload)` (sorted keys), as for
/// subscription entitlements.
final class UpdateManifest {
  const UpdateManifest({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.apkSha256,
    required this.apkSizeBytes,
    required this.minSupportedVersionCode,
    required this.forceUpdate,
    required this.releaseNotesEn,
    required this.releaseNotesUr,
    required this.publishedAt,
  });

  final String packageName, versionName, apkSha256;
  final int versionCode, apkSizeBytes, minSupportedVersionCode;
  final Uri apkUrl;
  final bool forceUpdate;
  final String releaseNotesEn, releaseNotesUr;
  final DateTime publishedAt;

  String releaseNotesFor(String languageCode) =>
      languageCode == 'ur' && releaseNotesUr.isNotEmpty
      ? releaseNotesUr
      : releaseNotesEn;

  /// Whether this release must be installed for [installedVersionCode] to
  /// stay supported. Never a lockout by itself (see UpdateOffer.mandatory).
  bool requiredFor(int installedVersionCode) =>
      forceUpdate || installedVersionCode < minSupportedVersionCode;
}

/// Why a manifest was not accepted. Reported, never shown raw to users.
final class UpdateManifestException implements Exception {
  const UpdateManifestException(this.reason);
  final String reason;
  @override
  String toString() => 'UpdateManifestException: $reason';
}

/// Limits that make a manifest "suspicious" rather than just new.
abstract final class UpdateManifestLimits {
  static const maxApkBytes = 400 * 1024 * 1024;
  static const minApkBytes = 1024 * 1024;
  static const maxNotesChars = 2000;
  static const maxVersionNameChars = 32;
  static const futureSkew = Duration(days: 1);
}

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');
final _versionName = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+\-]*$');

/// Parses, verifies and validates a downloaded manifest document.
final class UpdateManifestParser {
  const UpdateManifestParser({
    required this.publicKey,
    required this.allowedHosts,
    required this.packageName,
  });

  final RSAPublicKey publicKey;

  /// Exact host names (lower case) the APK may be downloaded from.
  final Set<String> allowedHosts;

  /// The installed app's application ID; any other package is refused.
  final String packageName;

  UpdateManifest parse(String body, {DateTime? now}) {
    final Object? document;
    try {
      document = jsonDecode(body);
    } on FormatException {
      throw const UpdateManifestException('not JSON');
    }
    if (document is! Map<String, dynamic>) {
      throw const UpdateManifestException('not an object');
    }
    final payload = document['payload'];
    if (payload is! Map<String, dynamic>) {
      throw const UpdateManifestException('payload missing');
    }
    if (document['algorithm'] != 'RS256') {
      throw const UpdateManifestException('unsupported algorithm');
    }
    _verifySignature(payload, document['signature']);
    return _validate(payload, now ?? DateTime.now().toUtc());
  }

  void _verifySignature(Map<String, dynamic> payload, Object? signature) {
    if (signature is! String || signature.isEmpty) {
      throw const UpdateManifestException('signature missing');
    }
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(signature));
    } on FormatException {
      throw const UpdateManifestException('signature malformed');
    }
    final verifier = Signer('SHA-256/RSA')
      ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
    bool ok;
    try {
      ok = verifier.verifySignature(
        Uint8List.fromList(utf8.encode(canonicalJson(payload))),
        RSASignature(bytes),
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) throw const UpdateManifestException('signature invalid');
  }

  UpdateManifest _validate(Map<String, dynamic> p, DateTime now) {
    T field<T>(String name) {
      final value = p[name];
      if (value is! T) throw UpdateManifestException('$name invalid');
      return value;
    }

    final package = field<String>('packageName');
    if (package != packageName) {
      throw const UpdateManifestException('packageName mismatch');
    }
    final versionName = field<String>('versionName').trim();
    if (versionName.isEmpty ||
        versionName.length > UpdateManifestLimits.maxVersionNameChars ||
        !_versionName.hasMatch(versionName)) {
      throw const UpdateManifestException('versionName invalid');
    }
    final versionCode = field<int>('versionCode');
    if (versionCode < 1) {
      throw const UpdateManifestException('versionCode invalid');
    }
    final minSupported = field<int>('minSupportedVersionCode');
    if (minSupported < 1 || minSupported > versionCode) {
      throw const UpdateManifestException('minSupportedVersionCode invalid');
    }
    final apkUrl = validateApkUrl(field<String>('apkUrl'));
    final sha = field<String>('apkSha256');
    if (!_sha256Hex.hasMatch(sha)) {
      throw const UpdateManifestException('apkSha256 invalid');
    }
    final size = field<int>('apkSizeBytes');
    if (size < UpdateManifestLimits.minApkBytes ||
        size > UpdateManifestLimits.maxApkBytes) {
      throw const UpdateManifestException('apkSizeBytes out of range');
    }
    final notes = field<Map<String, dynamic>>('releaseNotes');
    String note(String lang) {
      final v = notes[lang] ?? '';
      if (v is! String || v.length > UpdateManifestLimits.maxNotesChars) {
        throw UpdateManifestException('releaseNotes.$lang invalid');
      }
      return v.trim();
    }

    final en = note('en');
    if (en.isEmpty) {
      throw const UpdateManifestException('releaseNotes.en empty');
    }
    final published = DateTime.tryParse(field<String>('publishedAt'));
    if (published == null ||
        published.toUtc().isAfter(now.add(UpdateManifestLimits.futureSkew))) {
      throw const UpdateManifestException('publishedAt invalid');
    }
    return UpdateManifest(
      packageName: package,
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: apkUrl,
      apkSha256: sha,
      apkSizeBytes: size,
      minSupportedVersionCode: minSupported,
      forceUpdate: field<bool>('forceUpdate'),
      releaseNotesEn: en,
      releaseNotesUr: note('ur'),
      publishedAt: published.toUtc(),
    );
  }

  /// HTTPS only, default port, no credentials, host on the allow-list,
  /// path ending in `.apk`.
  Uri validateApkUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.fragment.isNotEmpty ||
        !allowedHosts.contains(uri.host.toLowerCase()) ||
        !uri.path.toLowerCase().endsWith('.apk')) {
      throw const UpdateManifestException('apkUrl not allowed');
    }
    return uri;
  }
}
