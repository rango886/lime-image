import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/settings.dart';
import '../l10n/strings.dart';

class SettingsService extends ChangeNotifier {
  SettingsService._(this._file, this.settings) {
    AppStrings.language = settings.language ?? AppLanguage.simplifiedChinese;
  }

  @override
  void notifyListeners() {
    AppStrings.language = settings.language ?? AppLanguage.simplifiedChinese;
    super.notifyListeners();
  }

  /// Complete onboarding only after the selection has reached disk.
  Future<void> chooseLanguage(AppLanguage language) async {
    final previous = settings.language;
    settings.language = language;
    try {
      await saveNow(rethrowErrors: true);
    } catch (_) {
      settings.language = previous;
      rethrow;
    }
    notifyListeners();
  }

  final File _file;
  Settings settings;
  Timer? _debounce;

  static Directory? _configDir;

  /// 正式程序只使用 exe 同目录，不读取工作目录 / 图片目录中的配置。
  /// Dart / Flutter 测试宿主使用系统配置目录，避免向 SDK 写入文件。
  static Future<Directory> configDir() async {
    final cached = _configDir;
    if (cached != null) return cached;

    // 不按配置是否存在或目录是否受保护切换位置，读写始终保持一致。
    final exeDir = Directory(p.dirname(Platform.resolvedExecutable));
    final hostedByToolchain = const {
      'dart',
      'dart.exe',
      'flutter_tester',
      'flutter_tester.exe',
    }.contains(p.basename(Platform.resolvedExecutable).toLowerCase());
    if (!hostedByToolchain) return _configDir = exeDir;
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return _configDir = dir;
  }

  static Future<SettingsService> load({Directory? directory}) async {
    final dir = directory ?? await configDir();
    final file = File(p.join(dir.path, 'settings.json'));
    Settings s;
    try {
      // 开机关键路径上刻意用同步读：文件只有几 KB，而第一次异步 IO 要把
      // Dart 的 IO 线程池拉起来，实测反而更贵。也不先 exists() 再 read（少一次 stat）。
      s = Settings.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    } on PathNotFoundException {
      s = Settings();
    } on FileSystemException {
      s = Settings();
    } catch (e) {
      debugPrint('[lime image] 设置读取失败，使用默认值: $e');
      s = Settings();
    }
    return SettingsService._(file, s);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    stopWatchingExternalChanges();
    super.dispose();
  }

  /// 外部进程改动后的回调（主窗口拿它重新应用运行时状态）
  VoidCallback? onExternalChange;

  String get filePath => _file.path;

  // —— 外部（独立设置窗口进程）改动检测 ——
  DateTime? _diskStamp;
  Timer? _watch;

  /// 每秒看一眼配置文件，被独立设置窗口改过就热加载
  void startWatchingExternalChanges() {
    _watch ??= Timer.periodic(const Duration(seconds: 1), (_) => _checkDisk());
  }

  void stopWatchingExternalChanges() {
    _watch?.cancel();
    _watch = null;
  }

  Future<void> _checkDisk() async {
    try {
      if (!await _file.exists()) return;
      final stamp = await _file.lastModified();
      if (_diskStamp == null) {
        _diskStamp = stamp;
        return;
      }
      if (stamp.isAtSameMomentAs(_diskStamp!)) return;
      _diskStamp = stamp;
      await reloadFromDisk();
    } catch (_) {}
  }

  /// 从磁盘重新读取设置，保留本进程的会话字段（窗口位置 / 上次图片）
  Future<void> reloadFromDisk() async {
    try {
      final json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      final fresh = Settings.fromJson(json);
      fresh
        ..savedX = settings.savedX
        ..savedY = settings.savedY
        ..savedWidth = settings.savedWidth
        ..savedHeight = settings.savedHeight
        ..savedMaximized = settings.savedMaximized
        ..lastImagePath = settings.lastImagePath;
      settings = fresh;
      notifyListeners();
      onExternalChange?.call();
    } catch (e) {
      debugPrint('[lime image] 设置热加载失败: $e');
    }
  }

  /// 修改设置并保存（带防抖）
  void update(void Function(Settings s) fn, {bool notify = true}) {
    fn(settings);
    settings.invalidateKeymap();
    if (notify) notifyListeners();
    scheduleSave();
  }

  void scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow({bool rethrowErrors = false}) async {
    _debounce?.cancel();
    try {
      const encoder = JsonEncoder.withIndent('  ');
      await _file.writeAsString(encoder.convert(settings.toJson()));
      _diskStamp = await _file.lastModified();
    } catch (e) {
      debugPrint('[lime image] 设置保存失败: $e');
      if (rethrowErrors) rethrow;
    }
  }

  Future<void> resetAll() async {
    settings = Settings()..language = settings.language;
    notifyListeners();
    await saveNow();
  }

  Future<void> exportTo(String path) async {
    const encoder = JsonEncoder.withIndent('  ');
    await File(path).writeAsString(encoder.convert(settings.toJson()));
  }

  Future<void> importFrom(String path) async {
    final json =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final imported = Settings.fromJson(json);
    imported.language ??= settings.language;
    settings = imported;
    notifyListeners();
    await saveNow();
  }
}

/// 标记过的文件（跨会话保存）
class MarksService extends ChangeNotifier {
  MarksService._(this._file, this._marks);

  File? _file;
  final Set<String> _marks;
  Future<void>? _loading;

  /// 立即返回的版本：读盘在后台跑，不拖住首帧。
  /// 读到数据后 notify 一次，UI 自行刷新。
  factory MarksService.deferred() {
    final svc = MarksService._(null, <String>{});
    svc._loading = svc._loadFromDisk();
    return svc;
  }

  static Future<MarksService> load() async {
    final svc = MarksService.deferred();
    await svc._loading;
    return svc;
  }

  Future<File> _resolveFile() async => _file ??= File(
    p.join((await SettingsService.configDir()).path, 'marks.json'),
  );

  Future<void> _loadFromDisk() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List;
      final before = _marks.length;
      _marks.addAll(list.map((e) => e.toString()));
      if (_marks.length != before) notifyListeners();
    } catch (_) {}
  }

  Set<String> get all => _marks;
  bool isMarked(String path) => _marks.contains(path);
  int get count => _marks.length;

  void toggle(String path) {
    if (!_marks.remove(path)) _marks.add(path);
    notifyListeners();
    _save();
  }

  void clear() {
    _marks.clear();
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      // 等初次读盘结束，否则会把盘上已有的标记覆盖掉
      await _loading;
      final file = await _resolveFile();
      await file.writeAsString(jsonEncode(_marks.toList()));
    } catch (_) {}
  }
}
