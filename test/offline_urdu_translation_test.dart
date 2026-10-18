import 'dart:math';

import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/offline_urdu_translation.dart';
import 'package:dukaan_pro/core/l10n/product_names.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/settings/offline_translation_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for ML Kit: an in-memory model store and a word table.
final class _FakeBackend implements TranslationModelBackend {
  _FakeBackend({this.isSupported = true, Set<String>? downloaded})
    : downloaded = downloaded ?? {};
  @override
  final bool isSupported;
  final Set<String> downloaded;
  final downloads = <String>[];
  final translated = <String>[];
  bool failDownload = false;
  int active = 0;
  int maxActive = 0;
  int closes = 0;
  final table = {
    'Basmati Rice': 'باسمتی چاول',
    'Lux Soap': 'لکس صابن',
    "Olper's Milk": 'اولپرز دودھ',
    'Tapal Danedar': 'ٹپال دانے دار',
  };

  @override
  Future<bool> isModelDownloaded(String languageCode) async =>
      downloaded.contains(languageCode);

  @override
  Future<bool> downloadModel(
    String languageCode, {
    required bool wifiOnly,
  }) async {
    downloads.add('$languageCode${wifiOnly ? '' : ' (mobile data)'}');
    if (failDownload) throw PlatformException(code: 'download-failed');
    downloaded.add(languageCode);
    return true;
  }

  @override
  Future<String> translate(String text) async {
    if (!downloaded.containsAll(['en', 'ur'])) {
      throw StateError('the real plugin would download here');
    }
    translated.add(text);
    active++;
    maxActive = max(maxActive, active);
    await Future<void>.delayed(Duration.zero);
    active--;
    return table[text] ?? text;
  }

  @override
  Future<void> close() async => closes++;
}

const _ur = 'ur';
const _en = 'en';

OfflineUrduTranslation _engine(_FakeBackend backend) =>
    OfflineUrduTranslation(backend: backend, idleClose: Duration.zero);

void main() {
  group('models', () {
    test('unsupported devices never translate or download', () async {
      final backend = _FakeBackend(isSupported: false);
      final engine = _engine(backend);
      await engine.checkModels();
      expect(engine.status, TranslationModelStatus.unsupported);
      expect(await engine.downloadModels(), isFalse);
      expect(engine.isConfigured, isFalse);
      expect(backend.downloads, isEmpty);
    });

    test('checking never downloads', () async {
      final backend = _FakeBackend();
      final engine = _engine(backend);
      await engine.checkModels();
      expect(engine.status, TranslationModelStatus.notDownloaded);
      expect(backend.downloads, isEmpty);
    });

    test('downloads only missing models, over Wi-Fi, once', () async {
      final backend = _FakeBackend(downloaded: {'en'});
      final engine = _engine(backend);
      await engine.checkModels();
      expect(await engine.downloadModels(), isTrue);
      expect(engine.status, TranslationModelStatus.ready);
      expect(await engine.downloadModels(), isTrue);
      await engine.checkModels();
      expect(backend.downloads, ['ur']);
    });

    test('a failed download can be retried', () async {
      final backend = _FakeBackend()..failDownload = true;
      final engine = _engine(backend);
      await engine.checkModels();
      expect(await engine.downloadModels(), isFalse);
      expect(engine.status, TranslationModelStatus.failed);
      backend.failDownload = false;
      expect(await engine.downloadModels(wifiOnly: false), isTrue);
      expect(engine.status, TranslationModelStatus.ready);
      expect(backend.downloads, ['en', 'en (mobile data)', 'ur (mobile data)']);
    });

    test(
      'a removed model is noticed and never downloaded implicitly',
      () async {
        final backend = _FakeBackend(downloaded: {'en', 'ur'});
        final engine = _engine(backend);
        await engine.checkModels();
        backend.downloaded.remove('ur');
        await expectLater(
          engine.translate(['Lux Soap'], languageCode: _ur),
          throwsStateError,
        );
        expect(engine.status, TranslationModelStatus.notDownloaded);
        expect(backend.translated, isEmpty);
        expect(backend.downloads, isEmpty);
      },
    );

    test('dispose releases the native translator', () async {
      final backend = _FakeBackend();
      _engine(backend).dispose();
      await pumpEventQueue();
      expect(backend.closes, 1);
    });
  });

  group('names', () {
    Future<String?> run(String name) =>
        translateProductName(name, (t) async => 'URDU[$t]');

    test('sizes, counts and units are kept exactly', () async {
      expect(await run('Lux Soap 100 g'), 'URDU[Lux Soap] 100 g');
      expect(await run("Olper's Milk 1.5L"), "URDU[Olper's Milk] 1.5L");
      expect(await run('Basmati Rice 5 kg x 2'), 'URDU[Basmati Rice] 5 kg x 2');
      expect(await run('500ml'), isNull, reason: 'nothing to translate');
    });

    test('an unchanged result is not a translation', () async {
      expect(await translateProductName('Surf', (t) async => 'surf'), isNull);
    });
  });

  group('resolver with ML Kit', () {
    late _FakeBackend backend;
    late OfflineUrduTranslation engine;
    late ProductDisplayNameResolver resolver;
    late MemoryProductTranslationStore store;

    setUp(() async {
      backend = _FakeBackend();
      engine = _engine(backend);
      await engine.checkModels();
      store = MemoryProductTranslationStore();
      resolver = ProductDisplayNameResolver(
        store: store,
        service: engine,
        retryDelay: (_) => Duration.zero,
      );
    });
    tearDown(() {
      resolver.dispose();
      engine.dispose();
      ProductDisplayNameResolver.instance = ProductDisplayNameResolver();
    });

    String ur(String id, String name) =>
        resolver.resolve(name, productId: id, languageCode: _ur);

    test('missing models: English shown, nothing requested', () async {
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      expect(ur('rice', 'Basmati Rice'), 'Basmati Rice');
      expect(backend.translated, isEmpty);
    });

    test('Urdu after the models arrive; English unchanged', () async {
      var notified = 0;
      resolver.addListener(() => notified++);
      await engine.downloadModels();
      expect(notified, greaterThan(0), reason: 'screens re-request names');
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      expect(ur('rice', 'Basmati Rice'), 'باسمتی چاول');
      expect(
        resolver.resolve('Basmati Rice', productId: 'rice', languageCode: _en),
        'Basmati Rice',
      );
    });

    test('cached names work offline after a restart, without models', () async {
      await engine.downloadModels();
      resolver.requestTranslations([(productId: 'lux', name: 'Lux Soap')]);
      await resolver.drain();
      final offline = await ProductDisplayNameResolver.load(
        store,
        service: _engine(_FakeBackend(isSupported: false)),
      );
      expect(
        offline.resolve('Lux Soap', productId: 'lux', languageCode: _ur),
        'لکس صابن',
      );
    });

    test('no duplicate requests; bounded batches and concurrency', () async {
      await engine.downloadModels();
      final many = [
        for (var i = 0; i < 30; i++) (productId: 'p$i', name: 'Item $i Lux'),
      ];
      for (var round = 0; round < 3; round++) {
        resolver.requestTranslations(many);
        await resolver.drain();
      }
      expect(backend.translated, hasLength(30));
      expect(backend.maxActive, lessThanOrEqualTo(engine.concurrency));
    });

    test('manual correction wins over machine translation', () async {
      await engine.downloadModels();
      await resolver.setManualUrdu(
        productId: 'rice',
        englishName: 'Basmati Rice',
        urdu: 'سپر باسمتی',
      );
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      expect(backend.translated, isEmpty);
      expect(ur('rice', 'Basmati Rice'), 'سپر باسمتی');
    });

    test('a renamed product is translated again by its new name', () async {
      await engine.downloadModels();
      resolver.requestTranslations([(productId: 'tea', name: 'Lux Soap')]);
      await resolver.drain();
      resolver.requestTranslations([(productId: 'tea', name: 'Tapal Danedar')]);
      await resolver.drain();
      expect(ur('tea', 'Tapal Danedar'), 'ٹپال دانے دار');
      expect(ur('tea', 'Lux Soap'), 'Lux Soap', reason: 'stale entry dropped');
    });

    test('bilingual POS search uses machine translations', () async {
      await engine.downloadModels();
      ProductDisplayNameResolver.instance = resolver;
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      const rice = PosProduct(
        id: 'rice',
        name: 'Basmati Rice',
        salePriceMinor: 100,
        stockQuantity: 1000,
        stockTrackingEnabled: true,
      );
      expect(matchesPosSearch(rice, 'چاول'), isTrue);
      expect(matchesPosSearch(rice, 'basmati'), isTrue);
      expect(rice.name, 'Basmati Rice', reason: 'product data unchanged');
    });
  });

  group('settings', () {
    Future<void> pump(
      WidgetTester tester,
      ProductDisplayNameResolver resolver,
    ) => tester.pumpWidget(
      ProductNamesScope(
        resolver: resolver,
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: OfflineTranslationSetting()),
        ),
      ),
    );

    testWidgets('download only after tap and confirm; failure offers retry', (
      tester,
    ) async {
      final backend = _FakeBackend()..failDownload = true;
      final engine = _engine(backend);
      final resolver = ProductDisplayNameResolver(service: engine);
      await tester.runAsync(engine.checkModels);
      await pump(tester, resolver);
      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.offlineTranslationNotDownloaded), findsOneWidget);
      expect(backend.downloads, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('offline-translation-download')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.commonCancel));
      await tester.pumpAndSettle();
      expect(backend.downloads, isEmpty, reason: 'cancel downloads nothing');

      await tester.tap(
        find.byKey(const ValueKey('offline-translation-download')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('offline-translation-confirm')),
      );
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(find.text(en.offlineTranslationFailed), findsOneWidget);
      expect(find.text(en.offlineTranslationRetry), findsOneWidget);

      backend.failDownload = false;
      await tester.tap(
        find.byKey(const ValueKey('offline-translation-download')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('offline-translation-confirm')),
      );
      await tester.runAsync(() => pumpEventQueue());
      await tester.pumpAndSettle();
      expect(find.text(en.offlineTranslationReady), findsOneWidget);
      resolver.dispose();
      engine.dispose();
    });

    testWidgets('unsupported devices explain manual names still work', (
      tester,
    ) async {
      final engine = _engine(_FakeBackend(isSupported: false));
      await tester.runAsync(engine.checkModels);
      final resolver = ProductDisplayNameResolver(service: engine);
      await pump(tester, resolver);
      expect(
        find.text(
          lookupAppLocalizations(
            const Locale('en'),
          ).offlineTranslationUnsupported,
        ),
        findsOneWidget,
      );
      resolver.dispose();
      engine.dispose();
    });
  });
}
