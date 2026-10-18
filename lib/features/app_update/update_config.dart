import 'dart:convert';

import 'package:pointycastle/export.dart';

/// Build-time configuration of in-app updates (all `--dart-define`):
///
/// * `APP_UPDATE_MANIFEST_URL`   HTTPS URL of the signed manifest.json.
/// * `APP_UPDATE_ALLOWED_HOSTS`  comma-separated hosts the manifest and APK
///                               may come from (exact names).
/// * `APP_UPDATE_RSA_MODULUS_B64URL` / `APP_UPDATE_RSA_EXPONENT_B64URL`
///                               public half of the update-manifest key
///                               (not the APK signing key).
///
/// Only public values: the private manifest key never leaves the release
/// machine. When anything is missing or not HTTPS, updates are disabled and
/// the app behaves exactly as before.
final class UpdateConfig {
  const UpdateConfig({
    required this.manifestUrl,
    required this.allowedHosts,
    required this.publicKey,
    this.packageName = defaultPackageName,
  });

  static const defaultPackageName = 'com.dukaanpro.dukaan_pro';

  final Uri manifestUrl;
  final Set<String> allowedHosts;
  final RSAPublicKey publicKey;
  final String packageName;

  /// Null when updates are not configured for this build.
  static UpdateConfig? fromEnvironment() => tryCreate(
    manifestUrl: const String.fromEnvironment('APP_UPDATE_MANIFEST_URL'),
    allowedHosts: const String.fromEnvironment('APP_UPDATE_ALLOWED_HOSTS'),
    modulusB64Url: const String.fromEnvironment(
      'APP_UPDATE_RSA_MODULUS_B64URL',
    ),
    exponentB64Url: const String.fromEnvironment(
      'APP_UPDATE_RSA_EXPONENT_B64URL',
      defaultValue: 'AQAB',
    ),
  );

  static UpdateConfig? tryCreate({
    required String manifestUrl,
    required String allowedHosts,
    required String modulusB64Url,
    String exponentB64Url = 'AQAB',
  }) {
    final hosts = {
      for (final h in allowedHosts.split(','))
        if (h.trim().isNotEmpty) h.trim().toLowerCase(),
    };
    final url = Uri.tryParse(manifestUrl.trim());
    if (url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        !hosts.contains(url.host.toLowerCase()) ||
        modulusB64Url.isEmpty) {
      return null;
    }
    try {
      final n = _decode(modulusB64Url);
      // Below 2048 bits is not an acceptable release key.
      if (n.bitLength < 2048) return null;
      return UpdateConfig(
        manifestUrl: url,
        allowedHosts: hosts,
        publicKey: RSAPublicKey(n, _decode(exponentB64Url)),
      );
    } on FormatException {
      return null;
    }
  }

  static BigInt _decode(String v) => BigInt.parse(
    base64Url
        .decode(base64Url.normalize(v))
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join(),
    radix: 16,
  );
}
