// In-app APK updates: signed manifest, download verification, install
// compatibility rules, controller flow and the update dialog. Android's own
// installer is faked here; a real-device upgrade is a separate manual test
// (docs/apk-release-workflow.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dukaan_pro/core/billing_activity.dart';
import 'package:dukaan_pro/features/app_update/apk_downloader.dart';
import 'package:dukaan_pro/features/app_update/apk_installer.dart';
import 'package:dukaan_pro/features/app_update/app_update_host.dart';
import 'package:dukaan_pro/features/app_update/update_config.dart';
import 'package:dukaan_pro/features/app_update/update_controller.dart';
import 'package:dukaan_pro/features/app_update/update_dialog.dart';
import 'package:dukaan_pro/features/app_update/update_manifest.dart';
import 'package:dukaan_pro/l10n/app_localizations.dart';
import 'package:dukaan_pro/subscription/entitlement.dart' show canonicalJson;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pkg = 'com.dukaanpro.dukaan_pro';
const host = 'releases.dokanpro.test';
const debugSigner = 'aa11';
const releaseSigner = 'bb22';

late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keys;
late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> otherKeys;

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generate(int seed) {
  final random = FortunaRandom()
    ..seed(
      KeyParameter(
        Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff)),
      ),
    );
  final g = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        random,
      ),
    );
  final pair = g.generateKeyPair();
  return AsymmetricKeyPair(pair.publicKey, pair.privateKey);
}

String sign(Map<String, dynamic> payload, RSAPrivateKey key) {
  final signer = Signer('SHA-256/RSA')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
  final sig =
      signer.generateSignature(
            Uint8List.fromList(utf8.encode(canonicalJson(payload))),
          )
          as RSASignature;
  return base64Url.encode(sig.bytes).replaceAll('=', '');
}

final apkBytes = Uint8List.fromList(
  List.generate(2 * 1024 * 1024 + 17, (i) => (i * 31) & 0xff),
);
String sha(Uint8List b) {
  final d = SHA256Digest();
  final out = d.process(b);
  return out.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, dynamic> payload({
  int versionCode = 5,
  Map<String, dynamic> override = const {},
}) => {
  'packageName': pkg,
  'versionName': '1.0.$versionCode',
  'versionCode': versionCode,
  'apkUrl': 'https://$host/dokan-pro/dokan_pro_$versionCode.apk',
  'apkSha256': sha(apkBytes),
  'apkSizeBytes': apkBytes.length,
  'minSupportedVersionCode': 1,
  'forceUpdate': false,
  'releaseNotes': {
    'en': 'Faster billing and bug fixes.',
    'ur': 'تیز بلنگ اور خرابیوں کی درستی۔',
  },
  'publishedAt': '2026-10-15T08:00:00Z',
  ...override,
};

String manifestJson(
  Map<String, dynamic> p, {
  RSAPrivateKey? key,
  String algorithm = 'RS256',
  String? signature,
}) => jsonEncode({
  'payload': p,
  'algorithm': algorithm,
  'keyId': 'update-1',
  'signature': signature ?? sign(p, key ?? keys.privateKey),
});

UpdateManifestParser parser() => UpdateManifestParser(
  publicKey: keys.publicKey,
  allowedHosts: {host},
  packageName: pkg,
);
final now = DateTime.utc(2026, 10, 16);

UpdateConfig config() => UpdateConfig(
  manifestUrl: Uri.parse('https://$host/dokan-pro/manifest.json'),
  allowedHosts: {host},
  publicKey: keys.publicKey,
);

final class FakeInstaller implements ApkInstaller {
  FakeInstaller({
    this.versionCode = 3,
    this.canInstall = true,
    this.archive,
    this.installResult = InstallStatus.userConfirming,
  });
  int versionCode;
  bool canInstall;
  ApkArchive? archive;
  InstallStatus installResult;
  final installs = <String>[];
  final permissionScreens = <int>[];
  final _statuses = StreamController<InstallStatus>.broadcast();
  void emit(InstallStatus s) => _statuses.add(s);

  @override
  Future<InstalledApp> installedApp() async => InstalledApp(
    packageName: pkg,
    versionCode: versionCode,
    versionName: '1.0.$versionCode',
    signerSha256: {debugSigner},
    canRequestInstalls: canInstall,
  );
  @override
  Future<ApkArchive> inspect(String apkPath) async =>
      archive ??
      const ApkArchive(
        packageName: pkg,
        versionCode: 5,
        versionName: '1.0.5',
        signerSha256: {releaseSigner},
        signerHistorySha256: {debugSigner, releaseSigner},
      );
  @override
  Future<void> openInstallPermissionSettings() async =>
      permissionScreens.add(1);
  @override
  Future<InstallStatus> install(String apkPath) async {
    installs.add(apkPath);
    return installResult;
  }

  @override
  Stream<InstallStatus> get statuses => _statuses.stream;
}

final class MemoryPrefs implements UpdatePreferences {
  DateTime? last;
  int? dismissed;
  @override
  Future<DateTime?> lastCheck() async => last;
  @override
  Future<void> setLastCheck(DateTime at) async => last = at;
  @override
  Future<int?> dismissedVersionCode() async => dismissed;
  @override
  Future<void> setDismissedVersionCode(int code) async => dismissed = code;
}

/// Serves the manifest and the APK; counts requests.
final class Server {
  Server({required this.manifest, Uint8List? apk}) : apk = apk ?? apkBytes;
  String manifest;
  Uint8List apk;
  int manifestHits = 0, apkHits = 0;
  bool offline = false;
  http.Client client() => MockClient.streaming((request, _) async {
    if (offline) throw const SocketException('offline');
    if (request.url.path.endsWith('manifest.json')) {
      manifestHits++;
      return http.StreamedResponse(Stream.value(utf8.encode(manifest)), 200);
    }
    apkHits++;
    return http.StreamedResponse(
      Stream.fromIterable([
        apk.sublist(0, apk.length ~/ 2),
        apk.sublist(apk.length ~/ 2),
      ]),
      200,
      contentLength: apk.length,
    );
  });
}

void main() {
  setUpAll(() {
    keys = generate(1);
    otherKeys = generate(2);
  });

  group('manifest', () {
    test('a correctly signed manifest parses; versionCode is numeric', () {
      final m = parser().parse(
        manifestJson(payload(versionCode: 10)),
        now: now,
      );
      expect(m.versionCode, 10);
      expect(
        m.versionCode > 9,
        isTrue,
        reason: '10 > 9 numerically, unlike "10" < "9"',
      );
      expect(m.apkUrl.host, host);
      expect(m.releaseNotesFor('ur'), contains('بلنگ'));
      expect(m.releaseNotesFor('en'), contains('billing'));
      expect(
        () => parser().parse(
          manifestJson(payload(override: {'versionCode': '10'})),
          now: now,
        ),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('tampering, missing or foreign signatures are refused', () {
      final p = payload();
      final good = sign(p, keys.privateKey);
      final tampered = {...p, 'apkSha256': 'f' * 64};
      for (final body in [
        manifestJson(tampered, signature: good),
        manifestJson(p, key: otherKeys.privateKey),
        manifestJson(p, signature: ''),
        manifestJson(p, algorithm: 'none'),
        manifestJson(p, signature: '%%%'),
        jsonEncode({'payload': p, 'algorithm': 'RS256'}),
        'not json',
        '[]',
      ]) {
        expect(
          () => parser().parse(body, now: now),
          throwsA(isA<UpdateManifestException>()),
          reason: body.length > 60 ? body.substring(0, 60) : body,
        );
      }
    });

    test('untrusted or malformed APK URLs are refused even when signed', () {
      for (final url in [
        'http://$host/a.apk',
        'https://evil.test/a.apk',
        'https://$host.evil.test/a.apk',
        'https://user:pw@$host/a.apk',
        'https://$host:8443/a.apk',
        'https://$host/a.zip',
        'https://$host/a.apk#x',
        'file:///sdcard/a.apk',
        'javascript:alert(1)',
      ]) {
        expect(
          () => parser().parse(
            manifestJson(payload(override: {'apkUrl': url})),
            now: now,
          ),
          throwsA(isA<UpdateManifestException>()),
          reason: url,
        );
      }
    });

    test('suspicious fields are refused', () {
      for (final o in <Map<String, dynamic>>[
        {'packageName': 'com.evil.app'},
        {'apkSha256': 'ABC'},
        {'apkSha256': 'A' * 64},
        {'apkSizeBytes': 10},
        {'apkSizeBytes': 900 * 1024 * 1024},
        {'minSupportedVersionCode': 9},
        {'versionCode': 0},
        {'versionName': '1.0 <script>'},
        {'publishedAt': '2027-01-01T00:00:00Z'},
        {'publishedAt': 'yesterday'},
        {'forceUpdate': 'yes'},
        {
          'releaseNotes': {'en': ''},
        },
        {
          'releaseNotes': {'en': 'x' * 3000},
        },
      ]) {
        expect(
          () => parser().parse(manifestJson(payload(override: o)), now: now),
          throwsA(isA<UpdateManifestException>()),
          reason: '$o',
        );
      }
    });

    test('required updates: forceUpdate or below minSupportedVersionCode', () {
      final m = parser().parse(
        manifestJson(
          payload(versionCode: 5, override: {'minSupportedVersionCode': 4}),
        ),
        now: now,
      );
      expect(m.requiredFor(3), isTrue);
      expect(m.requiredFor(4), isFalse);
      final forced = parser().parse(
        manifestJson(payload(override: {'forceUpdate': true})),
        now: now,
      );
      expect(forced.requiredFor(4), isTrue);
    });

    test('build config needs HTTPS, an allowed host and a 2048-bit key', () {
      final n = base64Url
          .encode(_bytes(keys.publicKey.modulus!))
          .replaceAll('=', '');
      expect(
        UpdateConfig.tryCreate(
          manifestUrl: 'https://$host/m.json',
          allowedHosts: host,
          modulusB64Url: n,
        ),
        isNotNull,
      );
      expect(
        UpdateConfig.tryCreate(
          manifestUrl: 'http://$host/m.json',
          allowedHosts: host,
          modulusB64Url: n,
        ),
        isNull,
      );
      expect(
        UpdateConfig.tryCreate(
          manifestUrl: 'https://other.test/m.json',
          allowedHosts: host,
          modulusB64Url: n,
        ),
        isNull,
      );
      expect(
        UpdateConfig.tryCreate(
          manifestUrl: 'https://$host/m.json',
          allowedHosts: host,
          modulusB64Url: '',
        ),
        isNull,
      );
      expect(
        UpdateConfig.tryCreate(
          manifestUrl: 'https://$host/m.json',
          allowedHosts: host,
          modulusB64Url: 'AQAB',
        ),
        isNull,
      );
    });
  });

  group('APK compatibility', () {
    const installed = InstalledApp(
      packageName: pkg,
      versionCode: 3,
      versionName: '1.0.3',
      signerSha256: {debugSigner},
      canRequestInstalls: true,
    );
    ApkArchive archive({
      String package = pkg,
      int code = 5,
      Set<String> signers = const {releaseSigner},
      Set<String> history = const {debugSigner, releaseSigner},
    }) => ApkArchive(
      packageName: package,
      versionCode: code,
      versionName: '',
      signerSha256: signers,
      signerHistorySha256: history,
    );

    test('rotated key with lineage (debug -> release) is accepted', () {
      expect(
        checkApkCompatibility(
          installed: installed,
          archive: archive(),
          expectedVersionCode: 5,
        ),
        isNull,
      );
    });
    test(
      'wrong package, downgrade, same version, unexpected version, foreign signer',
      () {
        expect(
          checkApkCompatibility(
            installed: installed,
            archive: archive(package: 'com.evil'),
            expectedVersionCode: 5,
          ),
          ApkRejection.wrongPackage,
        );
        expect(
          checkApkCompatibility(
            installed: installed,
            archive: archive(code: 2),
            expectedVersionCode: 2,
          ),
          ApkRejection.notNewer,
        );
        expect(
          checkApkCompatibility(
            installed: installed,
            archive: archive(code: 3),
            expectedVersionCode: 3,
          ),
          ApkRejection.notNewer,
        );
        expect(
          checkApkCompatibility(
            installed: installed,
            archive: archive(code: 6),
            expectedVersionCode: 5,
          ),
          ApkRejection.versionMismatch,
        );
        expect(
          checkApkCompatibility(
            installed: installed,
            archive: archive(signers: {'cc33'}, history: {'cc33'}),
            expectedVersionCode: 5,
          ),
          ApkRejection.signerMismatch,
        );
        expect(
          checkApkCompatibility(
            installed: installed,
            archive: archive(signers: {releaseSigner}, history: const {}),
            expectedVersionCode: 5,
          ),
          ApkRejection.signerMismatch,
          reason:
              'release-key APK without lineage cannot update a debug-signed install',
        );
      },
    );
  });

  group('downloader', () {
    late Directory cache;
    setUp(
      () => cache = Directory.systemTemp.createTempSync('dokan_update_test'),
    );
    tearDown(() => cache.deleteSync(recursive: true));

    UpdateManifest manifest({String? hash, int? size}) => UpdateManifest(
      packageName: pkg,
      versionName: '1.0.5',
      versionCode: 5,
      apkUrl: Uri.parse('https://$host/a.apk'),
      apkSha256: hash ?? sha(apkBytes),
      apkSizeBytes: size ?? apkBytes.length,
      minSupportedVersionCode: 1,
      forceUpdate: false,
      releaseNotesEn: 'x',
      releaseNotesUr: '',
      publishedAt: now,
    );

    ApkDownloader downloader(
      http.Client Function() client, {
      Duration stall = const Duration(seconds: 5),
    }) => ApkDownloader(
      cacheDirectory: () async => cache,
      clientFactory: client,
      stallTimeout: stall,
    );

    test('verified download with real progress', () async {
      final progress = <int>[];
      final file = await downloader(
        Server(manifest: '').client,
      ).download(manifest(), onProgress: (r, _) => progress.add(r));
      expect(file.uri.pathSegments.reversed.take(2).toList(), [
        'dokan_pro_5.apk',
        'app_update',
      ]);
      expect(await file.length(), apkBytes.length);
      expect(progress.first, 0);
      expect(progress.last, apkBytes.length);
      expect(progress.length, greaterThan(2));
    });

    test('SHA-256 mismatch: rejected, partial file deleted', () async {
      await expectLater(
        downloader(
          Server(manifest: '').client,
        ).download(manifest(hash: 'e' * 64), onProgress: (_, _) {}),
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.failure,
            'failure',
            DownloadFailure.hashMismatch,
          ),
        ),
      );
      expect(Directory('${cache.path}/app_update').listSync(), isEmpty);
    });

    test('size mismatch and HTTP errors are rejected', () async {
      await expectLater(
        downloader(
          Server(manifest: '').client,
        ).download(manifest(size: apkBytes.length + 1), onProgress: (_, _) {}),
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.failure,
            'failure',
            DownloadFailure.sizeMismatch,
          ),
        ),
      );
      await expectLater(
        downloader(
          () => MockClient((_) async => http.Response('nope', 404)),
        ).download(manifest(), onProgress: (_, _) {}),
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.failure,
            'failure',
            DownloadFailure.httpStatus,
          ),
        ),
      );
    });

    test('a stalled connection times out and leaves nothing behind', () async {
      final stalled = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream<List<int>>.fromFuture(Completer<List<int>>().future),
          200,
          contentLength: apkBytes.length,
        ),
      );
      await expectLater(
        downloader(
          () => stalled,
          stall: const Duration(milliseconds: 50),
        ).download(manifest(), onProgress: (_, _) {}),
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.failure,
            'failure',
            DownloadFailure.timeout,
          ),
        ),
      );
      expect(Directory('${cache.path}/app_update').listSync(), isEmpty);
    });

    test(
      'cancellation stops the download and removes the partial file',
      () async {
        final token = DownloadCancelToken();
        final chunks = StreamController<List<int>>();
        final client = MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            chunks.stream,
            200,
            contentLength: apkBytes.length,
          ),
        );
        final future = downloader(() => client).download(
          manifest(),
          cancel: token,
          onProgress: (r, _) {
            if (r > 0) token.cancel();
          },
        );
        chunks.add(apkBytes.sublist(0, 1000));
        chunks.add(apkBytes.sublist(1000, 2000));
        await expectLater(
          future,
          throwsA(
            isA<ApkDownloadException>().having(
              (e) => e.failure,
              'failure',
              DownloadFailure.cancelled,
            ),
          ),
        );
        await chunks.close();
        expect(Directory('${cache.path}/app_update').listSync(), isEmpty);
      },
    );

    test('cleanup removes only this feature\'s files', () async {
      final updates = Directory('${cache.path}/app_update')..createSync();
      for (final n in [
        'dokan_pro_3.apk',
        'dokan_pro_4.apk.part',
        'dokan_pro_5.apk',
      ]) {
        File('${updates.path}/$n').writeAsStringSync('x');
      }
      File('${updates.path}/notes.txt').writeAsStringSync('keep');
      File('${cache.path}/dukaan_pro.sqlite').writeAsStringSync('POS DATA');
      Directory('${cache.path}/product_images').createSync();
      File('${cache.path}/product_images/p.jpg').writeAsStringSync('img');
      final removed = await downloader(
        Server(manifest: '').client,
      ).cleanObsolete(keepVersionCode: 5);
      expect(removed, 2);
      expect(updates.listSync().map((e) => e.uri.pathSegments.last).toSet(), {
        'dokan_pro_5.apk',
        'notes.txt',
      });
      expect(
        File('${cache.path}/dukaan_pro.sqlite').readAsStringSync(),
        'POS DATA',
      );
      expect(File('${cache.path}/product_images/p.jpg').existsSync(), isTrue);
    });
  });

  group('controller', () {
    late Directory cache;
    late Server server;
    late FakeInstaller installer;
    late MemoryPrefs prefs;
    setUp(() {
      cache = Directory.systemTemp.createTempSync('dokan_update_ctrl');
      server = Server(manifest: manifestJson(payload()));
      installer = FakeInstaller();
      prefs = MemoryPrefs();
    });
    tearDown(() => cache.deleteSync(recursive: true));

    UpdateController controller() => UpdateController(
      config: config(),
      downloader: ApkDownloader(
        cacheDirectory: () async => cache,
        clientFactory: server.client,
      ),
      installer: installer,
      preferences: prefs,
      clientFactory: server.client,
      clock: () => now,
    );

    test('offline or broken manifests are silent, never thrown', () async {
      server.offline = true;
      final c = controller();
      expect((await c.check()).offer, isNull);
      expect(c.phase, UpdatePhase.idle);
      server
        ..offline = false
        ..manifest = '{"payload":{}}';
      expect((await c.check(manual: true)).offer, isNull);
      expect(c.failure, UpdateFailure.manifestInvalid);
    });

    test('automatic checks are throttled; manual checks are not', () async {
      final c = controller();
      expect((await c.check()).offer?.manifest.versionCode, 5);
      expect((await c.check()).checked, isFalse);
      expect(server.manifestHits, 1);
      await c.check(manual: true);
      expect(server.manifestHits, 2);
    });

    test('no prompt when installed is the same or newer', () async {
      installer.versionCode = 5;
      final c = controller();
      expect((await c.check(manual: true)).offer, isNull);
      expect(c.phase, UpdatePhase.upToDate);
    });

    test(
      'Later remembers an optional release; a newer one prompts again',
      () async {
        final c = controller();
        await c.check();
        expect(await c.shouldPrompt(c.offer!), isTrue);
        await c.postpone();
        expect(await c.shouldPrompt(c.offer!), isFalse);
        server.manifest = manifestJson(payload(versionCode: 6));
        await c.check(manual: true);
        expect(await c.shouldPrompt(c.offer!), isTrue);
      },
    );

    test(
      'a required release prompts every time and is never remembered',
      () async {
        server.manifest = manifestJson(
          payload(override: {'minSupportedVersionCode': 4}),
        );
        final c = controller();
        await c.check();
        expect(c.offer!.mandatory, isTrue);
        await c.postpone();
        expect(prefs.dismissed, isNull);
        expect(await c.shouldPrompt(c.offer!), isTrue);
      },
    );

    test('Update now: verified download, then Android confirmation', () async {
      final c = controller();
      await c.check();
      await c.startUpdate();
      expect(c.phase, UpdatePhase.installing);
      expect(installer.installs.single, endsWith('dokan_pro_5.apk'));
      installer.emit(InstallStatus.cancelled);
      await pumpEventQueue();
      expect(c.phase, UpdatePhase.available);
      expect(c.failure, UpdateFailure.installCancelled);
      // Retry reuses the verified file (re-hashed), no second download.
      await c.startUpdate();
      expect(server.apkHits, 1);
      expect(installer.installs, hasLength(2));
    });

    test(
      '"Install unknown apps" not allowed: explains, does not download',
      () async {
        installer.canInstall = false;
        final c = controller();
        await c.check();
        await c.startUpdate();
        expect(c.phase, UpdatePhase.needsPermission);
        expect(server.apkHits, 0);
        await c.openInstallPermissionSettings();
        expect(installer.permissionScreens, [1]);
      },
    );

    test('corrupted APK (SHA-256 mismatch) is never installed', () async {
      server.apk = Uint8List.fromList(List.of(apkBytes)..[100] ^= 0xff);
      final c = controller();
      await c.check();
      await c.startUpdate();
      expect(c.failure, UpdateFailure.hashMismatch);
      expect(installer.installs, isEmpty);
    });

    test(
      'wrong package or foreign signer is never installed and is deleted',
      () async {
        installer.archive = const ApkArchive(
          packageName: 'com.evil',
          versionCode: 5,
          versionName: '',
          signerSha256: {releaseSigner},
          signerHistorySha256: {},
        );
        final c = controller();
        await c.check();
        await c.startUpdate();
        expect(c.failure, UpdateFailure.wrongPackage);
        expect(installer.installs, isEmpty);
        expect(
          File('${cache.path}/app_update/dokan_pro_5.apk').existsSync(),
          isFalse,
        );

        installer.archive = const ApkArchive(
          packageName: pkg,
          versionCode: 5,
          versionName: '',
          signerSha256: {'cc33'},
          signerHistorySha256: {'cc33'},
        );
        await c.startUpdate();
        expect(c.failure, UpdateFailure.signerMismatch);
        expect(installer.installs, isEmpty);
      },
    );

    test('installer failure is reported; the app keeps running', () async {
      installer.installResult = InstallStatus.storage;
      final c = controller();
      await c.check();
      await c.startUpdate();
      expect(c.phase, UpdatePhase.failed);
      expect(c.failure, UpdateFailure.installFailed);
    });

    test(
      'the update workflow leaves app preferences and local data untouched',
      () async {
        SharedPreferences.setMockInitialValues({
          'dukaan_pro.app_device_id.v1': '0192a3b4-c5d6-7e8f-9a0b-1c2d3e4f5a6b',
          'dukaan_pro.locale': 'ur',
        });
        File(
          '${cache.path}/dukaan_pro.sqlite',
        ).writeAsStringSync('unsynced sales');
        final c = UpdateController(
          config: config(),
          downloader: ApkDownloader(
            cacheDirectory: () async => cache,
            clientFactory: server.client,
          ),
          installer: installer,
          clientFactory: server.client,
          clock: () => now,
        );
        await c.check();
        await c.postpone();
        await c.check(manual: true);
        await c.startUpdate();
        final p = await SharedPreferences.getInstance();
        expect(
          p.getString('dukaan_pro.app_device_id.v1'),
          '0192a3b4-c5d6-7e8f-9a0b-1c2d3e4f5a6b',
        );
        expect(p.getString('dukaan_pro.locale'), 'ur');
        expect(
          p
              .getKeys()
              .where((k) => !k.startsWith('dokan_pro.app_update.'))
              .toSet(),
          {'dukaan_pro.app_device_id.v1', 'dukaan_pro.locale'},
        );
        expect(
          File('${cache.path}/dukaan_pro.sqlite').readAsStringSync(),
          'unsynced sales',
        );
      },
    );
  });

  group('dialog and host', () {
    late Directory cache;
    late Server server;
    late FakeInstaller installer;
    late MemoryPrefs prefs;
    setUp(() {
      cache = Directory.systemTemp.createTempSync('dokan_update_ui');
      server = Server(manifest: manifestJson(payload()));
      installer = FakeInstaller();
      prefs = MemoryPrefs();
    });
    tearDown(() {
      BillingActivity.report('cart', busy: false);
      cache.deleteSync(recursive: true);
    });

    UpdateController controller() => UpdateController(
      config: config(),
      downloader: ApkDownloader(
        cacheDirectory: () async => cache,
        clientFactory: server.client,
      ),
      installer: installer,
      preferences: prefs,
      clientFactory: server.client,
      clock: () => now,
    );

    Widget app(Widget home, {String locale = 'en'}) => MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

    Future<void> host(
      WidgetTester tester,
      UpdateController c, {
      String locale = 'en',
      bool Function()? busy,
    }) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          AppUpdateHost(
            controller: c,
            startupDelay: const Duration(milliseconds: 10),
            isBillingBusy: busy,
            busyRetry: const Duration(seconds: 1),
            child: const Scaffold(body: Text('POS')),
          ),
          locale: locale,
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await c.check(); // completes the startup check's network work
      });
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
    }

    for (final locale in ['en', 'ur']) {
      testWidgets('update dialog shows versions, size and notes ($locale)', (
        tester,
      ) async {
        final c = controller();
        await host(tester, c, locale: locale);
        final l10n = lookupAppLocalizations(Locale(locale));
        expect(find.text(l10n.updateTitle), findsOneWidget);
        expect(find.text(l10n.updateInstalledVersion('1.0.3')), findsOneWidget);
        expect(find.text(l10n.updateNewVersion('1.0.5')), findsOneWidget);
        expect(find.text(l10n.updateDownloadSize('2.0 MB')), findsOneWidget);
        expect(
          find.textContaining(locale == 'ur' ? 'بلنگ' : 'billing'),
          findsOneWidget,
        );
        expect(find.text(l10n.updateNow), findsOneWidget);
        expect(find.text(l10n.updateLater), findsOneWidget);
        final dir = Directionality.of(
          tester.element(find.text(l10n.updateTitle)),
        );
        expect(dir, locale == 'ur' ? TextDirection.rtl : TextDirection.ltr);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'Later closes and is remembered; foreground does not re-prompt',
      (tester) async {
        final c = controller();
        await host(tester, c);
        await tester.tap(find.text('Later'));
        await tester.pumpAndSettle();
        expect(find.byType(AppUpdateDialog), findsNothing);
        expect(prefs.dismissed, 5);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppUpdateDialog), findsNothing);
      },
    );

    testWidgets('one dialog at a time, even when checks repeat', (
      tester,
    ) async {
      final c = controller();
      await host(tester, c);
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(AppUpdateDialog), findsOneWidget);
    });

    testWidgets(
      'required update: no Later, but Continue keeps billing available',
      (tester) async {
        server.manifest = manifestJson(
          payload(override: {'forceUpdate': true}),
        );
        final c = controller();
        await host(tester, c);
        expect(find.text('Dokan Pro update required'), findsOneWidget);
        expect(find.text('Later'), findsNothing);
        await tester.tap(find.text('Continue for now'));
        await tester.pumpAndSettle();
        expect(find.text('POS'), findsOneWidget);
        expect(find.byType(AppUpdateDialog), findsNothing);
      },
    );

    testWidgets('waits while a sale is being built', (tester) async {
      var busy = true;
      final c = controller();
      await host(tester, c, busy: () => busy);
      expect(find.byType(AppUpdateDialog), findsNothing);
      busy = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdateDialog), findsOneWidget);
    });

    testWidgets('signer mismatch shows a safe error and installs nothing', (
      tester,
    ) async {
      installer.archive = const ApkArchive(
        packageName: pkg,
        versionCode: 5,
        versionName: '',
        signerSha256: {'cc33'},
        signerHistorySha256: {'cc33'},
      );
      final c = controller();
      await host(tester, c);
      await tester.runAsync(() async {
        await c.startUpdate();
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('not signed by Dokan Pro'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(installer.installs, isEmpty);
    });
  });
}

Uint8List _bytes(BigInt v) {
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
