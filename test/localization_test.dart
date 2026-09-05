import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/l10n/strings.dart';
import 'package:limeimage/l10n/translations.dart';
import 'package:limeimage/models/app_action.dart';
import 'package:limeimage/models/settings.dart';
import 'package:limeimage/services/folder_service.dart';
import 'package:limeimage/services/image_service.dart';
import 'package:limeimage/services/settings_service.dart';
import 'package:limeimage/state/viewer_state.dart';
import 'package:limeimage/ui/app.dart';
import 'package:limeimage/ui/viewer_page.dart';
import 'package:limeimage/ui/language_page.dart';
import 'package:limeimage/ui/settings_page.dart';

class _Marks extends Fake implements MarksService {}

class _OnboardingService extends ChangeNotifier implements SettingsService {
  @override
  Settings settings = Settings();

  @override
  Future<void> chooseLanguage(AppLanguage language) async {
    settings.language = language;
    AppStrings.language = language;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lime-l10n-');
  });
  tearDown(() async {
    AppStrings.language = AppLanguage.simplifiedChinese;
    await directory.delete(recursive: true);
  });

  test('fresh, legacy and unsupported language configurations', () {
    expect(Settings().language, isNull);
    expect(Settings.fromJson({}).language, AppLanguage.simplifiedChinese);
    expect(Settings.fromJson({'language': 'unsupported'}).language, isNull);
    expect(Settings.fromJson(Settings().toJson()).language, isNull);
    for (final language in AppLanguage.values) {
      final settings = Settings()..language = language;
      expect(Settings.fromJson(settings.toJson()).language, language);
    }
    expect(
      AppLanguage.fromLocale(const Locale('zh', 'TW')),
      AppLanguage.traditionalChinese,
    );
    expect(
      AppLanguage.fromLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      AppLanguage.traditionalChinese,
    );
    expect(
      AppLanguage.fromLocale(const Locale('zh', 'CN')),
      AppLanguage.simplifiedChinese,
    );
    expect(AppLanguage.fromLocale(const Locale('fr')), AppLanguage.english);
  });

  test('catalog is complete and preserves placeholders in all languages', () {
    final placeholders = RegExp(r'\{\d+\}');
    for (final entry in translations.entries) {
      expect(entry.value, hasLength(4), reason: entry.key);
      final expected =
          placeholders.allMatches(entry.key).map((m) => m[0]).toList()..sort();
      for (final translated in entry.value) {
        expect(translated, isNotEmpty, reason: entry.key);
        final actual =
            placeholders.allMatches(translated).map((m) => m[0]).toList()
              ..sort();
        expect(actual, expected, reason: entry.key);
      }
    }
    // Guard the migrated UI and action keys against accidental missing entries.
    final sourceKeys = RegExp(r'''lt\(\s*["']([^"']+)["']''');
    for (final file in [
      ...Directory('lib/ui').listSync().whereType<File>(),
      File('lib/state/viewer_state.dart'),
    ]) {
      for (final match in sourceKeys.allMatches(file.readAsStringSync())) {
        final key = match[1]!.replaceAll(r'\n', '\n');
        expect(
          translations.containsKey(key),
          isTrue,
          reason: '${file.path}: $key',
        );
      }
    }
    for (final action in AppAction.values) {
      expect(translations.containsKey(action.label), isTrue);
    }
    AppStrings.language = AppLanguage.english;
    expect(AppAction.openSettings.label, 'Settings');
    expect(lt('把「{0}」移到回收站？', ['中文{1}.png']), 'Move “中文{1}.png” to the trash?');
    AppStrings.language = AppLanguage.japanese;
    expect(AppAction.openSettings.label, '設定');
  });

  test('selection survives restart, reset and external reload', () async {
    final service = await SettingsService.load(directory: directory);
    addTearDown(service.dispose);
    expect(service.settings.language, isNull);
    await service.chooseLanguage(AppLanguage.korean);
    final restarted = await SettingsService.load(directory: directory);
    addTearDown(restarted.dispose);
    expect(restarted.settings.language, AppLanguage.korean);
    await restarted.resetAll();
    expect(restarted.settings.language, AppLanguage.korean);
    await restarted.chooseLanguage(AppLanguage.traditionalChinese);
    await service.reloadFromDisk();
    expect(service.settings.language, AppLanguage.traditionalChinese);
    expect(lt('设置'), '設置');
    final disk = jsonDecode(await File(service.filePath).readAsString()) as Map;
    expect(disk['language'], 'zh-Hant');
  });

  test('failed persistence does not complete first-run selection', () async {
    final service = await SettingsService.load(directory: directory);
    addTearDown(service.dispose);
    await Directory(service.filePath)
        .create(); // A directory cannot be overwritten as a file.
    await expectLater(
      service.chooseLanguage(AppLanguage.english),
      throwsA(isA<FileSystemException>()),
    );
    expect(service.settings.language, isNull);
  });

  testWidgets('first-run selector previews languages and saves confirmation', (
    tester,
  ) async {
    final service = _OnboardingService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(home: LanguagePage(service: service)));
    for (final language in AppLanguage.values) {
      expect(find.text(language.nativeName), findsOneWidget);
      await tester.tap(find.byKey(ValueKey(language.code)));
      await tester.pump();
      expect(
        find.text(AppStrings.translate('继续', const [], language)),
        findsOneWidget,
      );
      expect(service.settings.language, isNull);
    }
    await tester.tap(find.byKey(const ValueKey('confirmLanguage')));
    await tester.pumpAndSettle();
    expect(service.settings.language, AppLanguage.korean);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('app gates the viewer and applies the confirmed locale', (
    tester,
  ) async {
    final service = _OnboardingService();
    final state = ViewerState(
      settingsService: service,
      folder: FolderService(service.settings),
      images: ImageService(service.settings),
      marks: _Marks(),
    );
    addTearDown(service.dispose);
    addTearDown(state.dispose);
    await tester.pumpWidget(LimeApp(state: state));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePage), findsOneWidget);
    expect(find.byType(ViewerPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('en')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirmLanguage')));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePage), findsNothing);
    expect(find.byType(ViewerPage), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings tabs render in every language without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = await SettingsService.load(directory: directory);
    addTearDown(service.dispose);
    final images = ImageService(service.settings);
    final folder = FolderService(service.settings);
    final state = ViewerState(
      settingsService: service,
      folder: folder,
      images: images,
      marks: _Marks(),
    );
    addTearDown(state.dispose);
    const tabs = [
      '窗口与启动',
      '外观',
      '查看',
      '拼页与滚动',
      '动画与过渡',
      '鼠标',
      '快捷键',
      '性能',
      '文件',
      '解码器',
      '关于',
    ];
    for (final language in AppLanguage.values) {
      service.settings.language = language;
      AppStrings.language = language;
      await tester.pumpWidget(
        MaterialApp(
          locale: language.locale,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: AppLanguage.values.map((l) => l.locale),
          home: Material(
            child: SettingsPage(
              key: ValueKey(language),
              state: state,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final tab in tabs) {
        await tester.tap(find.text(lt(tab)).first);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${language.code}: $tab',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
