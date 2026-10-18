import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dukaan_pro/core/images/product_image_processing.dart';
import 'package:dukaan_pro/core/images/product_image_store.dart';
import 'package:dukaan_pro/features/pos/product_thumbnail.dart';
import 'package:dukaan_pro/features/products/custom_product_dialog.dart';
import 'package:dukaan_pro/features/products/product_image_picker.dart';
import 'package:dukaan_pro/features/products/product_management_models.dart';
import 'package:dukaan_pro/features/products/product_management_native.dart'
    show saveProductImage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int width, int height, {bool alpha = false}) {
  final image = img.Image(
    width: width,
    height: height,
    numChannels: alpha ? 4 : 3,
  )..clear(alpha ? img.ColorRgba8(200, 30, 30, 120) : img.ColorRgb8(1, 2, 3));
  return img.encodePng(image);
}

Uint8List _jpg(int width, int height) =>
    img.encodeJpg(img.Image(width: width, height: height));

const _categories = [
  ProductCategory(id: 'cat-1', name: 'Grocery'),
  ProductCategory(id: 'cat-2', name: 'Household cleaning supplies'),
];

final class _FakePicker implements ProductImagePicker {
  _FakePicker(this.results);
  final List<Uint8List?> results;
  int calls = 0;
  @override
  Future<Uint8List?> pick() async => results[calls++];
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

Future<Uint8List> _prepareInline(Uint8List source) async =>
    prepareProductThumbnail(source);

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('dukaan-product-images-');
    ProductImageStore.instance = null;
  });
  tearDown(() {
    ProductImageStore.instance = null;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('thumbnail preparation', () {
    test('downsizes, flattens transparency and encodes JPEG', () {
      final out = prepareProductThumbnail(_png(1600, 900, alpha: true));
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, productImageMaxSide);
      expect(decoded.height, 288);
      expect(decoded.hasAlpha, isFalse);
    });

    test('keeps small images at their size', () {
      final decoded = img.decodeJpg(prepareProductThumbnail(_jpg(120, 300)))!;
      expect((decoded.width, decoded.height), (120, 300));
    });

    test('rejects empty and non-image input with a friendly message', () {
      expect(
        () => prepareProductThumbnail(Uint8List(0)),
        throwsA(isA<ProductImageException>()),
      );
      expect(
        () => prepareProductThumbnail(Uint8List.fromList('%PDF-1.7'.codeUnits)),
        throwsA(
          isA<ProductImageException>().having(
            (e) => e.message,
            'message',
            contains('JPG, PNG or WebP'),
          ),
        ),
      );
    });
  });

  test('rejects images whose header exceeds the pixel ceiling', () {
    final png = _png(1, 1);
    // Patch IHDR width/height (big-endian at bytes 16..23) to 10000x10000.
    final data = ByteData.sublistView(png);
    data.setUint32(16, 10000);
    data.setUint32(20, 10000);
    // Recompute the IHDR CRC over chunk type + data (bytes 12..28).
    data.setUint32(29, _crc32(png.sublist(12, 29)));
    expect(
      () => prepareProductThumbnail(png),
      throwsA(
        isA<ProductImageException>().having(
          (e) => e.message,
          'message',
          contains('too large'),
        ),
      ),
    );
  });

  group('local image store', () {
    test('persists across a fresh store instance (app restart)', () async {
      final root = Directory('${temp.path}/product_images');
      await (await ProductImageStore.open(root)).save('prod-1', _jpg(10, 10));
      final restarted = await ProductImageStore.open(root);
      expect(restarted.existing('prod-1'), isNotNull);
      expect(restarted.existing('prod-2'), isNull);
      expect(
        root.listSync().whereType<File>().map((f) => f.path),
        isNot(contains(endsWith('.tmp'))),
      );
    });

    test('change replaces and remove deletes the image', () async {
      final store = await ProductImageStore.open(Directory(temp.path));
      await store.save('prod-1', _jpg(10, 10));
      final replacement = _jpg(20, 20);
      await store.save('prod-1', replacement);
      expect(store.existing('prod-1')!.readAsBytesSync(), replacement);
      await store.remove('prod-1');
      expect(store.existing('prod-1'), isNull);
      expect(File('${temp.path}/prod-1.jpg').existsSync(), isFalse);
      await store.remove('prod-1');
      final restarted = await ProductImageStore.open(Directory(temp.path));
      expect(restarted.existing('prod-1'), isNull);
    });

    test('index ignores unsafe ids, empty, temp and foreign files', () async {
      File('${temp.path}/empty.jpg').writeAsBytesSync(const []);
      File('${temp.path}/half.jpg.tmp').writeAsBytesSync(_jpg(4, 4));
      File('${temp.path}/notes.txt').writeAsStringSync('x');
      File('${temp.path}/bad name.jpg').writeAsBytesSync(_jpg(4, 4));
      File('${temp.path}/good.jpg').writeAsBytesSync(_jpg(4, 4));
      final store = await ProductImageStore.open(Directory(temp.path));
      expect(store.existing('../escape'), isNull);
      expect(() => store.fileFor('a/b'), throwsArgumentError);
      expect(store.existing('empty'), isNull);
      expect(store.existing('half'), isNull);
      expect(store.existing('notes'), isNull);
      expect(store.existing('good'), isNotNull);
    });

    test('lookups use the index, not the filesystem', () async {
      final store = await ProductImageStore.open(Directory(temp.path));
      // Written behind the store's back: not visible until reopened.
      File('${temp.path}/late.jpg').writeAsBytesSync(_jpg(4, 4));
      expect(store.existing('late'), isNull);
      expect(
        (await ProductImageStore.open(Directory(temp.path))).existing('late'),
        isNotNull,
      );
    });

    test('a failed write leaves no temp file and is not indexed', () async {
      final store = await ProductImageStore.open(Directory(temp.path));
      // A directory in the way makes the final rename fail.
      Directory('${temp.path}/blocked.jpg').createSync();
      await expectLater(store.save('blocked', _jpg(4, 4)), throwsA(anything));
      expect(File('${temp.path}/blocked.jpg.tmp').existsSync(), isFalse);
      expect(store.has('blocked'), isFalse);
    });

    test('saveProductImage never throws and reports failures', () async {
      expect(await saveProductImage('prod-1', null), isTrue);
      ProductImageStore.instance = await ProductImageStore.open(
        Directory(temp.path),
      );
      expect(await saveProductImage('prod-1', _jpg(8, 8)), isTrue);
      expect(ProductImageStore.instance!.existing('prod-1'), isNotNull);
      // A file where the image directory should be makes writing fail.
      final blocker = File('${temp.path}/blocked')..writeAsStringSync('x');
      ProductImageStore.instance = await ProductImageStore.open(
        Directory(blocker.path),
      );
      expect(await saveProductImage('prod-2', _jpg(8, 8)), isFalse);
    });
  });

  group('thumbnail resolution', () {
    testWidgets('local product image, no image and missing file fallback', (
      tester,
    ) async {
      final store = (await tester.runAsync(
        () => ProductImageStore.open(Directory(temp.path)),
      ))!;
      ProductImageStore.instance = store;
      await tester.runAsync(() => store.save('with-image', _jpg(16, 16)));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ProductThumbnail(productId: 'with-image'),
                ProductThumbnail(productId: 'without-image'),
                ProductThumbnail(
                  productId: 'without-image',
                  imagePath: 'missing/local/file.png',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('product-image')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('product-image-placeholder')),
        findsNWidgets(2),
      );
    });

    testWidgets('without an initialized store thumbnails show placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: ProductThumbnail(productId: 'any')),
      );
      expect(
        find.byKey(const ValueKey('product-image-placeholder')),
        findsOneWidget,
      );
    });
  });

  group('Create Custom Product dialog', () {
    Future<Future<CustomProductDraft?>> open(
      WidgetTester tester,
      ProductImagePicker picker, {
      Size size = const Size(1280, 800),
      double keyboard = 0,
      CustomProductSubmitter? onSubmit,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);
      late Future<CustomProductDraft?> result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: const Color(0xff176b52)),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => result = showDialog<CustomProductDraft>(
                  context: context,
                  builder: (_) => CustomProductDialog(
                    categories: _categories,
                    picker: picker,
                    prepareImage: _prepareInline,
                    onSubmit: onSubmit,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    Future<void> fillRequired(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const ValueKey('custom-product-name')),
        'Desi Ghee 1kg',
      );
      await tester.tap(find.byKey(const ValueKey('custom-product-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grocery').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-product-purchase')),
        '850',
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-product-sale')),
        '950.50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-product-opening')),
        '12',
      );
    }

    Future<void> tapVisible(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a visual picker and never a developer field', (
      tester,
    ) async {
      await open(tester, _FakePicker(const []));
      expect(find.text('Choose product image'), findsOneWidget);
      expect(find.text('Optional · JPG, PNG or WebP'), findsOneWidget);
      expect(find.textContaining('Image reference'), findsNothing);
      expect(find.text('Create Product'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      for (final label in [
        'Product name *',
        'Category *',
        'Barcode',
        'Unit *',
        'Pack size / label',
        'Purchase price *',
        'Sale price *',
        'Opening stock',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('choose, change and remove image', (tester) async {
      final first = _png(900, 900), second = _jpg(300, 600);
      final picker = _FakePicker([first, null, second]);
      final result = await open(tester, picker);

      await tapVisible(tester, const ValueKey('product-image-choose'));
      expect(find.byKey(const ValueKey('product-image-preview')), findsOne);
      expect(find.text('Choose product image'), findsNothing);
      final firstPreview = tester
          .widget<Image>(find.byKey(const ValueKey('product-image-preview')))
          .image;

      // Cancelling the picker keeps the current image.
      await tapVisible(tester, const ValueKey('product-image-change'));
      expect(find.byKey(const ValueKey('product-image-preview')), findsOne);

      await tapVisible(tester, const ValueKey('product-image-change'));
      final secondPreview = tester
          .widget<Image>(find.byKey(const ValueKey('product-image-preview')))
          .image;
      expect(secondPreview, isNot(firstPreview));

      await tapVisible(tester, const ValueKey('product-image-remove'));
      expect(find.byKey(const ValueKey('product-image-preview')), findsNothing);
      expect(find.text('Choose product image'), findsOneWidget);

      await fillRequired(tester);
      await tapVisible(tester, const ValueKey('custom-product-create'));
      final draft = await result;
      expect(draft!.image, isNull);
      expect(picker.calls, 3);
    });

    testWidgets('creates a product with a compressed image', (tester) async {
      final result = await open(tester, _FakePicker([_png(2000, 1000)]));
      await tapVisible(tester, const ValueKey('product-image-choose'));
      await fillRequired(tester);
      await tapVisible(tester, const ValueKey('custom-product-create'));
      final draft = (await result)!;
      final stored = img.decodeJpg(draft.image!)!;
      expect(stored.width, productImageMaxSide);
      expect(draft.input.imagePath, isNull);
      expect(draft.input.name, 'Desi Ghee 1kg');
      expect(draft.input.categoryId, 'cat-1');
      expect(draft.input.purchasePriceMinor, 85000);
      expect(draft.input.salePriceMinor, 95050);
      expect(draft.input.openingQuantity, 12000);
      expect(draft.input.unit, ProductUnit.piece);
    });

    testWidgets('creates a product without an image', (tester) async {
      final result = await open(tester, _FakePicker(const []));
      await fillRequired(tester);
      await tapVisible(tester, const ValueKey('custom-product-create'));
      final draft = (await result)!;
      expect(draft.image, isNull);
      expect(draft.input.barcode, isNull);
      expect(draft.input.packLabel, isNull);
      expect(draft.input.lowStockLevel, 0);
    });

    testWidgets('invalid image shows a message and does not block create', (
      tester,
    ) async {
      final result = await open(
        tester,
        _FakePicker([Uint8List.fromList('not an image'.codeUnits)]),
      );
      await tapVisible(tester, const ValueKey('product-image-choose'));
      expect(find.text('Choose a JPG, PNG or WebP product image.'), findsOne);
      expect(find.byKey(const ValueKey('product-image-preview')), findsNothing);
      await fillRequired(tester);
      await tapVisible(tester, const ValueKey('custom-product-create'));
      expect((await result)!.image, isNull);
    });

    testWidgets('picker failure is reported without crashing', (tester) async {
      await open(tester, _ThrowingPicker());
      await tapVisible(tester, const ValueKey('product-image-choose'));
      expect(find.text('Could not open that image. Try another.'), findsOne);
    });

    testWidgets('failed create keeps the dialog, data and image', (
      tester,
    ) async {
      var attempts = 0;
      final result = await open(
        tester,
        _FakePicker([_png(300, 300)]),
        onSubmit: (_) async {
          if (++attempts == 1) throw StateError('offline');
        },
      );
      await tapVisible(tester, const ValueKey('product-image-choose'));
      await fillRequired(tester);
      await tapVisible(tester, const ValueKey('custom-product-create'));
      expect(attempts, 1);
      expect(
        find.text('Could not create the product. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Desi Ghee 1kg'), findsOneWidget);
      expect(find.byKey(const ValueKey('product-image-preview')), findsOne);

      await tapVisible(tester, const ValueKey('custom-product-create'));
      expect(attempts, 2);
      final draft = (await result)!;
      expect(draft.image, isNotNull);
      expect(draft.input.name, 'Desi Ghee 1kg');
    });

    testWidgets('form is locked while the product is being created', (
      tester,
    ) async {
      final gate = Completer<void>();
      final result = await open(
        tester,
        _FakePicker(const []),
        onSubmit: (_) => gate.future,
      );
      await fillRequired(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-product-create')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-product-create')));
      await tester.pump();
      expect(find.text('Creating…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      // System back is blocked mid-save.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Creating…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect((await result)!.input.name, 'Desi Ghee 1kg');
    });

    testWidgets('required-field validation is unchanged', (tester) async {
      final result = await open(tester, _FakePicker(const []));
      await tapVisible(tester, const ValueKey('custom-product-create'));
      expect(
        find.text('Complete all required fields with valid values.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    for (final (name, size, keyboard) in [
      ('landscape tablet with keyboard', const Size(1280, 800), 380.0),
      ('short landscape with keyboard', const Size(1024, 600), 340.0),
      ('very short height', const Size(1280, 300), 0.0),
      ('portrait tablet with keyboard', const Size(800, 1280), 420.0),
      ('phone width', const Size(390, 844), 300.0),
    ]) {
      testWidgets('no overflow: $name', (tester) async {
        await open(
          tester,
          _FakePicker([_png(400, 400)]),
          size: size,
          keyboard: keyboard,
        );
        expect(tester.takeException(), isNull);
        await tapVisible(tester, const ValueKey('product-image-choose'));
        await tester.enterText(
          find.byKey(const ValueKey('custom-product-name')),
          'A very long product name that a shopkeeper might type in full',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('custom-product-create')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('custom-product-create')).hitTestable(),
          findsOneWidget,
        );
      });
    }
  });
}

final class _ThrowingPicker implements ProductImagePicker {
  @override
  Future<Uint8List?> pick() => Future.error(StateError('picker unavailable'));
}
