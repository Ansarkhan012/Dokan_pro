import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'product_display_names.dart';

/// State of the on-device English and Urdu translation models.
enum TranslationModelStatus {
  /// Not an Android device (Windows counter, web): no ML Kit.
  unsupported,
  checking,
  notDownloaded,
  downloading,
  ready,
  failed,
}

/// The platform side of on-device translation; replaced in tests.
abstract interface class TranslationModelBackend {
  bool get isSupported;
  Future<bool> isModelDownloaded(String languageCode);

  /// Downloads one model. Returns true when it is on the device.
  Future<bool> downloadModel(String languageCode, {required bool wifiOnly});

  /// English to Urdu. Only called once both models are on the device.
  Future<String> translate(String text);

  /// Releases the native translator; a later [translate] reopens it.
  Future<void> close();
}

/// Google ML Kit on-device translation (`google_mlkit_translation`).
final class MlKitTranslationBackend implements TranslationModelBackend {
  MlKitTranslationBackend();

  final _models = OnDeviceTranslatorModelManager();
  OnDeviceTranslator? _translator;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isModelDownloaded(String languageCode) =>
      _models.isModelDownloaded(languageCode);

  @override
  Future<bool> downloadModel(String languageCode, {required bool wifiOnly}) =>
      _models.downloadModel(languageCode, isWifiRequired: wifiOnly);

  @override
  Future<String> translate(String text) => (_translator ??= OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.english,
    targetLanguage: TranslateLanguage.urdu,
  )).translateText(text);

  @override
  Future<void> close() async {
    final translator = _translator;
    _translator = null;
    await translator?.close();
  }
}

const _english = 'en';
const _urdu = 'ur';

/// Offline English-to-Urdu product name translation with ML Kit.
///
/// Models are only downloaded by [downloadModels], which the owner starts
/// from Settings; startup only checks whether they exist. Before each
/// batch the models are checked again, because the plugin's translate call
/// would otherwise download a missing model by itself.
final class OfflineUrduTranslation extends ChangeNotifier
    implements ProductTranslationService {
  OfflineUrduTranslation({
    TranslationModelBackend? backend,
    this.concurrency = 2,
    this.downloadTimeout = const Duration(minutes: 10),
    this.idleClose = const Duration(minutes: 1),
  }) : backend = backend ?? MlKitTranslationBackend(),
       _status = TranslationModelStatus.checking;

  final TranslationModelBackend backend;

  /// Names translated at the same time.
  final int concurrency;
  final Duration downloadTimeout;

  /// The native translator is closed after this long without work.
  final Duration idleClose;

  TranslationModelStatus _status;
  TranslationModelStatus get status => _status;
  Timer? _idleTimer;
  bool _disposed = false;

  @override
  bool get isConfigured => _status == TranslationModelStatus.ready;

  void _set(TranslationModelStatus status) {
    if (_disposed || status == _status) return;
    _status = status;
    notifyListeners();
  }

  /// Whether both models are on the device. Never downloads.
  Future<void> checkModels() async {
    if (!backend.isSupported) return _set(TranslationModelStatus.unsupported);
    if (_status == TranslationModelStatus.downloading) return;
    try {
      _set(
        await _modelsPresent()
            ? TranslationModelStatus.ready
            : TranslationModelStatus.notDownloaded,
      );
    } on MissingPluginException {
      _set(TranslationModelStatus.unsupported);
    } catch (_) {
      _set(TranslationModelStatus.notDownloaded);
    }
  }

  Future<bool> _modelsPresent() async =>
      await backend.isModelDownloaded(_english) &&
      await backend.isModelDownloaded(_urdu);

  /// Downloads whichever of the English and Urdu models is missing. Only
  /// called when the owner taps the download button. Returns whether the
  /// models are ready.
  Future<bool> downloadModels({bool wifiOnly = true}) async {
    if (!backend.isSupported) {
      _set(TranslationModelStatus.unsupported);
      return false;
    }
    if (_status == TranslationModelStatus.downloading) return false;
    if (_status == TranslationModelStatus.ready) return true;
    _set(TranslationModelStatus.downloading);
    try {
      for (final code in const [_english, _urdu]) {
        if (await backend.isModelDownloaded(code)) continue;
        await backend
            .downloadModel(code, wifiOnly: wifiOnly)
            .timeout(downloadTimeout);
      }
      final ready = await _modelsPresent();
      _set(
        ready ? TranslationModelStatus.ready : TranslationModelStatus.failed,
      );
      return ready;
    } on MissingPluginException {
      _set(TranslationModelStatus.unsupported);
      return false;
    } catch (_) {
      _set(TranslationModelStatus.failed);
      return false;
    }
  }

  @override
  Future<Map<String, String>> translate(
    List<String> names, {
    required String languageCode,
  }) async {
    if (languageCode != _urdu || !isConfigured) {
      throw StateError('Urdu translation models are not ready');
    }
    if (names.isEmpty) return const {};
    _idleTimer?.cancel();
    try {
      // Never let the plugin download a model that was removed meanwhile.
      if (!await _modelsPresent()) {
        _set(TranslationModelStatus.notDownloaded);
        throw StateError('Urdu translation models are not downloaded');
      }
      final out = <String, String>{};
      final queue = [...names];
      Future<void> worker() async {
        while (queue.isNotEmpty && !_disposed) {
          final name = queue.removeLast();
          try {
            if (await translateProductName(name, backend.translate)
                case final urdu?) {
              out[name] = urdu;
            }
          } catch (_) {
            // This name stays in English; the others continue.
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < concurrency.clamp(1, names.length); i++) worker(),
      ]);
      return out;
    } finally {
      _idleTimer = Timer(idleClose, () => unawaited(backend.close()));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    unawaited(backend.close());
    super.dispose();
  }
}

const _units = {
  'kg', 'kgs', 'g', 'gm', 'gms', 'gram', 'grams', 'mg', 'ml', 'l', 'ltr', //
  'litre', 'litres', 'liter', 'liters', 'pc', 'pcs', 'pack', 'packs', 'x',
};
final _digit = RegExp(r'\d');

/// Translates [name] with [translate], keeping sizes and counts exactly as
/// entered: tokens with digits (and the unit after a number) are taken out,
/// the remaining words are translated, and the sizes are appended in their
/// original order. Returns null when there is nothing to translate or the
/// engine gives nothing new.
Future<String?> translateProductName(
  String name,
  Future<String> Function(String text) translate,
) async {
  final words = <String>[];
  final measures = <String>[];
  final tokens = name.trim().split(RegExp(r'\s+'));
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final next = i + 1 < tokens.length ? tokens[i + 1] : null;
    if ((token.toLowerCase() == 'x' || token == '×') &&
        next != null &&
        _digit.hasMatch(next)) {
      // A pack count such as `x 2`.
      measures.add('$token $next');
      i++;
    } else if (_digit.hasMatch(token)) {
      if (next != null && _units.contains(next.toLowerCase())) {
        measures.add('$token $next');
        i++;
      } else {
        measures.add(token);
      }
    } else if (token.isNotEmpty) {
      words.add(token);
    }
  }
  if (words.isEmpty) return null;
  final text = words.join(' ');
  final urdu = (await translate(text)).trim();
  if (urdu.isEmpty || urdu.toLowerCase() == text.toLowerCase()) return null;
  return [urdu, ...measures].join(' ');
}
