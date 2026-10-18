// Every English string has an Urdu translation with the same placeholders,
// so a screen can never fall back to a missing key in Urdu.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messages(Map<String, dynamic> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

/// Top-level placeholders used in [message]: `{name}` and the argument of
/// `{name, select|plural, ...}`. Branch bodies such as `1{Jan}` or
/// `other{}` are not placeholders.
Set<String> _used(String message) => RegExp(
  r'(?<![\w}])\{(\w+)(?=[},])',
).allMatches(message).map((match) => match.group(1)!).toSet();

void main() {
  final en = _arb('en');
  final ur = _arb('ur');

  test('locales are declared', () {
    expect((en['@@locale'], ur['@@locale']), ('en', 'ur'));
  });

  test('Urdu has exactly the English keys', () {
    expect(_messages(ur), _messages(en));
  });

  test('every English key is documented for translators', () {
    for (final key in _messages(en)) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      expect(meta?['description'], isA<String>(), reason: key);
    }
  });

  test('both languages use exactly the declared placeholders', () {
    for (final key in _messages(en)) {
      final meta = en['@$key'] as Map<String, dynamic>;
      final declared =
          (meta['placeholders'] as Map<String, dynamic>? ?? const {}).keys
              .toSet();
      expect(_used(en[key] as String), declared, reason: 'en $key');
      expect(_used(ur[key] as String), declared, reason: 'ur $key');
    }
  });

  test('no message is empty and select messages keep every branch', () {
    for (final key in _messages(en)) {
      final english = en[key] as String;
      final urdu = ur[key] as String;
      expect(urdu.trim(), isNotEmpty, reason: key);
      final branches = RegExp(r'(\w+)\{');
      Set<String> names(String m) =>
          branches.allMatches(m).map((x) => x.group(1)!).toSet();
      // Urdu covers every English branch (it may translate more cases, e.g.
      // unit names whose English text is passed through) and keeps `other`.
      if (english.contains(', select,') || english.contains(', plural,')) {
        expect(names(urdu), containsAll(names(english)), reason: key);
        expect(names(urdu), contains('other'), reason: key);
      }
    }
  });
}
