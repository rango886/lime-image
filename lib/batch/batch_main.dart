import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../core/platform_ops.dart';
import '../l10n/strings.dart';
import '../models/enums.dart';
import '../services/image_service.dart';
import '../services/settings_service.dart';
import '../ui/batch/batch_page.dart';
import '../ui/theme.dart';
import 'batch_state.dart';
import 'preset_store.dart';

/// 和看图窗口的单实例端口分开：右键多选时 Explorer 会给每个文件起一个进程，
/// 第一个进程开窗口，其余的把路径发过来后立即退出。
const int kBatchPort = 47824;

Future<void> runBatchMode(List<String> args) async {
  final paths = args.where((a) => !a.startsWith('--')).toList();

  final settingsService = await SettingsService.load();
  final cfg = settingsService.settings;
  if (cfg.language == null) {
    AppStrings.language = AppLanguage.fromLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
  }

  BatchState? state;
  final early = <String>[];
  final primary = await SingleInstance.acquire(
    args,
    port: kBatchPort,
    onSecondInstance: (a) async {
      final files = a.where((x) => !x.startsWith('--')).toList();
      final s = state;
      if (s == null) {
        early.addAll(files);
      } else {
        await s.addPaths(files);
      }
      await windowManager.show();
      await windowManager.focus();
    },
  );
  if (!primary) exit(0);

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    minimumSize: Size(900, 560),
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setSize(const Size(1320, 840));
    await windowManager.center();
    await windowManager.setTitle('Lime Image');
    await windowManager.show();
    await windowManager.focus();
  });

  final store = await PresetStore.open();
  final s = state = BatchState(settings: cfg, store: store);
  await s.init();
  final images = ImageService(cfg);

  runApp(BatchApp(service: settingsService, state: s, images: images));

  await s.addPaths([...paths, ...early]);
  early.clear();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    images.warmUp();
    try {
      await windowManager.setResizable(true);
      await windowManager.setMinimizable(true);
      await windowManager.setMaximizable(true);
    } catch (_) {}
  });
}

class BatchApp extends StatelessWidget {
  const BatchApp({
    super.key,
    required this.service,
    required this.state,
    required this.images,
  });

  final SettingsService service;
  final BatchState state;
  final ImageService images;

  @override
  Widget build(BuildContext context) {
    final cfg = service.settings;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lime Image',
      locale: AppStrings.language.locale,
      supportedLocales: AppLanguage.values.map((v) => v.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: switch (cfg.theme) {
        ThemePref.system => ThemeMode.system,
        ThemePref.light => ThemeMode.light,
        ThemePref.dark => ThemeMode.dark,
      },
      theme: LimeTheme.build(
        Brightness.light,
        cfg.accentColor,
        radius: cfg.cornerRadius,
        fontScale: cfg.uiFontScale,
      ),
      darkTheme: LimeTheme.build(
        Brightness.dark,
        cfg.accentColor,
        radius: cfg.cornerRadius,
        fontScale: cfg.uiFontScale,
      ),
      home: Material(
        child: BatchPage(state: state, images: images, settings: cfg),
      ),
    );
  }
}
