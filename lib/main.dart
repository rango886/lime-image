import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'core/platform_ops.dart';
import 'models/enums.dart';
import 'models/settings.dart';
import 'services/folder_service.dart';
import 'services/image_service.dart';
import 'services/settings_service.dart';
import 'state/viewer_state.dart';
import 'ui/app.dart';

/// 冷启动埋点。`LIMEIMAGE_TRACE_BOOT=1` 时把各阶段耗时打到 stderr，
/// 改启动性能时先看这个，别靠猜。
final Stopwatch _boot = Stopwatch()..start();
final bool _traceBoot = Platform.environment['LIMEIMAGE_TRACE_BOOT'] == '1';
void _mark(String stage) {
  if (_traceBoot) {
    stderr.writeln('[boot ${_boot.elapsedMilliseconds}ms] $stage');
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  PlatformOps.initChannel();
  _mark('binding ready');

  final settingsService = await SettingsService.load();
  final cfg = settingsService.settings;
  _mark('settings loaded (${settingsService.filePath})');

  // 单实例：复用已有窗口
  if (cfg.instanceMode == InstanceMode.reuse) {
    final primary = await SingleInstance.acquire(
      args,
      onSecondInstance: (a) async {
        await windowManager.show();
        await windowManager.focus();
        final files = a.where((x) => !x.startsWith('-')).toList();
        if (files.isNotEmpty) PlatformOps.emitOpenFiles(files);
      },
    );
    if (!primary) {
      exit(0);
    }
    _mark('single instance acquired');
  }

  await windowManager.ensureInitialized();
  _mark('windowManager ready');

  // WindowOptions 里每多一项就多一趟 platform channel 往返（实测每趟 ~15ms），
  // 而且它们全排在 show() 前面。size / center 我们自己在回调里设，
  // title 由 runner 建窗时已经给了，skipTaskbar=false 本就是默认值 —— 全删。
  const options = WindowOptions(
    minimumSize: Size(420, 320),
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  // 只留「决定窗口初始外观」的那几个调用，其余（resizable / preventClose /
  // alwaysOnTop / 位置合法性校验）一律推到首帧之后。
  final savedBounds = cfg.startupPlacement == StartupPlacement.remember
      ? cfg.savedBounds
      : null;
  await windowManager.waitUntilReadyToShow(options, () async {
    _mark('readyToShow callback');
    if (savedBounds != null) {
      await windowManager.setBounds(savedBounds);
      if (cfg.savedMaximized && !cfg.startFullscreen) {
        await windowManager.maximize();
      }
    } else {
      await windowManager.setSize(Size(cfg.defaultWidth, cfg.defaultHeight));
      await windowManager.center();
    }
    // 注意：必须在「未最大化」的状态下进全屏，否则 Windows 上尺寸不生效
    if (cfg.startFullscreen) await windowManager.setFullScreen(true);
    await windowManager.show();
    await windowManager.focus();
  });
  _mark('window shown');

  final folder = FolderService(cfg);
  final images = ImageService(cfg);
  final marks = MarksService.deferred(); // 读盘在后台，不挡首帧
  final state = ViewerState(
    settingsService: settingsService,
    folder: folder,
    images: images,
    marks: marks,
  );
  state.isFullscreen = cfg.startFullscreen;

  // 设置变化时同步给各服务
  settingsService.addListener(() {
    folder.settings = settingsService.settings;
    images.settings = settingsService.settings;
    images.registry.ffmpegPath = settingsService.settings.ffmpegPath;
  });
  // 独立设置窗口写盘 -> 主窗口热加载并重新应用
  settingsService.onExternalChange = state.onSettingsChanged;

  runApp(LimeApp(state: state));
  _mark('runApp');

  // 首帧还在排版时就把解码跑起来（都是异步 IO，跟布局并行）。
  // 目标图会走 folder.seedSingle 的快路径，不等目录扫描。
  void initializeViewer() {
    state
        .initialize(args)
        .then((_) => _mark('first image ready'))
        .catchError((Object e) => debugPrint('[lime image] 启动打开失败: $e'));
  }

  if (cfg.language != null) {
    initializeViewer();
  } else {
    void onLanguageSelected() {
      if (settingsService.settings.language == null) return;
      settingsService.removeListener(onLanguageSelected);
      initializeViewer();
    }

    settingsService.addListener(onLanguageSelected);
  }

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    _mark('first frame');
    // 解码后端探测（WIC COM 枚举 / ffmpeg 定位 / isolate 池）全在这之后
    images.warmUp();
    settingsService.startWatchingExternalChanges();
    await _applyDeferredWindowOptions(cfg);
    if (savedBounds != null) await _ensureOnScreen(savedBounds);
    _mark('deferred window setup done');
  });
}

/// 不影响首屏外观、但需要在用户真的操作窗口前设好的那些选项
Future<void> _applyDeferredWindowOptions(Settings cfg) async {
  await _ensureWindowControlsEnabled();
  await windowManager.setPreventClose(true);
  if (cfg.alwaysOnTop) await windowManager.setAlwaysOnTop(true);
}

Future<void> _ensureWindowControlsEnabled() async {
  if (!Platform.isWindows && !Platform.isMacOS) return;
  try {
    await windowManager.setResizable(true);
    await windowManager.setMinimizable(true);
    await windowManager.setMaximizable(true);
  } catch (_) {}
}

/// 记住的窗口位置可能已经落在拔掉的副屏上。枚举显示器要 10~30ms，
/// 所以先无条件恢复位置，首帧之后再校验，不合法就拉回主屏中央。
Future<void> _ensureOnScreen(Rect bounds) async {
  if (await _boundsVisible(bounds)) return;
  await windowManager.setSize(bounds.size);
  await windowManager.center();
}

Future<bool> _boundsVisible(Rect bounds) async {
  try {
    final displays = await ScreenRetriever.instance.getAllDisplays();
    final center = bounds.center;
    for (final d in displays) {
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      if (rect.inflate(8).contains(center)) return true;
    }
  } catch (_) {
    return true;
  }
  return false;
}
