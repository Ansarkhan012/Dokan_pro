// Real fonts for layout tests. Flutter's default test font draws every glyph
// one em wide, which says nothing about whether Urdu (Nastaliq or Naskh) or
// English text really fits. Loads Roboto (the Android UI font, from the
// Flutter SDK) and the two bundled Urdu fonts under their app family names.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

String get _flutterRoot {
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  // flutter_tester runs from <flutter>/bin/cache/artifacts/engine/<platform>.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (File('${dir.path}/bin/flutter').existsSync() ||
        File('${dir.path}/bin/flutter.bat').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  throw StateError('Flutter SDK not found for real-font tests');
}

Future<ByteData> _bytes(String path) async =>
    ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

/// Call from `setUpAll` (or inside `tester.runAsync`). Safe to call twice.
Future<void> loadRealFonts() async {
  if (_loaded) return;
  final material = '$_flutterRoot/bin/cache/artifacts/material_fonts';
  final families = <String, List<String>>{
    'Roboto': [
      '$material/roboto-regular.ttf',
      '$material/roboto-medium.ttf',
      '$material/roboto-bold.ttf',
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
      '$_flutterRoot/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    ).existsSync(),
    isTrue,
  );
}
