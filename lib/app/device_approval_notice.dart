import 'package:flutter/material.dart';

import '../core/device/device_code.dart';
import '../core/l10n/l10n.dart';

/// Shown while this device's registration waits for Dokan Pro Support, for
/// example after an uninstall/reinstall or cleared app data made a new device
/// identity in a shop whose slots are taken. The server decides; this only
/// explains it, shows the code support needs to pick the right registration,
/// and lets the owner re-check after support approves (no restart needed).
class DeviceApprovalPendingNotice extends StatelessWidget {
  const DeviceApprovalPendingNotice({
    super.key,
    required this.deviceId,
    required this.onCheckAgain,
    this.checking = false,
  });

  final String deviceId;
  final VoidCallback onCheckAgain;
  final bool checking;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(context.l10n.deviceApprovalPending),
      const SizedBox(height: 8),
      SelectableText(
        context.l10n.deviceApprovalCode(deviceCode(deviceId)),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: checking ? null : onCheckAgain,
        icon: const Icon(Icons.refresh),
        label: Text(context.l10n.deviceApprovalCheckAgain),
      ),
    ],
  );
}
