import 'dart:async';
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
  // 窗口设好尺寸 / 位置并显示之前，绝不能由别的进程触发 show()：
  // 否则窗口会先在 runner 默认的左上角闪出来。
  var shown = false;
  // Explorer 多选时每个文件一个进程，路径会密集地一条条到达。
  // 放进缓冲区等安静下来一次性处理，只激活一次窗口，避免反复闪烁。
  final pending = <String>[];
  Timer? flushTimer;
  Future<void> flushPending() async {
    final s = state;
    if (s == null || !shown || pending.isEmpty) return;
    final files = List<String>.of(pending);
    pending.clear();
    await s.addPaths(files);
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.focus();
    } catch (_) {}
  }

  final primary = await SingleInstance.acquire(
    args,
    port: kBatchPort,
    onSecondInstance: (a) {
      final files = a.where((x) => !x.startsWith('--'));
      if (state == null) {
        early.addAll(files);
        return;
      }
      pending.addAll(files);
      flushTimer?.cancel();
      flushTimer = Timer(const Duration(milliseconds: 250), flushPending);
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
    await windowManager.setSize(const Size(1440, 900));
    await windowManager.center();
    await windowManager.setTitle('Lime Image');
    await windowManager.show();
    await windowManager.focus();
  });
  shown = true;

  final store = await PresetStore.open();
  final s = state = BatchState(settings: cfg, store: store);
  await s.init();
  final images = ImageService(cfg);

  runApp(BatchApp(service: settingsService, state: s, images: images));

  await s.addPaths([...paths, ...early]);
  early.clear();
  // init / 首批 addPaths 期间来的路径
  if (pending.isNotEmpty) {
    flushTimer?.cancel();
    flushTimer = Timer(const Duration(milliseconds: 250), flushPending);
  }

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
