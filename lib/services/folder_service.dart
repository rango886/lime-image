import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../core/utils.dart';
import '../models/enums.dart';
import '../models/settings.dart';

class FileEntry {
  FileEntry(this.path, [int? size, DateTime? modified])
    : _size = size,
      _modified = modified;

  final String path;
  int? _size;
  DateTime? _modified;
  FileStat? _stat;

  /// 目录扫描时刻意不做 stat：几千张图的目录里那是秒级开销，而且它挡在
  /// 「开始解码第一张图」前面。真要用到（状态栏 / 按大小时间排序）再按需补。
  int get size => _size ??= _statSync()?.size ?? 0;
  DateTime get modified => _modified ??=
      _statSync()?.modified ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasStat => _size != null && _modified != null;

  void applyStat(FileStat st) {
    _size = st.size;
    _modified = st.modified;
  }

  FileStat? _statSync() {
    try {
      return _stat ??= File(path).statSync();
    } catch (_) {
      return null;
    }
  }

  String get name => p.basename(path);
  String get ext => p.extension(path).toLowerCase();
}

/// 目录扫描 / 排序 / 监听 / 压缩包（cbz）支持
class FolderService extends ChangeNotifier {
  FolderService(this.settings);

  Settings settings;

  String? directory;
  String? archivePath; // 当前浏览的是压缩包时的原始路径
  List<FileEntry> entries = [];
  int index = -1;
  bool loading = false;
  bool markedOnly = false;
  List<FileEntry>? _unfiltered;

  StreamSubscription<WatchEvent>? _watchSub;
  Timer? _watchDebounce;
  Timer? _watchStartTimer;
  int _randomSeed = 1;

  FileEntry? get current =>
      (index >= 0 && index < entries.length) ? entries[index] : null;
  String? get currentPath => current?.path;
  int get count => entries.length;
  bool get isEmpty => entries.isEmpty;

  /// 冷启动快路径：先只放要看的那一张，让解码立即开始；
  /// 完整目录列表由随后的 [open] 在后台补齐。
  void seedSingle(String path) {
    directory = p.dirname(path);
    archivePath = null;
    _unfiltered = null;
    markedOnly = false;
    entries = [FileEntry(path)];
    index = 0;
    loading = true;
    notifyListeners();
  }

  /// 打开图片 / 目录 / 压缩包
  Future<void> open(String rawPath) async {
    final path = p.normalize(rawPath.replaceAll('"', ''));
    if (await FileSystemEntity.isDirectory(path)) {
      await _loadDirectory(path, select: null);
      return;
    }
    if (isArchiveFile(path) && settings.openArchives) {
      await _openArchive(path);
      return;
    }
    await _loadDirectory(p.dirname(path), select: path);
  }

  Future<void> _openArchive(String path) async {
    loading = true;
    notifyListeners();
    try {
      final tmp = Directory(
        p.join(
          Directory.systemTemp.path,
          'limeimage_${path.hashCode.toUnsigned(32)}',
        ),
      );
      if (!await tmp.exists()) {
        await tmp.create(recursive: true);
        await extractFileToDisk(path, tmp.path);
      }
      archivePath = path;
      await _loadDirectory(tmp.path, select: null, recursive: true);
    } catch (e) {
      debugPrint('[lime image] 压缩包解析失败: $e');
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadDirectory(
    String dir, {
    String? select,
    bool recursive = false,
  }) async {
    loading = true;
    directory = dir;
    if (!recursive) archivePath = null;
    notifyListeners();

    final found = <FileEntry>[];
    try {
      final d = Directory(dir);
      final stream = d.list(recursive: recursive, followLinks: false);
      await for (final e in stream) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (!settings.includeHidden && name.startsWith('.')) continue;
        if (!isImageFile(e.path)) continue;
        // 默认列出所有认得出的图片，保持浏览连续性；
        // 只有用户明确要求“干净列表”时才按运行时解码能力过滤
        if (settings.hideUndecodableFiles && !isDecodableFile(e.path)) {
          continue;
        }
        // 注意：这里不做 stat。大目录下每个文件一次 await stat 是冷启动的大头，
        // 大小/时间由 FileEntry 按需或 _ensureStats() 批量补。
        found.add(FileEntry(e.path));
      }
    } catch (e) {
      debugPrint('[lime image] 目录扫描失败: $e');
    }

    entries = found;
    if (_sortNeedsStat) await _ensureStats();
    _applySort();
    if (select != null) {
      index = entries.indexWhere((e) => p.equals(e.path, select));
      if (index < 0 && await File(select).exists()) {
        // 扩展名不在支持列表里，也允许单独打开
        entries.insert(0, FileEntry(select));
        index = 0;
      }
    } else {
      index = entries.isEmpty ? -1 : 0;
    }
    loading = false;
    _startWatching();
    notifyListeners();
  }

  Future<void> refresh() async {
    final keep = currentPath;
    if (directory == null) return;
    await _loadDirectory(
      directory!,
      select: keep,
      recursive: archivePath != null,
    );
  }

  void _startWatching() {
    _watchSub?.cancel();
    _watchSub = null;
    _watchStartTimer?.cancel();
    if (!settings.watchFolder || directory == null || archivePath != null) {
      return;
    }
    // DirectoryWatcher 启动时会自己先列一遍目录，冷启动时别跟首屏抢 IO
    _watchStartTimer = Timer(const Duration(seconds: 2), _beginWatch);
  }

  void _beginWatch() {
    if (!settings.watchFolder || directory == null || archivePath != null) {
      return;
    }
    try {
      final w = DirectoryWatcher(
        directory!,
        pollingDelay: const Duration(seconds: 2),
      );
      _watchSub = w.events.listen((_) {
        _watchDebounce?.cancel();
        _watchDebounce = Timer(const Duration(milliseconds: 500), refresh);
      }, onError: (_) {});
    } catch (_) {}
  }

  bool get _sortNeedsStat =>
      settings.sortField == SortField.time ||
      settings.sortField == SortField.size;

  /// 批量补 stat（只在排序真的需要时跑）。分批并发，别一个一个 await。
  Future<void> _ensureStats() async {
    final pending = entries.where((e) => !e.hasStat).toList();
    if (pending.isEmpty) return;
    const batch = 64;
    for (var i = 0; i < pending.length; i += batch) {
      final slice = pending.skip(i).take(batch);
      await Future.wait(
        slice.map((e) async => e.applyStat(await File(e.path).stat())),
      );
    }
  }

  // —— 排序 ——
  void sortBy(SortField field, bool ascending) {
    settings.sortField = field;
    settings.sortAscending = ascending;
    if (field == SortField.random) {
      _randomSeed = DateTime.now().millisecondsSinceEpoch;
    }
    _resortKeepingCurrent();
  }

  void _resortKeepingCurrent() {
    // 按时间/大小排时先把 stat 补齐（异步），否则比较器里会触发成千上万次同步 stat
    if (_sortNeedsStat && entries.any((e) => !e.hasStat)) {
      _ensureStats().then((_) => _resortKeepingCurrent());
      return;
    }
    final keep = currentPath;
    _applySort();
    if (keep != null) index = entries.indexWhere((e) => e.path == keep);
    if (index < 0) index = entries.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void _applySort() {
    final asc = settings.sortAscending ? 1 : -1;
    switch (settings.sortField) {
      case SortField.name:
        entries.sort(
          (a, b) =>
              asc *
              (settings.naturalSort
                  ? naturalCompare(a.name, b.name)
                  : a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        );
      case SortField.time:
        entries.sort((a, b) => asc * a.modified.compareTo(b.modified));
      case SortField.size:
        entries.sort((a, b) => asc * a.size.compareTo(b.size));
      case SortField.type:
        entries.sort((a, b) {
          final c = a.ext.compareTo(b.ext);
          return asc * (c != 0 ? c : naturalCompare(a.name, b.name));
        });
      case SortField.random:
        final rnd = math.Random(_randomSeed);
        entries.shuffle(rnd);
    }
  }

  /// 只浏览标记过的文件
  void applyMarkFilter(Set<String> marked) {
    _unfiltered ??= entries;
    final keep = currentPath;
    entries = _unfiltered!.where((e) => marked.contains(e.path)).toList();
    markedOnly = true;
    index = keep == null ? 0 : entries.indexWhere((e) => e.path == keep);
    if (index < 0) index = entries.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void clearMarkFilter() {
    if (_unfiltered == null) return;
    final keep = currentPath;
    entries = _unfiltered!;
    _unfiltered = null;
    markedOnly = false;
    if (keep != null) index = entries.indexWhere((e) => e.path == keep);
    if (index < 0) index = entries.isEmpty ? -1 : 0;
    notifyListeners();
  }

  // —— 导航 ——
  bool goTo(int newIndex) {
    if (entries.isEmpty) return false;
    var i = newIndex;
    if (i < 0 || i >= entries.length) {
      if (!settings.wrapAround) {
        i = i.clamp(0, entries.length - 1);
      } else {
        i = ((i % entries.length) + entries.length) % entries.length;
      }
    }
    if (i == index) return false;
    index = i;
    notifyListeners();
    return true;
  }

  bool step(int delta) => goTo(index + delta);

  bool goToPath(String path) {
    final i = entries.indexWhere((e) => p.equals(e.path, path));
    if (i < 0) return false;
    return goTo(i);
  }

  bool get canGoNext =>
      settings.wrapAround ? entries.length > 1 : index < entries.length - 1;
  bool get canGoPrev => settings.wrapAround ? entries.length > 1 : index > 0;

  /// 相邻若干张（用于预取）
  List<String> neighbors(int radius) {
    final out = <String>[];
    for (var d = 1; d <= radius; d++) {
      for (final i in [index + d, index - d]) {
        var j = i;
        if (settings.wrapAround && entries.isNotEmpty) {
          j = ((i % entries.length) + entries.length) % entries.length;
        }
        if (j >= 0 && j < entries.length && j != index) {
          out.add(entries[j].path);
        }
      }
    }
    return out;
  }

  void removeCurrent() {
    if (index < 0 || index >= entries.length) return;
    entries.removeAt(index);
    if (entries.isEmpty) {
      index = -1;
    } else if (index >= entries.length) {
      index = entries.length - 1;
    }
    notifyListeners();
  }

  void replaceCurrentPath(String newPath) {
    if (current == null) return;
    final old = entries[index];
    entries[index] = FileEntry(
      newPath,
      old.hasStat ? old.size : null,
      old.hasStat ? old.modified : null,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _watchDebounce?.cancel();
    _watchStartTimer?.cancel();
    super.dispose();
  }
}
