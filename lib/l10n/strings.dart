import 'dart:ui';

import 'translations.dart';

/// Stable language identifiers used in settings.json; labels are always native.
enum AppLanguage {
  simplifiedChinese(
    'zh-Hans',
    '简体中文',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ),
  traditionalChinese(
    'zh-Hant',
    '繁體中文',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ),
  english('en', 'English', Locale('en')),
  japanese('ja', '日本語', Locale('ja')),
  korean('ko', '한국어', Locale('ko'));

  const AppLanguage(this.code, this.nativeName, this.locale);
  final String code;
  final String nativeName;
  final Locale locale;

  static AppLanguage? fromCode(Object? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }

  static AppLanguage fromLocale(Locale locale) => switch (locale.languageCode) {
    'zh' =>
      locale.scriptCode == 'Hant' ||
              const ['TW', 'HK', 'MO'].contains(locale.countryCode)
          ? traditionalChinese
          : simplifiedChinese,
    'ja' => japanese,
    'ko' => korean,
    _ => english,
  };
}

/// The desktop application has one settings service per process. Keeping the
/// selected language here also makes action labels and non-widget HUD producers
/// localizable. SettingsService updates this before notifying the widget tree.
class AppStrings {
  static AppLanguage language = AppLanguage.simplifiedChinese;

  static String translate(
    String source, [
    List<Object?> args = const [],
    AppLanguage? language,
  ]) {
    final selected = language ?? AppStrings.language;
    final template = selected == AppLanguage.simplifiedChinese
        ? source
        : translations[source]?[selected.index - 1] ?? source;
    // Replace in one pass: filenames/other arguments must never be interpreted
    // as placeholders or translated themselves.
    return template.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < args.length ? '${args[index]}' : match[0]!;
    });
  }
}

String lt(String source, [List<Object?> args = const []]) =>
    AppStrings.translate(source, args);
