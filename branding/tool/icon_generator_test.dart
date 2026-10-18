// Generates every Dokan Pro launcher-icon asset from ONE geometry definition.
//
//   flutter test branding/tool/icon_generator_test.dart
//
// Outputs (overwritten on each run; nothing else is touched):
//   branding/icon/dokan_pro_icon.svg               full icon (editable master)
//   branding/icon/dokan_pro_icon_foreground.svg    adaptive foreground layer
//   branding/icon/dokan_pro_icon_monochrome.svg    Android 13+ themed layer
//   branding/icon/dokan_pro_icon_1024.png          1024 px master (full bleed)
//   branding/icon/dokan_pro_icon_preview.png       launcher-mask preview sheet
//   android/app/src/main/res/drawable/ic_launcher_foreground.xml
//   android/app/src/main/res/drawable/ic_launcher_monochrome.xml
//   android/app/src/main/res/values/ic_launcher_background.xml
//   android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
//   android/app/src/main/res/mipmap-*/ic_launcher.png   legacy (API < 26)
//
// Lives outside test/ so the normal `flutter test` run never executes it.
//
// Design: a kiryana storefront. A scalloped awning in alternating saffron and
// white over a white shop with an arched doorway, on Dokan Pro green
// (#176B52, the app's seed colour, pos_ui.dart posAccent). Geometry is on the
// 108 x 108 adaptive-icon grid and stays inside the 66-unit safe circle.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const green = Color(0xff176b52);
const greenDark = Color(0xff0f4a39);
const saffron = Color(0xfff4b63f);
const white = Color(0xffffffff);

String hex(Color c, {bool alpha = false}) {
  final v = c.toARGB32();
  final rgb = (v & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase();
  return alpha ? '#${(v >> 24).toRadixString(16).padLeft(2, '0').toUpperCase()}$rgb' : '#$rgb';
}

/// Path commands shared by SVG, VectorDrawable and Flutter.
sealed class Cmd {}

class M extends Cmd {
  M(this.x, this.y);
  final double x, y;
}

class H extends Cmd {
  H(this.x);
  final double x;
}

class V extends Cmd {
  V(this.y);
  final double y;
}

/// Arc to (x, y) with radius r; clockwise == SVG sweep-flag 1 (y down).
class A extends Cmd {
  A(this.r, this.x, this.y, {required this.clockwise});
  final double r, x, y;
  final bool clockwise;
}

class Z extends Cmd {}

class Shape {
  Shape(this.color, this.cmds);
  final Color color;
  final List<Cmd> cmds;
}

String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

String pathData(List<Cmd> cmds) => cmds
    .map(
      (c) => switch (c) {
        M(:final x, :final y) => 'M${fmt(x)},${fmt(y)}',
        H(:final x) => 'H${fmt(x)}',
        V(:final y) => 'V${fmt(y)}',
        A(:final r, :final x, :final y, :final clockwise) =>
          'A${fmt(r)},${fmt(r)} 0 0,${clockwise ? 1 : 0} ${fmt(x)},${fmt(y)}',
        Z() => 'Z',
      },
    )
    .join(' ');

Path flutterPath(List<Cmd> cmds) {
  final p = Path();
  var cx = 0.0, cy = 0.0;
  for (final c in cmds) {
    switch (c) {
      case M(:final x, :final y):
        p.moveTo(x, y);
        cx = x;
        cy = y;
      case H(:final x):
        p.lineTo(x, cy);
        cx = x;
      case V(:final y):
        p.lineTo(cx, y);
        cy = y;
      case A(:final r, :final x, :final y, :final clockwise):
        p.arcToPoint(Offset(x, y), radius: Radius.circular(r), clockwise: clockwise);
        cx = x;
        cy = y;
      case Z():
        p.close();
    }
  }
  return p;
}

// --- Geometry (108-unit adaptive grid) -------------------------------------
const awningLeft = 30.0, awningRight = 78.0, awningTop = 32.0, bandBottom = 41.0;
const stripe = 12.0, corner = 3.0, scallop = 6.0;
const bodyLeft = 33.0, bodyRight = 75.0, bodyTop = 50.0, bodyBottom = 76.0;
const doorLeft = 47.0, doorRight = 61.0, doorSpring = 66.0;

List<Shape> foreground() {
  final shapes = <Shape>[];
  for (var i = 0; i < 4; i++) {
    final x0 = awningLeft + i * stripe, x1 = x0 + stripe;
    final cmds = <Cmd>[
      if (i == 0) ...[M(x0, awningTop + corner), A(corner, x0 + corner, awningTop, clockwise: true)] else M(x0, awningTop),
      if (i == 3) ...[H(x1 - corner), A(corner, x1, awningTop + corner, clockwise: true)] else H(x1),
      V(bandBottom),
      A(scallop, x0, bandBottom, clockwise: true),
      Z(),
    ];
    shapes.add(Shape(i.isEven ? saffron : white, cmds));
  }
  // Shop with an arched doorway open to the street (one outline, no holes).
  shapes.add(
    Shape(white, [
      M(bodyLeft, bodyTop),
      H(bodyRight),
      V(bodyBottom - corner),
      A(corner, bodyRight - corner, bodyBottom, clockwise: true),
      H(doorRight),
      V(doorSpring),
      A((doorRight - doorLeft) / 2, doorLeft, doorSpring, clockwise: false),
      V(bodyBottom),
      H(bodyLeft + corner),
      A(corner, bodyLeft, bodyBottom - corner, clockwise: true),
      Z(),
    ]),
  );
  return shapes;
}

// --- Writers ---------------------------------------------------------------
String svg(List<Shape> shapes, {Color? background, Color? mono}) {
  final b = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="1024" height="1024">')
    ..writeln('  <title>Dokan Pro</title>');
  if (background != null) b.writeln('  <rect width="108" height="108" fill="${hex(background)}"/>');
  for (final s in shapes) {
    b.writeln('  <path fill="${hex(mono ?? s.color)}" d="${pathData(s.cmds)}"/>');
  }
  b.writeln('</svg>');
  return b.toString();
}

String vectorDrawable(List<Shape> shapes, {Color? mono}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- Generated by branding/tool/icon_generator_test.dart; edit the generator, not this file. -->')
    ..writeln('<vector xmlns:android="http://schemas.android.com/apk/res/android"')
    ..writeln('    android:width="108dp"')
    ..writeln('    android:height="108dp"')
    ..writeln('    android:viewportWidth="108"')
    ..writeln('    android:viewportHeight="108">');
  for (final s in shapes) {
    b
      ..writeln('    <path')
      ..writeln('        android:fillColor="${hex(mono ?? s.color)}"')
      ..writeln('        android:pathData="${pathData(s.cmds)}" />');
  }
  b.writeln('</vector>');
  return b.toString();
}

/// Draws the 108-grid icon into [dst]. [crop] selects the visible part of
/// the grid (adaptive icons show the centre 72 units).
void paintIcon(
  Canvas canvas,
  Rect dst, {
  Color background = green,
  bool foregroundOnly = false,
  Color? mono,
  double crop = 0,
}) {
  canvas.save();
  canvas.translate(dst.left, dst.top);
  final scale = dst.width / (108 - 2 * crop);
  canvas.scale(scale);
  canvas.translate(-crop, -crop);
  if (!foregroundOnly) canvas.drawRect(const Rect.fromLTWH(0, 0, 108, 108), Paint()..color = background);
  for (final s in foreground()) {
    canvas.drawPath(flutterPath(s.cmds), Paint()
      ..color = mono ?? s.color
      ..isAntiAlias = true);
  }
  canvas.restore();
}

/// Launcher masks: Samsung One UI squircle, circle (Pixel), rounded square.
Path maskPath(String kind, Rect r) {
  switch (kind) {
    case 'circle':
      return Path()..addOval(r);
    case 'rounded':
      return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * .2)));
    default: // squircle (superellipse n = 5)
      final p = Path();
      const n = 5.0;
      for (var i = 0; i <= 360; i++) {
        final t = i * math.pi / 180;
        final c = math.cos(t), s = math.sin(t);
        final x = math.pow(c.abs(), 2 / n) * c.sign, y = math.pow(s.abs(), 2 / n) * s.sign;
        final o = Offset(r.center.dx + x * r.width / 2, r.center.dy + y * r.height / 2);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      return p..close();
  }
}

Future<List<int>> render(int w, int h, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> legacyLauncher(Canvas c, double size) async {
  final r = Rect.fromLTWH(0, 0, size, size);
  c.save();
  c.clipPath(maskPath('rounded', r.deflate(size * .04)));
  paintIcon(c, r, crop: 18);
  c.restore();
}

void main() {
  testWidgets('generate Dokan Pro icon assets', (tester) async {
    await tester.runAsync(() async {
      final shapes = foreground();
      Directory('branding/icon').createSync(recursive: true);
      File('branding/icon/dokan_pro_icon.svg').writeAsStringSync(svg(shapes, background: green));
      File('branding/icon/dokan_pro_icon_foreground.svg').writeAsStringSync(svg(shapes));
      File('branding/icon/dokan_pro_icon_monochrome.svg').writeAsStringSync(svg(shapes, mono: const Color(0xff000000)));

      const res = 'android/app/src/main/res';
      File('$res/drawable/ic_launcher_foreground.xml').writeAsStringSync(vectorDrawable(shapes));
      File('$res/drawable/ic_launcher_monochrome.xml').writeAsStringSync(vectorDrawable(shapes, mono: white));
      File('$res/values/ic_launcher_background.xml').writeAsStringSync(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated by branding/tool/icon_generator_test.dart. -->\n'
        '<resources>\n    <color name="ic_launcher_background">${hex(green)}</color>\n</resources>\n',
      );
      Directory('$res/mipmap-anydpi-v26').createSync(recursive: true);
      File('$res/mipmap-anydpi-v26/ic_launcher.xml').writeAsStringSync(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Generated by branding/tool/icon_generator_test.dart. -->\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n',
      );

      // Legacy launcher PNGs (API < 26): 48 dp at each density.
      for (final (dir, px) in const [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
        File('$res/mipmap-$dir/ic_launcher.png').writeAsBytesSync(
          await render(px, px, (c) => legacyLauncher(c, px.toDouble())),
        );
      }

      // 1024 master: full bleed, launcher-visible area (centre 72 units).
      File('branding/icon/dokan_pro_icon_1024.png').writeAsBytesSync(
        await render(1024, 1024, (c) => paintIcon(c, const Rect.fromLTWH(0, 0, 1024, 1024), crop: 18)),
      );

      // Preview: 3 masks x 3 sizes on light and dark wallpapers, plus the
      // Android 13 themed (monochrome) rendering and the raw 108 grid with
      // its 66-unit safe circle.
      const cell = 220.0, cols = 5, rows = 2;
      File('branding/icon/dokan_pro_icon_preview.png').writeAsBytesSync(
        await render((cell * cols).toInt(), (cell * rows).toInt(), (c) {
          for (var row = 0; row < rows; row++) {
            final wallpaper = row == 0 ? const Color(0xffeef1f3) : const Color(0xff1d2327);
            c.drawRect(Rect.fromLTWH(0, row * cell, cell * cols, cell), Paint()..color = wallpaper);
            for (var col = 0; col < 3; col++) {
              final kind = const ['squircle', 'circle', 'rounded'][col];
              var x = col * cell + 20;
              for (final size in const [120.0, 64.0, 40.0]) {
                final r = Rect.fromLTWH(x, row * cell + (cell - size) / 2, size, size);
                c.save();
                c.clipPath(maskPath(kind, r));
                paintIcon(c, r, crop: 18);
                c.restore();
                x += size + 8;
                if (x > (col + 1) * cell - 30) break;
              }
            }
            // Themed icon (Android 13+): launcher tints the monochrome layer.
            final themed = Rect.fromLTWH(3 * cell + 50, row * cell + 50, 120, 120);
            c.save();
            c.clipPath(maskPath('circle', themed));
            c.drawRect(themed, Paint()..color = row == 0 ? const Color(0xffd3eadf) : const Color(0xff1f3b31));
            paintIcon(c, themed, foregroundOnly: true, mono: row == 0 ? greenDark : const Color(0xffb9e3cf), crop: 18);
            c.restore();
            // Full 108 grid with safe zone (row 0) / small 24 px check (row 1).
            if (row == 0) {
              final grid = Rect.fromLTWH(4 * cell + 20, 20, 180, 180);
              paintIcon(c, grid);
              c.drawCircle(grid.center, 180 * 33 / 108, Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = const Color(0xccff3b30));
              c.drawRect(Rect.fromCenter(center: grid.center, width: 180 * 72 / 108, height: 180 * 72 / 108), Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1
                ..color = const Color(0x99ffffff));
            } else {
              var x = 4 * cell + 30;
              for (final size in const [48.0, 32.0, 24.0]) {
                final r = Rect.fromLTWH(x, cell + (cell - size) / 2, size, size);
                c.save();
                c.clipPath(maskPath('squircle', r));
                paintIcon(c, r, crop: 18);
                c.restore();
                x += size + 18;
              }
            }
          }
        }),
      );
    });
  });
}
