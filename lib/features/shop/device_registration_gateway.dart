import 'package:flutter/foundation.dart';
import '../../core/domain/enums.dart';

final class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.isActive,
    this.approvalStatus = 'approved',
  });
  final String id;
  final bool isActive;

  /// approved | pending | rejected | revoked (two-device rule). Servers
  /// before migration 202610140001 report none: active means approved.
  final String approvalStatus;
  bool get awaitingApproval => approvalStatus == 'pending';
  bool get rejected => approvalStatus == 'rejected';
}

/// Shortest screen side, in logical pixels, from which an Android device is
/// registered as a tablet (Material's compact/medium breakpoint).
const tabletShortestSide = 600.0;

/// The device type sent at first registration. The server keeps it as the
/// device's mobile/tablet slot and the owner cannot change it later; support
/// can correct it. Android is classified by screen size, not by a label the
/// user picks.
DeviceType classifyDeviceType({
  required bool isWeb,
  required TargetPlatform platform,
  required double shortestSide,
}) {
  if (isWeb) return DeviceType.mobile;
  return switch (platform) {
    TargetPlatform.windows => DeviceType.windowsDesktop,
    TargetPlatform.android || TargetPlatform.iOS =>
      shortestSide >= tabletShortestSide
          ? DeviceType.androidTablet
          : DeviceType.mobile,
    _ => DeviceType.mobile,
  };
}

abstract interface class DeviceRegistrationGateway {
  Future<RegisteredDevice> register({
    required String shopId,
    required String deviceName,
    required DeviceType type,
    required String identifier,
  });
  Future<RegisteredDevice?> find({
    required String shopId,
    required String identifier,
  });
}
