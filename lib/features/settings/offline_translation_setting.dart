import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/l10n/offline_urdu_translation.dart';
import '../../core/l10n/product_names.dart';
import '../../core/ui/pos_ui.dart';

/// Settings: the on-device Urdu translation models. Downloads only start
/// from the button here, after the owner confirms.
class OfflineTranslationSetting extends StatelessWidget {
  const OfflineTranslationSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final engine = ProductNamesScope.of(context).service;
    if (engine is! OfflineUrduTranslation) {
      return Text(l10n.offlineTranslationUnsupported);
    }
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final status = engine.status;
        const muted = TextStyle(color: posMuted, fontSize: 12);
        return Column(
          key: ValueKey('offline-translation-${status.name}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switch (status) {
              TranslationModelStatus.unsupported => Text(
                l10n.offlineTranslationUnsupported,
              ),
              TranslationModelStatus.checking => Text(
                l10n.offlineTranslationChecking,
              ),
              TranslationModelStatus.notDownloaded => Text(
                l10n.offlineTranslationNotDownloaded,
              ),
              TranslationModelStatus.downloading => Text(
                l10n.offlineTranslationDownloading,
              ),
              TranslationModelStatus.ready => Text(
                l10n.offlineTranslationReady,
              ),
              TranslationModelStatus.failed => Text(
                l10n.offlineTranslationFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            },
            if (status == TranslationModelStatus.downloading) ...[
              const SizedBox(height: 8),
              // ML Kit reports no download percentage.
              const LinearProgressIndicator(),
            ],
            if (status == TranslationModelStatus.notDownloaded ||
                status == TranslationModelStatus.failed) ...[
              const SizedBox(height: 6),
              Text(l10n.offlineTranslationSize, style: muted),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('offline-translation-download'),
                    onPressed: () => _download(context, engine),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(
                      status == TranslationModelStatus.failed
                          ? l10n.offlineTranslationRetry
                          : l10n.offlineTranslationDownload,
                    ),
                  ),
                  if (status == TranslationModelStatus.failed)
                    OutlinedButton(
                      key: const ValueKey('offline-translation-mobile-data'),
                      onPressed: () =>
                          _download(context, engine, wifiOnly: false),
                      child: Text(l10n.offlineTranslationUseMobileData),
                    ),
                ],
              ),
            ],
            if (status == TranslationModelStatus.ready) ...[
              const SizedBox(height: 6),
              Text(l10n.offlineTranslationMachineNote, style: muted),
            ],
          ],
        );
      },
    );
  }

  Future<void> _download(
    BuildContext context,
    OfflineUrduTranslation engine, {
    bool wifiOnly = true,
  }) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.offlineTranslationConfirmTitle),
        content: Text(l10n.offlineTranslationSize),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('offline-translation-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.offlineTranslationConfirmDownload),
          ),
        ],
      ),
    );
    if (confirmed == true) await engine.downloadModels(wifiOnly: wifiOnly);
  }
}
