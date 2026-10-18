import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Urdu display names for products.
///
/// Stored product names (SQLite, Supabase, sale snapshots) always stay in
/// English; this only changes what a screen shows. In Urdu a name resolves,
/// in order, to:
///   1. the owner's manual correction for that product,
///   2. a cached machine translation for exactly this product and name,
///   3. the original English name.
/// English always shows the original name.
///
/// Machine translation needs an on-device [ProductTranslationService]. None
/// is installed yet ([UnconfiguredProductTranslationService]), so names stay
/// in English in Urdu mode until an owner enters a correction.

final _apostrophes = RegExp('[\'’‘`´]');
// A `.` or `,` that is not inside a number (so `1.5 L` stays `1.5 l`).
final _looseStops = RegExp(r'(?<!\d)[.,]|[.,](?!\d)');
final _openParen = RegExp(r'\s*\(\s*');
final _closeParen = RegExp(r'\s*\)');
final _spaces = RegExp(r'\s+');
// Directional isolates/marks and zero-width joiners a pasted name may carry.
final _invisible = RegExp('[\u200B-\u200F\u2066-\u2069\uFEFF]');
final _arabicScript = RegExp('[؀-ۿݐ-ݿﭐ-﷿ﹰ-\uFEFF]');

/// The lookup form of an English product name: case, spacing, apostrophes
/// and stray full stops/commas ignored. Digits, units and every other word
/// are kept, so sizes and variants stay distinct.
String normalizeProductName(String name) => name
    .replaceAll(_invisible, '')
    .toLowerCase()
    .replaceAll(_apostrophes, '')
    .replaceAll(_looseStops, ' ')
    .replaceAll(_openParen, ' (')
    .replaceAll(_closeParen, ')')
    .replaceAll(_spaces, ' ')
    .trim();

/// Urdu text as typed on different keyboards: Arabic yeh/kaf/heh folded to
/// their Urdu forms, invisible marks dropped, spacing collapsed.
String normalizeUrduText(String text) => text
    .replaceAll(_invisible, '')
    .replaceAll(RegExp('[يى]'), 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('ه', 'ہ')
    .replaceAll(_spaces, ' ')
    .trim();

/// Whether [query] contains Urdu (Arabic-script) letters.
bool hasUrduScript(String query) => _arabicScript.hasMatch(query);

/// Where a displayed name came from.
enum ProductNameSource { original, automatic, manual }

/// A product whose Urdu name may be requested.
typedef ProductNameRef = ({String productId, String name});

/// An offline, on-device English-to-Urdu translation engine (for example an
/// ML Kit or ONNX model shipped or downloaded to the device). Must never
/// call a cloud translation API or hold provider credentials.
abstract interface class ProductTranslationService {
  /// False until a real engine and its model are installed; nothing is
  /// requested then.
  bool get isConfigured;

  /// Translations of [names] (English source text) into [languageCode],
  /// keyed by the same source text. Missing keys mean "no translation".
  /// May throw or time out; the caller retries later.
  Future<Map<String, String>> translate(
    List<String> names, {
    required String languageCode,
  });
}

/// The default: no machine translation is available.
final class UnconfiguredProductTranslationService
    implements ProductTranslationService {
  const UnconfiguredProductTranslationService();
  @override
  bool get isConfigured => false;
  @override
  Future<Map<String, String>> translate(
    List<String> names, {
    required String languageCode,
  }) async => const {};
}

/// Device-local storage of translations, as one JSON document. Never part of
/// shop data, SQLite or sync.
abstract interface class ProductTranslationStore {
  Future<String?> read();
  Future<void> write(String json);
}

final class SharedPreferencesProductTranslationStore
    implements ProductTranslationStore {
  const SharedPreferencesProductTranslationStore();
  static const _key = 'product_display_names.v1';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);
  @override
  Future<void> write(String json) async {
    await (await SharedPreferences.getInstance()).setString(_key, json);
  }
}

/// For tests and the unconfigured shell: remembers nothing across runs.
final class MemoryProductTranslationStore implements ProductTranslationStore {
  MemoryProductTranslationStore([this.json]);
  String? json;
  @override
  Future<String?> read() async => json;
  @override
  Future<void> write(String json) async => this.json = json;
}

typedef _Manual = ({String source, String urdu});
typedef _Auto = ({String productId, String source, String text});

const _urdu = 'ur';

/// The shared resolver. Lookups are synchronous, in-memory map reads, so
/// widgets can call [resolve] on every build; nothing is translated during a
/// build. Automatic translations are fetched in the background through
/// [requestTranslations], never awaited by sales, checkout or stock code.
final class ProductDisplayNameResolver extends ChangeNotifier {
  ProductDisplayNameResolver({
    ProductTranslationStore? store,
    this.service = const UnconfiguredProductTranslationService(),
    this.timeout = const Duration(seconds: 30),
    this.maxAttempts = 3,
    this.batchSize = 8,
    this.retryDelay = _defaultRetryDelay,
  }) : _store = store ?? MemoryProductTranslationStore() {
    _engineReady = service.isConfigured;
    if (service case final Listenable engine) {
      engine.addListener(_engineChanged);
    }
  }

  /// The resolver for code without a [BuildContext] (repository searches).
  /// Replaced at startup by the loaded, persistent one.
  static ProductDisplayNameResolver instance = ProductDisplayNameResolver();

  /// Reads saved translations; an unreadable store starts empty.
  static Future<ProductDisplayNameResolver> load(
    ProductTranslationStore store, {
    ProductTranslationService service =
        const UnconfiguredProductTranslationService(),
  }) async {
    final resolver = ProductDisplayNameResolver(store: store, service: service);
    try {
      resolver._decode(await store.read());
    } catch (_) {
      // Corrupt or unavailable: English fallback still works.
    }
    return resolver;
  }

  final ProductTranslationStore _store;
  final ProductTranslationService service;
  final Duration timeout;
  final int maxAttempts;

  /// The most names sent to the engine at once, so a large catalog is
  /// translated a few names at a time.
  final int batchSize;
  final Duration Function(int attempt) retryDelay;

  bool _engineReady = false;

  /// The engine became ready (models downloaded) or stopped being ready:
  /// names that failed before may be retried, and visible names re-request.
  void _engineChanged() {
    final ready = service.isConfigured;
    if (ready == _engineReady) return;
    _engineReady = ready;
    if (ready) _attempts.clear();
    notifyListeners();
    if (ready && _pending.isNotEmpty) unawaited(drain());
  }

  static Duration _defaultRetryDelay(int attempt) =>
      Duration(seconds: 30 * (1 << (attempt - 1)));

  /// Manual corrections by product id. Kept across renames until changed.
  final _manual = <String, _Manual>{};

  /// Automatic translations by [_autoKey] (locale, product, source name).
  final _auto = <String, _Auto>{};

  final _pending = <String, ProductNameRef>{};
  final _attempts = <String, int>{};
  bool _draining = false;
  Timer? _retryTimer;

  /// Whether a real on-device translation engine is installed.
  bool get automaticTranslationAvailable => service.isConfigured;

  static String _autoKey(String languageCode, String productId, String name) =>
      '$languageCode|$productId|${normalizeProductName(name)}';

  /// The name to show for [name] in [languageCode]. Pass [productId] when
  /// known; without it (sale snapshots) the name alone is matched.
  String resolve(
    String name, {
    String? productId,
    required String languageCode,
  }) => _lookup(name, productId, languageCode)?.$1 ?? name;

  /// Where [resolve]'s answer comes from.
  ProductNameSource sourceOf(
    String name, {
    String? productId,
    required String languageCode,
  }) =>
      _lookup(name, productId, languageCode)?.$2 ?? ProductNameSource.original;

  (String, ProductNameSource)? _lookup(
    String name,
    String? productId,
    String languageCode,
  ) {
    if (languageCode != _urdu) return null;
    final key = normalizeProductName(name);
    if (productId != null) {
      if (_manual[productId] case final m?) {
        return (m.urdu, ProductNameSource.manual);
      }
      if (_auto[_autoKey(languageCode, productId, name)] case final a?) {
        return (a.text, ProductNameSource.automatic);
      }
    } else {
      for (final m in _manual.values) {
        if (normalizeProductName(m.source) == key) {
          return (m.urdu, ProductNameSource.manual);
        }
      }
      for (final a in _auto.values) {
        if (normalizeProductName(a.source) == key) {
          return (a.text, ProductNameSource.automatic);
        }
      }
    }
    return null;
  }

  /// Whether [name] matches [query] by its English name or its Urdu display
  /// name, whatever the UI language. Case-insensitive substring match.
  bool matches(String name, String query, {String? productId}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (!hasUrduScript(q)) return false;
    final urdu = _lookup(name, productId, _urdu)?.$1;
    if (urdu == null) return false;
    final uq = normalizeUrduText(q);
    return uq.isNotEmpty && normalizeUrduText(urdu).contains(uq);
  }

  /// The owner's correction for [productId], if any.
  String? manualUrdu(String productId) => _manual[productId]?.urdu;

  /// Saves the owner's Urdu name for a product; an empty [urdu] removes it.
  /// The English product name is never changed.
  Future<void> setManualUrdu({
    required String productId,
    required String englishName,
    required String urdu,
  }) async {
    final text = normalizeUrduText(urdu);
    if (text.isEmpty) {
      if (_manual.remove(productId) == null) return;
    } else {
      _manual[productId] = (source: englishName, urdu: text);
    }
    notifyListeners();
    await _save();
  }

  /// Queues background translation of products with no Urdu name yet.
  /// Returns at once; does nothing while no engine is installed. Cached
  /// translations of an older name of the same product are dropped.
  void requestTranslations(Iterable<ProductNameRef> products) {
    var purged = false;
    for (final p in products) {
      purged |= _purgeStale(p);
      if (!service.isConfigured || _manual.containsKey(p.productId)) continue;
      final key = _autoKey(_urdu, p.productId, p.name);
      if (_auto.containsKey(key) || (_attempts[key] ?? 0) >= maxAttempts) {
        continue;
      }
      _pending[key] = p;
    }
    if (purged) {
      notifyListeners();
      unawaited(_save());
    }
    if (_pending.isNotEmpty) scheduleMicrotask(() => unawaited(drain()));
  }

  bool _purgeStale(ProductNameRef p) {
    final current = normalizeProductName(p.name);
    final before = _auto.length;
    _auto.removeWhere(
      (_, a) =>
          a.productId == p.productId &&
          normalizeProductName(a.source) != current,
    );
    return _auto.length != before;
  }

  /// Sends queued names to the service. Failures (model missing, timeout, engine
  /// errors) are swallowed and retried later, up to [maxAttempts]. Exposed
  /// for tests; the app never awaits it.
  @visibleForTesting
  Future<void> drain() async {
    if (_draining || _pending.isEmpty || !service.isConfigured) return;
    _draining = true;
    final batch = Map.fromEntries(_pending.entries.take(batchSize));
    batch.keys.forEach(_pending.remove);
    try {
      final result = await service
          .translate(
            batch.values.map((p) => p.name).toSet().toList(),
            languageCode: _urdu,
          )
          .timeout(timeout);
      var changed = false;
      batch.forEach((key, p) {
        final text = normalizeUrduText(result[p.name] ?? '');
        if (text.isEmpty || text == p.name) {
          _failed(key, p, retry: false);
          return;
        }
        _auto[key] = (productId: p.productId, source: p.name, text: text);
        _attempts.remove(key);
        changed = true;
      });
      if (changed) {
        notifyListeners();
        await _save();
      }
    } catch (_) {
      batch.forEach((key, p) => _failed(key, p, retry: true));
    } finally {
      _draining = false;
    }
    // Names queued while this batch was in flight.
    if (_pending.isNotEmpty && _retryTimer == null) await drain();
  }

  void _failed(String key, ProductNameRef p, {required bool retry}) {
    final attempt = (_attempts[key] ?? 0) + 1;
    // No translation for this name: don't ask again this session.
    _attempts[key] = retry ? attempt : maxAttempts;
    if (!retry || attempt >= maxAttempts) return;
    _pending[key] = p;
    _retryTimer ??= Timer(retryDelay(attempt), () {
      _retryTimer = null;
      unawaited(drain());
    });
  }

  void _decode(String? json) {
    if (json == null || json.isEmpty) return;
    final data = jsonDecode(json) as Map<String, dynamic>;
    for (final MapEntry(:key, :value)
        in ((data['manual'] as Map?) ?? const {}).entries) {
      final m = value as Map;
      _manual[key as String] = (
        source: m['source'] as String,
        urdu: m['ur'] as String,
      );
    }
    for (final MapEntry(:key, :value)
        in ((data['auto'] as Map?) ?? const {}).entries) {
      final a = value as Map;
      _auto[key as String] = (
        productId: a['product'] as String,
        source: a['source'] as String,
        text: a['text'] as String,
      );
    }
  }

  Future<void> _save() async {
    try {
      await _store.write(
        jsonEncode({
          'manual': {
            for (final MapEntry(:key, :value) in _manual.entries)
              key: {'source': value.source, 'ur': value.urdu},
          },
          'auto': {
            for (final MapEntry(:key, :value) in _auto.entries)
              key: {
                'product': value.productId,
                'source': value.source,
                'text': value.text,
              },
          },
        }),
      );
    } catch (_) {
      // Kept in memory; written again with the next change.
    }
  }

  @override
  void dispose() {
    if (service case final Listenable engine) {
      engine.removeListener(_engineChanged);
    }
    _retryTimer?.cancel();
    super.dispose();
  }
}
