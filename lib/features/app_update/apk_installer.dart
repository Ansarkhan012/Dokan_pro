import 'dart:async';

import 'package:flutter/services.dart';

/// The installed app as Android reports it.
final class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.signerSha256,
    required this.canRequestInstalls,
  });
  final String packageName, versionName;
  final int versionCode;

  /// SHA-256 of the current signing certificate(s), lower-case hex.
  final Set<String> signerSha256;

  /// Android 8+: "Install unknown apps" allowed for Dokan Pro.
  final bool canRequestInstalls;
}

/// A downloaded APK as Android parses it (PackageManager archive info).
final class ApkArchive {
  const ApkArchive({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.signerSha256,
    required this.signerHistorySha256,
  });
  final String packageName, versionName;
  final int versionCode;
  final Set<String> signerSha256;

  /// Current plus past signers from the APK's v3 rotation lineage (empty
  /// when Android cannot report it).
  final Set<String> signerHistorySha256;
}

/// Outcome reported by the platform installer.
enum InstallStatus {
  userConfirming,
  success,
  cancelled,
  blocked,
  conflict,
  incompatible,
  storage,
  invalid,
  failed,
}

/// Why an APK must not be installed (checked before Android is asked).
enum ApkRejection { wrongPackage, notNewer, versionMismatch, signerMismatch }

/// Pure compatibility rules, testable without a device.
ApkRejection? checkApkCompatibility({
  required InstalledApp installed,
  required ApkArchive archive,
  required int expectedVersionCode,
}) {
  if (archive.packageName != installed.packageName) {
    return ApkRejection.wrongPackage;
  }
  if (archive.versionCode != expectedVersionCode) {
    return ApkRejection.versionMismatch;
  }
  if (archive.versionCode <= installed.versionCode) {
    return ApkRejection.notNewer;
  }
  // Same key, or a rotated key whose lineage includes the installed key
  // (docs/release-signing.md: debug -> release). When Android reports no
  // signer at all we cannot tell; Android still refuses an incompatible
  // signature at install time without touching the installed app.
  final known = {...archive.signerSha256, ...archive.signerHistorySha256};
  if (known.isNotEmpty &&
      installed.signerSha256.isNotEmpty &&
      installed.signerSha256.intersection(known).isEmpty) {
    return ApkRejection.signerMismatch;
  }
  return null;
}

abstract interface class ApkInstaller {
  Future<InstalledApp> installedApp();
  Future<ApkArchive> inspect(String apkPath);

  /// Opens Android's "Install unknown apps" screen for Dokan Pro.
  Future<void> openInstallPermissionSettings();

  /// Starts a PackageInstaller session; Android shows its own confirmation.
  /// Completes with the first status (usually [InstallStatus.userConfirming]);
  /// later statuses arrive on [statuses]. On success Android restarts the
  /// app as the new version with its data intact.
  Future<InstallStatus> install(String apkPath);
  Stream<InstallStatus> get statuses;
}

/// MethodChannel implementation backed by MainActivity (Kotlin).
final class AndroidApkInstaller implements ApkInstaller {
  AndroidApkInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installStatus') {
        _statuses.add(_status(call.arguments as String?));
      }
    });
  }

  static const channelName = 'com.dukaanpro.dukaan_pro/app_update';
  final MethodChannel _channel;
  final _statuses = StreamController<InstallStatus>.broadcast();

  @override
  Stream<InstallStatus> get statuses => _statuses.stream;

  static Set<String> _set(Object? v) => {
    for (final x in (v as List? ?? const [])) (x as String).toLowerCase(),
  };

  @override
  Future<InstalledApp> installedApp() async {
    final m = Map<String, Object?>.from(
      await _channel.invokeMethod<Map>('installedApp') ?? const {},
    );
    return InstalledApp(
      packageName: m['packageName'] as String,
      versionCode: (m['versionCode'] as num).toInt(),
      versionName: m['versionName'] as String? ?? '',
      signerSha256: _set(m['signers']),
      canRequestInstalls: m['canRequestInstalls'] as bool? ?? false,
    );
  }

  @override
  Future<ApkArchive> inspect(String apkPath) async {
    final m = Map<String, Object?>.from(
      await _channel.invokeMethod<Map>('inspectApk', {'path': apkPath}) ??
          const {},
    );
    return ApkArchive(
      packageName: m['packageName'] as String? ?? '',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      versionName: m['versionName'] as String? ?? '',
      signerSha256: _set(m['signers']),
      signerHistorySha256: _set(m['signerHistory']),
    );
  }

  @override
  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod('openInstallPermissionSettings');

  @override
  Future<InstallStatus> install(String apkPath) async => _status(
    await _channel.invokeMethod<String>('install', {'path': apkPath}),
  );

  static InstallStatus _status(String? s) => InstallStatus.values.firstWhere(
    (v) => v.name == s,
    orElse: () => InstallStatus.failed,
  );
}
