import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/l10n/l10n.dart';
import 'package:dukaan_pro/core/l10n/product_names.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/inventory/drift_inventory_repository.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/products/drift_product_management_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test double for an on-device engine: answers from a fixed table, or
/// fails like a missing model.
final class _FakeEngine implements ProductTranslationService {
  _FakeEngine(this.table);
  final Map<String, String> table;
  bool fail = false;
  int calls = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<Map<String, String>> translate(
    List<String> names, {
    required String languageCode,
  }) async {
    calls++;
    if (fail) throw StateError('model not available');
    return {
      for (final n in names) n: ?table[n],
    };
  }
}

const _ur = 'ur';
const _en = 'en';

String _strip(String s) =>
    String.fromCharCodes(s.runes.where((r) => r < 0x2066 || r > 0x2069));

void main() {
  late MemoryProductTranslationStore store;
  late _FakeEngine engine;
  late ProductDisplayNameResolver resolver;

  setUp(() {
    store = MemoryProductTranslationStore();
    engine = _FakeEngine({
      'Basmati Rice': 'باسمتی چاول',
      'Lux Soap': 'لکس صابن',
      'Lux Soap 100 g': 'لکس صابن 100 g',
    });
    resolver = ProductDisplayNameResolver(
      store: store,
      service: engine,
      retryDelay: (_) => Duration.zero,
    );
  });
  tearDown(() {
    resolver.dispose();
    ProductDisplayNameResolver.instance = ProductDisplayNameResolver();
  });

  group('resolver', () {
    test('without an engine every name stays as stored, in both languages', () {
      final plain = ProductDisplayNameResolver();
      expect(plain.automaticTranslationAvailable, isFalse);
      plain.requestTranslations([(productId: 'p', name: 'Basmati Rice')]);
      for (final lang in [_en, _ur]) {
        expect(
          plain.resolve('Basmati Rice', productId: 'p', languageCode: lang),
          'Basmati Rice',
        );
      }
    });

    test(
      'English always shows the original, Urdu the cached translation',
      () async {
        resolver.requestTranslations([
          (productId: 'rice', name: 'Basmati Rice'),
        ]);
        expect(
          resolver.resolve(
            'Basmati Rice',
            productId: 'rice',
            languageCode: _ur,
          ),
          'Basmati Rice',
          reason: 'pending: original shown',
        );
        await resolver.drain();
        expect(
          resolver.resolve(
            'Basmati Rice',
            productId: 'rice',
            languageCode: _ur,
          ),
          'باسمتی چاول',
        );
        expect(
          resolver.resolve(
            'Basmati Rice',
            productId: 'rice',
            languageCode: _en,
          ),
          'Basmati Rice',
        );
      },
    );

    test('cached names persist and load offline without the engine', () async {
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      final offline = await ProductDisplayNameResolver.load(store);
      expect(offline.automaticTranslationAvailable, isFalse);
      expect(
        offline.resolve('Basmati Rice', productId: 'rice', languageCode: _ur),
        'باسمتی چاول',
      );
      expect(
        offline.sourceOf('Basmati Rice', productId: 'rice', languageCode: _ur),
        ProductNameSource.automatic,
      );
    });

    test('each name is translated once, not on every lookup', () async {
      for (var i = 0; i < 5; i++) {
        resolver.requestTranslations([
          (productId: 'rice', name: 'Basmati Rice'),
        ]);
        await resolver.drain();
      }
      expect(engine.calls, 1);
    });

    test('a rename drops the stale translation and falls back', () async {
      resolver.requestTranslations([(productId: 'lux', name: 'Lux Soap')]);
      await resolver.drain();
      resolver.requestTranslations([(productId: 'lux', name: 'Lux Soap Rose')]);
      await resolver.drain();
      expect(
        resolver.resolve('Lux Soap Rose', productId: 'lux', languageCode: _ur),
        'Lux Soap Rose',
        reason: 'no translation for the new name',
      );
      expect(store.json, isNot(contains('لکس صابن')));
    });

    test('variants are translated per name, never borrowed', () async {
      resolver.requestTranslations([
        (productId: 'lux', name: 'Lux Soap'),
        (productId: 'lux100', name: 'Lux Soap 100 g'),
        (productId: 'luxrose', name: 'Lux Soap Rose'),
      ]);
      await resolver.drain();
      String ur(String id, String name) =>
          resolver.resolve(name, productId: id, languageCode: _ur);
      expect(ur('lux', 'Lux Soap'), 'لکس صابن');
      expect(ur('lux100', 'Lux Soap 100 g'), 'لکس صابن 100 g');
      expect(ur('luxrose', 'Lux Soap Rose'), 'Lux Soap Rose');
    });

    test('manual corrections win and are never overwritten', () async {
      await resolver.setManualUrdu(
        productId: 'rice',
        englishName: 'Basmati Rice',
        urdu: 'باسمتی چاول سپر',
      );
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      expect(engine.calls, 0, reason: 'corrected products are not re-sent');
      expect(
        resolver.resolve('Basmati Rice', productId: 'rice', languageCode: _ur),
        'باسمتی چاول سپر',
      );
      expect(
        resolver.resolve('Basmati Rice', languageCode: _ur),
        'باسمتی چاول سپر',
        reason: 'name-only lookups (sale snapshots) use it too',
      );
      await resolver.setManualUrdu(
        productId: 'rice',
        englishName: 'Basmati Rice',
        urdu: '',
      );
      expect(resolver.manualUrdu('rice'), isNull);
    });

    test('engine failures never throw and are retried, then give up', () async {
      engine.fail = true;
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      expect(
        resolver.resolve('Basmati Rice', productId: 'rice', languageCode: _ur),
        'Basmati Rice',
      );
      await pumpEventQueue();
      expect(engine.calls, resolver.maxAttempts);
      engine.fail = false;
      resolver.requestTranslations([(productId: 'rice', name: 'Basmati Rice')]);
      await resolver.drain();
      expect(
        engine.calls,
        resolver.maxAttempts,
        reason: 'gave up this session',
      );
    });

    test('a corrupt store starts empty', () async {
      final loaded = await ProductDisplayNameResolver.load(
        MemoryProductTranslationStore('{not json'),
      );
      expect(loaded.resolve('Lux Soap', languageCode: _ur), 'Lux Soap');
    });
  });

  group('bilingual search', () {
    PosProduct pos(String id, String name) => PosProduct(
      id: id,
      name: name,
      salePriceMinor: 10000,
      stockQuantity: 5000,
      stockTrackingEnabled: true,
    );

    test('POS search matches English and the available Urdu name', () async {
      ProductDisplayNameResolver.instance = resolver;
      resolver.requestTranslations([
        (productId: 'rice', name: 'Basmati Rice'),
        (productId: 'lux', name: 'Lux Soap'),
      ]);
      await resolver.drain();
      final all = [
        pos('rice', 'Basmati Rice'),
        pos('lux', 'Lux Soap'),
        pos('tea', 'Tapal Danedar'),
      ];
      List<String> find(String q) =>
          all.where((p) => matchesPosSearch(p, q)).map((p) => p.id).toList();
      expect(find('basmati'), ['rice']);
      expect(find('چاول'), ['rice']);
      expect(find('صابن'), ['lux']);
      expect(find('چائے'), isEmpty);
      expect(find(''), hasLength(3));
    });
  });

  group('locale switching in widgets', () {
    Future<String> shown(WidgetTester tester, Locale locale) async {
      late String result;
      await tester.pumpWidget(
        ProductNamesScope(
          resolver: resolver,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                result = productDisplayName(
                  context,
                  'Lux Soap',
                  productId: 'lux',
                );
                return Text(result);
              },
            ),
          ),
        ),
      );
      return _strip(result);
    }

    testWidgets('Urdu shows the original until cached, then the translation', (
      tester,
    ) async {
      expect(await shown(tester, const Locale('ur')), 'Lux Soap');
      await tester.runAsync(resolver.drain);
      await tester.pump();
      expect(await shown(tester, const Locale('ur')), 'لکس صابن');
      expect(await shown(tester, const Locale('en')), 'Lux Soap');
      expect(await shown(tester, const Locale('ur')), 'لکس صابن');
    });
  });

  group('offline repositories', () {
    late AppDatabase db;
    final now = DateTime.utc(2026, 10, 13);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(
              id: 'shop',
              name: 'Shop',
              phone: '',
              address: '',
              subscriptionPlan: SubscriptionPlan.trial,
              subscriptionStatus: SubscriptionStatus.trial,
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (final (id, name) in [
        ('rice', 'Basmati Rice'),
        ('lux', 'Lux Soap'),
        ('tea', 'Tapal Danedar'),
      ]) {
        await db
            .into(db.shopProducts)
            .insert(
              ShopProductsCompanion.insert(
                id: id,
                shopId: 'shop',
                customName: Value(name),
                purchasePrice: 100,
                salePrice: 120,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      ProductDisplayNameResolver.instance = resolver;
      resolver.requestTranslations([
        (productId: 'rice', name: 'Basmati Rice'),
        (productId: 'lux', name: 'Lux Soap'),
      ]);
      await resolver.drain();
    });
    tearDown(() => db.close());

    test('product management and inventory search both languages', () async {
      final products = DriftProductManagementRepository(db, shopId: 'shop');
      final inventory = DriftInventoryRepository(db, shopId: 'shop');
      Future<List<String>> managed(String q) async =>
          [for (final p in await products.products(query: q)) p.id]..sort();
      Future<List<String>> stock(String q) async =>
          [for (final p in await inventory.products(search: q)) p.id]..sort();
      expect(await managed('rice'), ['rice']);
      expect(await managed('چاول'), ['rice']);
      expect(await managed(''), hasLength(3));
      expect(await stock('لکس'), ['lux']);
      expect(await stock('lux'), ['lux']);
    });

    test('product rows, ids and names are never changed', () async {
      await resolver.setManualUrdu(
        productId: 'rice',
        englishName: 'Basmati Rice',
        urdu: 'چاول',
      );
      await DriftProductManagementRepository(
        db,
        shopId: 'shop',
      ).products(query: 'چاول');
      final rows = await db.select(db.shopProducts).get();
      expect(
        {for (final r in rows) r.id: r.customName},
        {'rice': 'Basmati Rice', 'lux': 'Lux Soap', 'tea': 'Tapal Danedar'},
      );
    });
  });
}
