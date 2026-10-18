import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apk_downloader.dart';
import 'apk_installer.dart';
import 'update_config.dart';
import 'update_manifest.dart';

/// Remembers when updates were last checked and which optional release the
/// user postponed. Own keys only; nothing else in preferences is touched.
abstract interface class UpdatePreferences {
  Future<DateTime?> lastCheck();
  Future<void> setLastCheck(DateTime at);
  Future<int?> dismissedVersionCode();
  Future<void> setDismissedVersionCode(int code);
}

final class SharedPreferencesUpdatePreferences implements UpdatePreferences {
  const SharedPreferencesUpdatePreferences();
  static const _lastCheck = 'dokan_pro.app_update.last_check_ms';
  static const _dismissed = 'dokan_pro.app_update.dismissed_version_code';

  @override
  Future<DateTime?> lastCheck() async {
    final ms = (await SharedPreferences.getInstance()).getInt(_lastCheck);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> setLastCheck(DateTime at) async =>
      (await SharedPreferences.getInstance()).setInt(
        _lastCheck,
        at.toUtc().millisecondsSinceEpoch,
      );

  @override
  Future<int?> dismissedVersionCode() async =>
      (await SharedPreferences.getInstance()).getInt(_dismissed);

  @override
  Future<void> setDismissedVersionCode(int code) async =>
      (await SharedPreferences.getInstance()).setInt(_dismissed, code);
}

/// A verified newer release for this installation.
final class UpdateOffer {
  const UpdateOffer({required this.manifest, required this.installed});
  final UpdateManifest manifest;
  final InstalledApp installed;

  /// The signed manifest marks it required (forceUpdate or the installed
  /// version is below minSupportedVersionCode). The prompt then has no
  /// "Later", but offline billing and unsynced records stay reachable: a
  /// manifest never locks the shop out.
  bool get mandatory => manifest.requiredFor(installed.versionCode);
}

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  needsPermission,
  downloading,
  verifying,
  installing,
  failed,
}

enum UpdateFailure {
  offline,
  manifestInvalid,
  download,
  hashMismatch,
  wrongPackage,
  notNewer,
  signerMismatch,
  installCancelled,
  installFailed,
  unsupported,
}

typedef CheckResult = ({UpdateOffer? offer, bool checked});

/// Orchestrates update checks, download, verification and install.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.config,
    required this.downloader,
    required this.installer,
    UpdatePreferences? preferences,
    http.Client Function()? clientFactory,
    DateTime Function()? clock,
    this.autoCheckInterval = const Duration(hours: 6),
    this.manifestTimeout = const Duration(seconds: 15),
  }) : preferences = preferences ?? const SharedPreferencesUpdatePreferences(),
       _clientFactory = clientFactory ?? http.Client.new,
       _clock = clock ?? DateTime.now {
    _installSub = installer.statuses.listen(_onInstallStatus);
  }

  /// Built from `--dart-define`s; null (feature off) when not configured or
  /// not running on Android.
  static UpdateController? fromEnvironment() {
    final config = UpdateConfig.fromEnvironment();
    if (config == null || kIsWeb || !Platform.isAndroid) return null;
    return UpdateController(
      config: config,
      // Android's app cache dir; MainActivity only installs from
      // <cacheDir>/app_update.
      downloader: ApkDownloader(cacheDirectory: getApplicationCacheDirectory),
      installer: AndroidApkInstaller(),
    );
  }

  final UpdateConfig config;
  final ApkDownloader downloader;
  final ApkInstaller installer;
  final UpdatePreferences preferences;
  final http.Client Function() _clientFactory;
  final DateTime Function() _clock;
  final Duration autoCheckInterval, manifestTimeout;
  late final StreamSubscription<InstallStatus> _installSub;

  static const _maxManifestBytes = 64 * 1024;

  UpdatePhase phase = UpdatePhase.idle;
  UpdateFailure? failure;
  UpdateOffer? offer;
  int received = 0, total = 0;
  DownloadCancelToken? _cancel;
  File? _apk;
  bool _checking = false;

  void _set(UpdatePhase p, {UpdateFailure? fail}) {
    phase = p;
    failure = fail;
    notifyListeners();
  }

  /// Fetches and verifies the manifest. Automatic checks are throttled to
  /// [autoCheckInterval]; [manual] always checks. Never throws: offline or
  /// broken manifests just mean "no update".
  Future<CheckResult> check({bool manual = false}) async {
    if (_checking || _busy) return (offer: offer, checked: false);
    final now = _clock().toUtc();
    if (!manual) {
      final last = await preferences.lastCheck();
      if (last != null && now.difference(last) < autoCheckInterval) {
        return (offer: offer, checked: false);
      }
    }
    _checking = true;
    if (manual) _set(UpdatePhase.checking);
    try {
      final manifest = await _fetchManifest(now);
      await preferences.setLastCheck(now);
      final installed = await installer.installedApp();
      if (installed.packageName != config.packageName ||
          manifest.versionCode <= installed.versionCode) {
        offer = null;
        _set(UpdatePhase.upToDate);
        return (offer: null, checked: true);
      }
      offer = UpdateOffer(manifest: manifest, installed: installed);
      _set(UpdatePhase.available);
      return (offer: offer, checked: true);
    } on UpdateManifestException {
      _set(
        manual ? UpdatePhase.failed : UpdatePhase.idle,
        fail: UpdateFailure.manifestInvalid,
      );
      return (offer: null, checked: false);
    } catch (_) {
      _set(
        manual ? UpdatePhase.failed : UpdatePhase.idle,
        fail: UpdateFailure.offline,
      );
      return (offer: null, checked: false);
    } finally {
      _checking = false;
    }
  }

  bool get _busy => const {
    UpdatePhase.downloading,
    UpdatePhase.verifying,
    UpdatePhase.installing,
  }.contains(phase);

  Future<UpdateManifest> _fetchManifest(DateTime now) async {
    final client = _clientFactory();
    try {
      final response = await client
          .get(config.manifestUrl, headers: const {'Cache-Control': 'no-cache'})
          .timeout(manifestTimeout);
      if (response.statusCode != 200) throw const HttpException('manifest');
      if (response.bodyBytes.length > _maxManifestBytes) {
        throw const UpdateManifestException('manifest too large');
      }
      return UpdateManifestParser(
        publicKey: config.publicKey,
        allowedHosts: config.allowedHosts,
        packageName: config.packageName,
      ).parse(utf8.decode(response.bodyBytes), now: now);
    } finally {
      client.close();
    }
  }

  /// Whether the prompt should appear for [o] (optional releases the user
  /// postponed stay quiet until a newer one is published).
  Future<bool> shouldPrompt(UpdateOffer o) async =>
      o.mandatory ||
      await preferences.dismissedVersionCode() != o.manifest.versionCode;

  /// "Later". Mandatory releases are not remembered, so they ask again.
  Future<void> postpone() async {
    final o = offer;
    if (o != null && !o.mandatory) {
      await preferences.setDismissedVersionCode(o.manifest.versionCode);
    }
    if (!_busy) _set(UpdatePhase.available);
  }

  /// "Update now": permission → download → verify → inspect → install.
  Future<void> startUpdate() async {
    final o = offer;
    if (o == null || _busy) return;
    final InstalledApp installed;
    try {
      installed = await installer.installedApp();
    } catch (_) {
      return _set(UpdatePhase.failed, fail: UpdateFailure.unsupported);
    }
    if (!installed.canRequestInstalls) {
      return _set(UpdatePhase.needsPermission);
    }
    _cancel = DownloadCancelToken();
    received = 0;
    total = o.manifest.apkSizeBytes;
    _set(UpdatePhase.downloading);
    File apk;
    try {
      await downloader.cleanObsolete(keepVersionCode: o.manifest.versionCode);
      apk =
          await downloader.verifiedExisting(o.manifest) ??
          await downloader.download(
            o.manifest,
            cancel: _cancel,
            onProgress: (r, t) {
              received = r;
              total = t;
              notifyListeners();
            },
          );
    } on ApkDownloadException catch (e) {
      if (e.failure == DownloadFailure.cancelled) {
        return _set(UpdatePhase.available);
      }
      return _set(
        UpdatePhase.failed,
        fail:
            e.failure == DownloadFailure.hashMismatch ||
                e.failure == DownloadFailure.sizeMismatch
            ? UpdateFailure.hashMismatch
            : UpdateFailure.download,
      );
    }
    _set(UpdatePhase.verifying);
    final ApkRejection? rejection;
    try {
      rejection = checkApkCompatibility(
        installed: installed,
        archive: await installer.inspect(apk.path),
        expectedVersionCode: o.manifest.versionCode,
      );
    } catch (_) {
      await _discard(apk);
      return _set(UpdatePhase.failed, fail: UpdateFailure.wrongPackage);
    }
    if (rejection != null) {
      await _discard(apk);
      return _set(
        UpdatePhase.failed,
        fail: switch (rejection) {
          ApkRejection.wrongPackage ||
          ApkRejection.versionMismatch => UpdateFailure.wrongPackage,
          ApkRejection.notNewer => UpdateFailure.notNewer,
          ApkRejection.signerMismatch => UpdateFailure.signerMismatch,
        },
      );
    }
    _apk = apk;
    _set(UpdatePhase.installing);
    try {
      _onInstallStatus(await installer.install(apk.path));
    } catch (_) {
      _set(UpdatePhase.failed, fail: UpdateFailure.installFailed);
    }
  }

  void _onInstallStatus(InstallStatus s) {
    switch (s) {
      case InstallStatus.userConfirming:
        if (phase != UpdatePhase.installing) _set(UpdatePhase.installing);
      case InstallStatus.success:
        // Android replaces and restarts the app; usually never observed.
        _set(UpdatePhase.idle);
      case InstallStatus.cancelled:
        _set(UpdatePhase.available, fail: UpdateFailure.installCancelled);
      case InstallStatus.incompatible ||
          InstallStatus.conflict ||
          InstallStatus.invalid:
        _set(UpdatePhase.failed, fail: UpdateFailure.signerMismatch);
      case InstallStatus.blocked ||
          InstallStatus.storage ||
          InstallStatus.failed:
        _set(UpdatePhase.failed, fail: UpdateFailure.installFailed);
    }
  }

  /// Cancels a download in progress. Nothing else is affected.
  void cancelDownload() => _cancel?.cancel();

  Future<void> openInstallPermissionSettings() =>
      installer.openInstallPermissionSettings();

  Future<void> _discard(File apk) async {
    try {
      if (await apk.exists()) await apk.delete();
    } catch (_) {}
  }

  /// Path of the verified APK awaiting install (for diagnostics/tests).
  String? get verifiedApkPath => _apk?.path;

  @override
  void dispose() {
    _installSub.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}
