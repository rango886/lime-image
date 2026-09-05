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

  /// 配置目录。按「已有配置 → exe 同目录（便携）→ 系统 AppData」的顺序决定，
  /// 结果缓存。
  ///
  /// 不能再无条件用 `Directory.current`：从资源管理器双击关联文件启动时 CWD
  /// 不可控（可能是 System32），会导致配置读不到、写不进去。
  static Future<Directory> configDir() async {
    final cached = _configDir;
    if (cached != null) return cached;

    // 1. 旧版本把配置写在工作目录，已有就继续用，保证升级不丢设置
    final cwd = Directory.current;
    if (File(p.join(cwd.path, 'settings.json')).existsSync()) {
      return _configDir = cwd;
    }
    // 2. 便携模式：exe 同目录（除非它在系统保护目录里）。
    // 跑在 dart / flutter_tester 里时不能这么干，否则会往 SDK 目录里写配置。
    final exeDir = Directory(p.dirname(Platform.resolvedExecutable));
    final hostedByToolchain = const {
      'dart',
      'dart.exe',
      'flutter_tester',
      'flutter_tester.exe',
    }.contains(p.basename(Platform.resolvedExecutable).toLowerCase());
    if (!hostedByToolchain &&
        (File(p.join(exeDir.path, 'settings.json')).existsSync() ||
            !_systemProtected(exeDir.path))) {
      return _configDir = exeDir;
    }
    // 3. 兜底：系统配置目录
    try {
      final dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      return _configDir = dir;
    } catch (_) {
      return _configDir = cwd;
    }
  }

  /// 写不进去的典型位置。刻意不用「真写一个探测文件」的办法：
  /// 那是开机关键路径上多出的两次同步 IO。真写失败时 saveNow() 已经会记日志。
  static bool _systemProtected(String path) {
    if (!Platform.isWindows) return false;
    final lower = path.toLowerCase();
    for (final key in const [
      'ProgramFiles',
      'ProgramFiles(x86)',
      'ProgramW6432',
      'windir',
    ]) {
      final base = Platform.environment[key];
      if (base != null &&
          base.isNotEmpty &&
          lower.startsWith(base.toLowerCase())) {
        return true;
      }
    }
    return lower.contains(r'\windowsapps\');
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
