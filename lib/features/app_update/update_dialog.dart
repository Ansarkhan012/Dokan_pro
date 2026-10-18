import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/ui/pos_ui.dart';
import 'update_controller.dart';

/// "45.2 MB" (Latin digits, as for prices on receipts).
String formatDownloadSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

String updateFailureText(AppLocalizations l10n, UpdateFailure f) => switch (f) {
  UpdateFailure.offline => l10n.updateErrOffline,
  UpdateFailure.manifestInvalid => l10n.updateErrManifest,
  UpdateFailure.download => l10n.updateErrDownload,
  UpdateFailure.hashMismatch => l10n.updateErrCorrupt,
  UpdateFailure.wrongPackage || UpdateFailure.notNewer => l10n.updateErrPackage,
  UpdateFailure.signerMismatch => l10n.updateErrSigner,
  UpdateFailure.installCancelled => l10n.updateInstallCancelled,
  UpdateFailure.installFailed ||
  UpdateFailure.unsupported => l10n.updateErrInstall,
};

/// The update prompt. It follows [controller]: offer → permission →
/// download progress → verification → Android's install confirmation, with
/// cancel/retry. Nothing here can stop billing: a required update hides
/// "Later" but always offers "Continue for now".
class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({super.key, required this.controller});
  final UpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l10n = context.l10n;
      final offer = controller.offer;
      final theme = Theme.of(context);
      if (offer == null) {
        return PosFormDialog(
          title: l10n.updateCheckNow,
          maxWidth: 520,
          body: (_, _) => Text(
            controller.failure == null
                ? l10n.updateUpToDate
                : updateFailureText(l10n, controller.failure!),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.updateClose),
            ),
          ],
        );
      }
      final m = offer.manifest;
      final phase = controller.phase;
      final locked =
          phase == UpdatePhase.downloading || phase == UpdatePhase.verifying;
      void close() => Navigator.of(context).pop();

      final status = switch (phase) {
        UpdatePhase.downloading => _Progress(
          label: l10n.updateDownloading(
            '${controller.total == 0 ? 0 : (controller.received * 100 ~/ controller.total).clamp(0, 100)}',
          ),
          value: controller.total == 0
              ? null
              : controller.received / controller.total,
        ),
        UpdatePhase.verifying => _Progress(
          label: l10n.updateVerifying,
          value: null,
        ),
        UpdatePhase.installing => _Note(
          l10n.updateInstalling,
          icon: Icons.system_update_alt,
          tone: StatusTone.info,
        ),
        UpdatePhase.needsPermission => _Note(
          '${l10n.updatePermissionTitle}\n${l10n.updatePermissionBody}',
          icon: Icons.security,
          tone: StatusTone.warning,
        ),
        _ when controller.failure != null => _Note(
          updateFailureText(l10n, controller.failure!),
          icon: Icons.error_outline,
          tone: controller.failure == UpdateFailure.installCancelled
              ? StatusTone.neutral
              : StatusTone.danger,
        ),
        _ => null,
      };

      final actions = <Widget>[
        if (phase == UpdatePhase.downloading)
          OutlinedButton(
            onPressed: controller.cancelDownload,
            child: Text(l10n.updateCancel),
          )
        else if (!locked) ...[
          TextButton(
            onPressed: () async {
              await controller.postpone();
              close();
            },
            child: Text(
              offer.mandatory ? l10n.updateContinue : l10n.updateLater,
            ),
          ),
          if (phase == UpdatePhase.needsPermission)
            OutlinedButton(
              onPressed: controller.openInstallPermissionSettings,
              child: Text(l10n.updateOpenSettings),
            ),
          if (phase != UpdatePhase.installing)
            FilledButton.icon(
              onPressed: controller.startUpdate,
              icon: const Icon(Icons.download),
              label: Text(
                phase == UpdatePhase.failed ? l10n.updateRetry : l10n.updateNow,
              ),
            ),
        ],
      ];

      return PosFormDialog(
        title: offer.mandatory ? l10n.updateRequiredTitle : l10n.updateTitle,
        maxWidth: 560,
        locked: locked,
        body: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(l10n.updateInstalledVersion(offer.installed.versionName)),
                Text(
                  l10n.updateNewVersion(m.versionName),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  l10n.updateDownloadSize(formatDownloadSize(m.apkSizeBytes)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSectionLabel(l10n.updateWhatsNew),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  m.releaseNotesFor(
                    Localizations.localeOf(context).languageCode,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              offer.mandatory ? l10n.updateRequiredNote : l10n.updateDataSafe,
              style: theme.textTheme.bodySmall?.copyWith(color: posMuted),
            ),
            if (status != null) ...[const SizedBox(height: 16), status],
          ],
        ),
        actions: actions,
      );
    },
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label, required this.value});
  final String label;
  final double? value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value, minHeight: 8),
      ),
    ],
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.icon, required this.tone});
  final String text;
  final IconData icon;
  final StatusTone tone;
  @override
  Widget build(BuildContext context) {
    final color = StatusPill.colorFor(tone);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
