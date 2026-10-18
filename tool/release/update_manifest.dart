// Release tooling for in-app APK updates (docs/apk-release-workflow.md).
//
//   dart run tool/release/update_manifest.dart keygen <private-key.json>
//       Creates the update-manifest RSA-3072 key. Store the file OUTSIDE the
//       repository (e.g. C:\Users\ansar\.dukaan\signing\) and back it up with
//       the APK keystore. Prints only the PUBLIC values for --dart-define.
//
//   dart run tool/release/update_manifest.dart sign <payload.json> <private-key.json> <manifest.json> <apk-file> <allowed-host>
//       Checks the payload against the real APK (size, SHA-256), signs it,
//       then re-reads the result exactly as the app does before writing.
//
// This key only authorises update manifests. It is NOT the APK signing key
// and never replaces it: Android still checks the APK signature on install.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dukaan_pro/features/app_update/update_manifest.dart';
import 'package:dukaan_pro/subscription/entitlement.dart' show canonicalJson;
import 'package:pointycastle/export.dart';

String b64(BigInt v) {
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return base64Url.encode(bytes).replaceAll('=', '');
}

BigInt unb64(String v) => BigInt.parse(
  base64Url
      .decode(base64Url.normalize(v))
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join(),
  radix: 16,
);

Never fail(String message) {
  stderr.writeln(message);
  exit(1);
}

void keygen(String path) {
  final file = File(path);
  if (file.existsSync()) fail('Refusing to overwrite $path');
  final seed = Random.secure();
  final random = FortunaRandom()
    ..seed(
      KeyParameter(
        Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256))),
      ),
    );
  final pair =
      (RSAKeyGenerator()..init(
            ParametersWithRandom(
              RSAKeyGeneratorParameters(BigInt.from(65537), 3072, 64),
              random,
            ),
          ))
          .generateKeyPair();
  final pub = pair.publicKey, priv = pair.privateKey;
  file.writeAsStringSync(
    jsonEncode({
      'kty': 'RSA',
      'use': 'dokan-pro-update-manifest',
      'n': b64(pub.modulus!),
      'e': b64(pub.exponent!),
      'd': b64(priv.privateExponent!),
      'p': b64(priv.p!),
      'q': b64(priv.q!),
    }),
  );
  stdout
    ..writeln(
      'Private key written to $path (keep it outside the repository; back it up).',
    )
    ..writeln('Public values for the app build (safe to share):')
    ..writeln('  APP_UPDATE_RSA_MODULUS_B64URL=${b64(pub.modulus!)}')
    ..writeln('  APP_UPDATE_RSA_EXPONENT_B64URL=${b64(pub.exponent!)}');
}

String sha256Hex(File f) {
  final d = SHA256Digest();
  final out = d.process(f.readAsBytesSync());
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void signManifest(
  String payloadPath,
  String keyPath,
  String outPath,
  String apkPath,
  String host,
) {
  final payload =
      jsonDecode(File(payloadPath).readAsStringSync()) as Map<String, dynamic>;
  final jwk =
      jsonDecode(File(keyPath).readAsStringSync()) as Map<String, dynamic>;
  final apk = File(apkPath);
  if (!apk.existsSync()) fail('APK not found: $apkPath');
  if (payload['apkSizeBytes'] != apk.lengthSync()) {
    fail('apkSizeBytes does not match the APK (${apk.lengthSync()})');
  }
  if (payload['apkSha256'] != sha256Hex(apk)) {
    fail('apkSha256 does not match the APK');
  }
  final n = unb64(jwk['n'] as String), e = unb64(jwk['e'] as String);
  final priv = RSAPrivateKey(
    n,
    unb64(jwk['d'] as String),
    unb64(jwk['p'] as String),
    unb64(jwk['q'] as String),
  );
  final signer = Signer('SHA-256/RSA')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
  final sig =
      signer.generateSignature(
            Uint8List.fromList(utf8.encode(canonicalJson(payload))),
          )
          as RSASignature;
  final manifest = const JsonEncoder.withIndent('  ').convert({
    'payload': payload,
    'algorithm': 'RS256',
    'keyId': jwk['kid'] ?? 'update-1',
    'signature': base64Url.encode(sig.bytes).replaceAll('=', ''),
  });
  // Same checks as the app (signature, HTTPS host, fields).
  final UpdateManifest parsed;
  try {
    parsed = UpdateManifestParser(
      publicKey: RSAPublicKey(n, e),
      allowedHosts: {host.toLowerCase()},
      packageName: 'com.dukaanpro.dukaan_pro',
    ).parse(manifest);
  } on UpdateManifestException catch (e) {
    fail("Manifest refused by the app's own checks: ${e.reason}");
  }
  final out = File(outPath);
  if (out.existsSync()) {
    fail('Refusing to overwrite $outPath; write a new file per release.');
  }
  out.writeAsStringSync('$manifest\n');
  stdout.writeln(
    'Signed manifest for ${parsed.versionName} (versionCode ${parsed.versionCode}) -> $outPath',
  );
}

void main(List<String> args) {
  switch (args) {
    case ['keygen', final path]:
      keygen(path);
    case ['sign', final payload, final key, final out, final apk, final host]:
      signManifest(payload, key, out, apk, host);
    default:
      fail(
        'usage: keygen <private-key.json> | sign <payload.json> <private-key.json> <manifest.json> <apk> <allowed-host>',
      );
  }
}
