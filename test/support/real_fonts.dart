// Real fonts for layout tests. Flutter's default test font draws every glyph
// one em wide, which says nothing about whether Urdu (Nastaliq or Naskh) or
// English text really fits. Loads Roboto (the Android UI font, bundled under
// test/support/fonts/roboto with its Apache 2.0 license, so tests never depend
// on an SDK cache that CI may not have) and the two bundled Urdu fonts under
// their app family names.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

const _roboto = 'test/support/fonts/roboto';

Future<ByteData> _bytes(String path) async =>
    ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

/// Call from `setUpAll` (or inside `tester.runAsync`). Safe to call twice.
Future<void> loadRealFonts() async {
  if (_loaded) return;
  final families = <String, List<String>>{
    'Roboto': [
      '$_roboto/roboto-regular.ttf',
      '$_roboto/roboto-medium.ttf',
      '$_roboto/roboto-bold.ttf',
    ],
    'NotoNastaliqUrdu': [
      'assets/fonts/noto_nastaliq_urdu/NotoNastaliqUrdu-Regular.ttf',
      'assets/fonts/noto_nastaliq_urdu/NotoNastaliqUrdu-Bold.ttf',
    ],
    'NotoNaskhArabic': [
      'assets/fonts/noto_naskh_arabic/NotoNaskhArabic-Regular.ttf',
      'assets/fonts/noto_naskh_arabic/NotoNaskhArabic-Bold.ttf',
    ],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(_bytes(file));
    }
    await loader.load();
  }
  _loaded = true;
}

/// Fails the test if any font file is missing, instead of silently falling
/// back to the box test font.
void expectRealFontsAvailable() {
  expect(
    File(
      'assets/fonts/noto_nastaliq_urdu/NotoNastaliqUrdu-Regular.ttf',
    ).existsSync(),
    isTrue,
  );
  expect(
    File(
      '$_roboto/roboto-regular.ttf',
    ).existsSync(),
    isTrue,
  );
}
