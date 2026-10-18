import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two Urdu typefaces under comparison (Stage 2 font spike). Only used
/// while the UI language is Urdu.
enum UrduFont {
  nastaliq('NotoNastaliqUrdu'),
  naskh('NotoNaskhArabic');

  const UrduFont(this.family);
  final String family;
}

/// Device-local storage of the UI language. Never part of shop data, SQLite
/// or sync.
abstract interface class LocalePreferenceStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

final class SharedPreferencesLocaleStore implements LocalePreferenceStore {
  const SharedPreferencesLocaleStore();
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}

/// For tests and the unconfigured shell: remembers nothing across runs.
final class MemoryLocaleStore implements LocalePreferenceStore {
  MemoryLocaleStore([Map<String, String>? values]) : values = values ?? {};
  final Map<String, String> values;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// The UI language and Urdu font. English is the default whenever nothing
/// was chosen or the preference cannot be read, so existing users see no
/// change until they pick Urdu.
///
/// Switching only notifies listeners; the app rebuilds `MaterialApp` with
/// the new locale, which keeps the navigator, the signed-in session, the
/// cart and the current screen.
final class LocaleController extends ChangeNotifier {
  LocaleController({
    LocalePreferenceStore? store,
    Locale initialLocale = english,
    UrduFont initialUrduFont = UrduFont.nastaliq,
  }) : _store = store ?? MemoryLocaleStore(),
       _locale = initialLocale,
       _urduFont = initialUrduFont;

  static const english = Locale('en');
  static const urdu = Locale('ur');
  static const supportedLocales = [english, urdu];
  static const localeKey = 'ui_locale';
  static const urduFontKey = 'ui_urdu_font';

  final LocalePreferenceStore _store;
  Locale _locale;
  UrduFont _urduFont;

  Locale get locale => _locale;
  UrduFont get urduFont => _urduFont;
  bool get isUrdu => _locale.languageCode == urdu.languageCode;

  /// Reads the saved choice; any failure falls back to English.
  static Future<LocaleController> load(LocalePreferenceStore store) async {
    var locale = english;
    var font = UrduFont.nastaliq;
    try {
      if (await store.read(localeKey) == urdu.languageCode) locale = urdu;
      final savedFont = await store.read(urduFontKey);
      font = UrduFont.values.firstWhere(
        (value) => value.name == savedFont,
        orElse: () => UrduFont.nastaliq,
      );
    } catch (_) {
      // Unreadable preferences never block startup.
    }
    return LocaleController(
      store: store,
      initialLocale: locale,
      initialUrduFont: font,
    );
  }

  /// Switches at once; saving is best effort and never undoes the switch.
  Future<void> setLocale(Locale locale) async {
    final next = supportedLocales.firstWhere(
      (value) => value.languageCode == locale.languageCode,
      orElse: () => english,
    );
    if (next == _locale) return;
    _locale = next;
    notifyListeners();
    await _save(localeKey, next.languageCode);
  }

  Future<void> setUrduFont(UrduFont font) async {
    if (font == _urduFont) return;
    _urduFont = font;
    notifyListeners();
    await _save(urduFontKey, font.name);
  }

  Future<void> _save(String key, String value) async {
    try {
      await _store.write(key, value);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

/// Makes the [LocaleController] reachable from any route, including dialogs.
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Null when the widget is pumped without the app shell (e.g. in a test).
  static LocaleController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.notifier;
}
