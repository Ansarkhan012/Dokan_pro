import 'package:flutter/widgets.dart';

/// Provided by the native CashierResumeGate: how owner screens hand the
/// device over to cashier mode. Absent in the web preview.
class DeviceModeScope extends InheritedWidget {
  const DeviceModeScope({
    super.key,
    required this.startCashierMode,
    required this.reload,
    required super.child,
  });

  /// Removes the owner session (verified) and opens the cashier session that
  /// was just stored for [cashierName]. Call only after the device credential
  /// is provisioned and owner mode is locked.
  final void Function(String cashierName) startCashierMode;

  /// Re-reads the device state, e.g. after a full owner sign-out.
  final VoidCallback reload;

  static DeviceModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeviceModeScope>();

  @override
  bool updateShouldNotify(DeviceModeScope oldWidget) => false;
}
