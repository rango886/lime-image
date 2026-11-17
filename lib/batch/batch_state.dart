import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/utils.dart';
import '../l10n/strings.dart';
import '../models/settings.dart';
import 'convert_preset.dart';
import 'engine/convert_engine.dart';
import 'engine/convert_pool.dart';
import 'engine/ffmpeg_codec.dart';
import 'engine/pixels.dart';
import 'naming.dart';
import 'preset_store.dart';

enum ItemStatus { pending, running, done, skipped, failed }

class BatchItem {
  BatchItem(this.path, this.root, this.size);
  final String path;

  /// 从哪个文件夹展开出来的（直接加的文件为 null）
  final String? root;
  final int size;
  bool checked = true;
  ItemStatus status = ItemStatus.pending;
  String? message;
  String? outPath;
  int outSize = 0;

  String get name => p.basename(path);
}

enum PreviewMode { original, result, sideBySide }

/// 预览：当前选中图片按当前参数跑一遍的结果
class PreviewData {
  PreviewData(this.path);
  final String path;
  ConvertResult? result;
  ui.Image? source;
  ui.Image? output;
  String? targetPath;
  int outBytes = 0;
  bool loading = true;

  void dispose() {
    source?.dispose();
    output?.dispose();
  }
}

class RunSummary {
  int done = 0;
  int skipped = 0;
  int failed = 0;
  int inBytes = 0;
  int outBytes = 0;
  bool cancelled = false;
  String? lastDir;
  Duration elapsed = Duration.zero;
}

class BatchState extends ChangeNotifier {
  BatchState({required this.settings, required this.store});

  final Settings settings;
  final PresetStore store;

  final List<BatchItem> items = [];
  final Set<String> _known = {};
  int selected = -1;
  bool onlyFailed = false;
  bool recursive = true;

  ConvertPreset preset = ConvertPreset();
  String? presetName;
  String _savedSnapshot = '';
  List<NamedPreset> presets = [];
  List<String> recentDirs = [];
  final Set<String> collapsed = {};

  /// 单张图手动拖过的裁切框（归一化 x, y, w, h）
  final Map<String, List<double>> cropOverrides = {};

  PreviewMode previewMode = PreviewMode.result;
  bool zoomActual = false;
  PreviewData? preview;

  // 编码能力
  String? ffmpegExe;
  Set<String> ffmpegEncoders = {};
  bool capsReady = false;

  // 运行状态
  bool running = false;
  int runTotal = 0;
  int runDone = 0;
  DateTime? _runStart;
  RunSummary? summary;
  ConvertPool? _pool;
  ConvertPool? _previewPool;

  bool get dirty => presetName == null || preset.encode() != _savedSnapshot;

  List<BatchItem> get visibleItems => onlyFailed
      ? items.where((i) => i.status == ItemStatus.failed).toList()
      : items;

  BatchItem? get current =>
      selected >= 0 && selected < items.length ? items[selected] : null;

  int get checkedCount => items.where((i) => i.checked).length;
  int get totalBytes => items.fold(0, (s, i) => s + i.size);
  int get failedCount =>
      items.where((i) => i.status == ItemStatus.failed).length;

  Duration? get eta {
    final start = _runStart;
    if (!running || start == null || runDone == 0) return null;
    final spent = DateTime.now().difference(start);
    return spent * ((runTotal - runDone) / runDone);
  }

  // ---------------------------------------------------------------------------
  // 启动 / 持久化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    presets = await store.list();
    final st = await store.readState();
    if (st['preset'] is Map) {
      preset = ConvertPreset.fromJson((st['preset'] as Map).cast());
    }
    final name = st.isEmpty
        ? (presets.where((x) => x.name == lt('网页 JPEG')).firstOrNull ??
                  presets.firstOrNull)
              ?.name
        : st['presetName'] as String?;
    final match = presets.where((x) => x.name == name).firstOrNull;
    if (match != null) {
      presetName = match.name;
      _savedSnapshot = match.preset.encode();
      if (st['preset'] is! Map) preset = match.preset.copy();
    }
    recentDirs = ((st['recentDirs'] as List?) ?? const []).cast<String>();
    recursive = st['recursive'] as bool? ?? true;
    collapsed.addAll(
      ((st['collapsed'] as List?) ?? const ['crop', 'resize', 'name', 'meta'])
          .cast<String>(),
    );
    previewMode = PreviewMode.values.firstWhere(
      (m) => m.name == st['previewMode'],
      orElse: () => PreviewMode.result,
    );
    notifyListeners();
    unawaited(_probeCaps());
  }

  Timer? _saveTimer;
  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      store.writeState({
        'preset': preset.toJson(),
        'presetName': presetName,
        'recentDirs': recentDirs,
        'recursive': recursive,
        'collapsed': collapsed.toList(),
        'previewMode': previewMode.name,
      });
    });
  }

  Future<void> _probeCaps() async {
    ffmpegExe = await FfmpegEncoder.locate(settings.ffmpegPath);
    if (ffmpegExe != null) {
      ffmpegEncoders = await FfmpegEncoder.encoders(ffmpegExe!);
    }
    capsReady = true;
    notifyListeners();
  }

  /// 这种输出格式本机能不能编码
  bool canEncode(OutputFormat f) {
    final win = Platform.isWindows;
    switch (f) {
      case OutputFormat.keep:
        return true;
      case OutputFormat.jpeg:
        return win || ffmpegEncoders.contains('mjpeg');
      case OutputFormat.png:
        return win || ffmpegEncoders.contains('png');
      case OutputFormat.tiff:
        return win || ffmpegEncoders.contains('tiff');
      case OutputFormat.bmp:
        return win || ffmpegEncoders.contains('bmp');
      case OutputFormat.webp:
        return ffmpegEncoders.contains('libwebp');
      case OutputFormat.avif:
        return ffmpegEncoders.contains('libaom-av1') ||
            ffmpegEncoders.contains('libsvtav1');
    }
  }

  // ---------------------------------------------------------------------------
  // 文件列表
  // ---------------------------------------------------------------------------

  Future<void> addPaths(List<String> paths) async {
    final before = items.length;
    for (final raw in paths) {
      final path = p.normalize(raw);
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        await _addDir(path);
      } else if (type == FileSystemEntityType.file && isImageFile(path)) {
        await _addFile(path, null);
      }
    }
    if (items.length == before) return;
    if (selected < 0) select(before);
    notifyListeners();
  }

  Future<void> _addDir(String dir) async {
    final files = <String>[];
    final skipName = preset.place == OutputPlace.subfolder
        ? preset.subfolder.trim()
        : null;
    Future<void> walk(Directory d) async {
      final subdirs = <Directory>[];
      try {
        await for (final e in d.list(followLinks: false)) {
          if (e is File && isImageFile(e.path)) {
            files.add(e.path);
          } else if (e is Directory && recursive) {
            if (skipName != null &&
                p.basename(e.path).toLowerCase() == skipName.toLowerCase()) {
              continue;
            }
            subdirs.add(e);
          }
        }
      } catch (_) {}
      for (final s in subdirs) {
        await walk(s);
      }
    }

    await walk(Directory(dir));
    files.sort(naturalCompare);
    for (final f in files) {
      await _addFile(f, dir);
    }
  }

  Future<void> _addFile(String path, String? root) async {
    final key = path.toLowerCase();
    if (!_known.add(key)) return;
    var size = 0;
    try {
      size = await File(path).length();
    } catch (_) {}
    items.add(BatchItem(path, root, size));
  }

  void select(int index) {
    if (index < 0 || index >= items.length) return;
    if (selected == index) return;
    selected = index;
    notifyListeners();
    schedulePreview(immediate: true);
  }

  void selectRelative(int delta) {
    final list = visibleItems;
    if (list.isEmpty) return;
    final cur = current;
    var i = cur == null ? -1 : list.indexOf(cur);
    i = (i + delta).clamp(0, list.length - 1);
    select(items.indexOf(list[i]));
  }

  void toggleChecked(BatchItem item, [bool? v]) {
    item.checked = v ?? !item.checked;
    notifyListeners();
  }

  void setAllChecked(bool v) {
    for (final i in items) {
      i.checked = v;
    }
    notifyListeners();
  }

  void remove(BatchItem item) {
    if (running) return;
    final idx = items.indexOf(item);
    if (idx < 0) return;
    items.removeAt(idx);
    _known.remove(item.path.toLowerCase());
    cropOverrides.remove(item.path);
    if (items.isEmpty) {
      selected = -1;
      _clearPreview();
    } else if (selected >= items.length || idx == selected) {
      selected = -1;
      select(idx.clamp(0, items.length - 1));
    } else if (idx < selected) {
      selected--;
    }
    notifyListeners();
  }

  void clear() {
    if (running) return;
    items.clear();
    _known.clear();
    cropOverrides.clear();
    selected = -1;
    summary = null;
    _clearPreview();
    notifyListeners();
  }

  void removeFinished() {
    if (running) return;
    final cur = current;
    items.removeWhere((i) {
      final drop = i.status == ItemStatus.done;
      if (drop) _known.remove(i.path.toLowerCase());
      return drop;
    });
    selected = cur == null ? -1 : items.indexOf(cur);
    if (selected < 0 && items.isNotEmpty) {
      select(0);
    } else if (items.isEmpty) {
      _clearPreview();
    }
    notifyListeners();
  }

  void setOnlyFailed(bool v) {
    onlyFailed = v;
    notifyListeners();
  }

  void setRecursive(bool v) {
    recursive = v;
    _persist();
    notifyListeners();
  }

  void sortBy(int Function(BatchItem, BatchItem) cmp) {
    final cur = current;
    items.sort(cmp);
    selected = cur == null ? -1 : items.indexOf(cur);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 参数 / 预设
  // ---------------------------------------------------------------------------

  void update(void Function(ConvertPreset p) fn) {
    fn(preset);
    _persist();
    notifyListeners();
    schedulePreview();
  }

  void toggleSection(String id) {
    if (!collapsed.remove(id)) collapsed.add(id);
    _persist();
    notifyListeners();
  }

  void setPreviewMode(PreviewMode m) {
    previewMode = m;
    _persist();
    notifyListeners();
  }

  void toggleZoom() {
    zoomActual = !zoomActual;
    notifyListeners();
  }

  void applyPreset(NamedPreset np) {
    preset = np.preset.copy();
    presetName = np.name;
    _savedSnapshot = np.preset.encode();
    _persist();
    notifyListeners();
    schedulePreview(immediate: true);
  }

  Future<void> reloadPresets() async {
    presets = await store.list();
    notifyListeners();
  }

  Future<void> savePreset([String? asName]) async {
    final name = asName ?? presetName;
    if (name == null || name.trim().isEmpty) return;
    await store.save(name.trim(), preset);
    presetName = name.trim();
    _savedSnapshot = preset.encode();
    _persist();
    await reloadPresets();
  }

  Future<void> deletePreset(String name) async {
    await store.delete(name);
    if (presetName == name) presetName = null;
    _persist();
    await reloadPresets();
  }

  Future<void> renamePreset(String from, String to) async {
    final np = presets.where((x) => x.name == from).firstOrNull;
    if (np == null || to.trim().isEmpty) return;
    await store.rename(from, to.trim(), np.preset);
    if (presetName == from) presetName = to.trim();
    _persist();
    await reloadPresets();
  }

  Future<void> importPreset(String file) async {
    final np = await store.importFile(file);
    if (np == null) return;
    await reloadPresets();
    final m = presets.where((x) => x.name == np.name).firstOrNull;
    if (m != null) applyPreset(m);
  }

  Future<void> exportPreset(String file) =>
      store.exportFile(file, presetName ?? 'preset', preset);

  void rememberDir(String dir) {
    recentDirs.remove(dir);
    recentDirs.insert(0, dir);
    if (recentDirs.length > 8) recentDirs.removeRange(8, recentDirs.length);
    _persist();
  }

  // ---------------------------------------------------------------------------
  // 单张裁切
  // ---------------------------------------------------------------------------

  List<double>? cropOverrideFor(String path) => cropOverrides[path];

  void setCropOverride(String path, List<double> rect) {
    cropOverrides[path] = rect;
    notifyListeners();
    schedulePreview();
  }

  void clearCropOverride(String path) {
    if (cropOverrides.remove(path) == null) return;
    notifyListeners();
    schedulePreview(immediate: true);
  }

  // ---------------------------------------------------------------------------
  // 预览
  // ---------------------------------------------------------------------------

  Timer? _previewTimer;
  bool _previewBusy = false;
  bool _previewAgain = false;
  int _previewSeq = 0;

  void schedulePreview({bool immediate = false}) {
    _previewTimer?.cancel();
    _previewTimer = Timer(
      Duration(milliseconds: immediate ? 0 : 280),
      _runPreview,
    );
  }

  void _clearPreview() {
    preview?.dispose();
    preview = null;
  }

  Future<void> _runPreview() async {
    final item = current;
    if (item == null) return;
    if (_previewBusy) {
      _previewAgain = true;
      return;
    }
    _previewBusy = true;
    final seq = ++_previewSeq;
    final samePath = preview?.path == item.path;
    if (!samePath) {
      _clearPreview();
      preview = PreviewData(item.path);
    }
    preview!.loading = true;
    notifyListeners();

    _previewPool ??= ConvertPool(size: 1, ffmpegPath: settings.ffmpegPath);
    final snapshot = preset.copy();
    final r = await _previewPool!.submit(
      ConvertJob(
        path: item.path,
        preset: snapshot,
        cropOverride: cropOverrides[item.path],
        previewMax: 2048,
      ),
    );
    try {
      final pv = preview;
      if (pv != null && pv.path == item.path && seq == _previewSeq) {
        final src = r.srcPreview != null ? await _toImage(r.srcPreview!) : null;
        ui.Image? out;
        final bytes = r.bytes;
        if (bytes != null && _skiaDecodable(r.format)) {
          out = await _decodeEncoded(bytes);
        }
        if (out == null && r.outPreview != null) {
          out = await _toImage(r.outPreview!);
        }
        if (src != null) {
          pv.source?.dispose();
          pv.source = src;
        }
        pv.output?.dispose();
        pv.output = out;
        r.bytes = null; // 只留尺寸信息
        r.srcPreview = null;
        r.outPreview = null;
        pv.result = r;
        pv.targetPath = r.ok ? previewTargetPath(item, r) : null;
        if (bytes != null) pv.outBytes = bytes.length;
        pv.loading = false;
        notifyListeners();
      }
    } finally {
      _previewBusy = false;
      if (_previewAgain) {
        _previewAgain = false;
        unawaited(_runPreview());
      }
    }
  }

  static bool _skiaDecodable(OutputFormat f) =>
      f == OutputFormat.jpeg ||
      f == OutputFormat.png ||
      f == OutputFormat.webp ||
      f == OutputFormat.bmp;

  static Future<ui.Image> _toImage(Pix px) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(px.data);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: px.width,
      height: px.height,
      pixelFormat: ui.PixelFormat.bgra8888,
    );
    try {
      final codec = await desc.instantiateCodec();
      final f = await codec.getNextFrame();
      codec.dispose();
      return f.image;
    } finally {
      desc.dispose();
      buf.dispose();
    }
  }

  static Future<ui.Image?> _decodeEncoded(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final f = await codec.getNextFrame();
      codec.dispose();
      return f.image;
    } catch (_) {
      return null;
    }
  }

  /// 预览时显示的目标路径（不占用名字）
  String previewTargetPath(BatchItem item, ConvertResult r) {
    final checked = items.where((i) => i.checked).toList();
    final idx = checked.indexOf(item);
    final seq = preset.seqStart + (idx < 0 ? 0 : idx);
    final name = renderName(
      preset.nameTemplate,
      source: item.path,
      seq: seq,
      digits: preset.seqDigits,
      width: r.outW,
      height: r.outH,
      taken: r.taken,
    );
    return p.join(outputDir(preset, item.path, item.root), '$name.${r.ext}');
  }

  // ---------------------------------------------------------------------------
  // 执行
  // ---------------------------------------------------------------------------

  Future<RunSummary?> start() async {
    if (running) return null;
    final list = items.where((i) => i.checked).toList();
    if (list.isEmpty) return null;
    running = true;
    _cancelled = false;
    summary = null;
    runTotal = list.length;
    runDone = 0;
    _runStart = DateTime.now();
    final sum = RunSummary();
    for (final i in list) {
      i.status = ItemStatus.pending;
      i.message = null;
      i.outPath = null;
      i.outSize = 0;
    }
    notifyListeners();

    final snapshot = preset.copy();
    final claimed = <String>{};
    final pool = _pool ??= ConvertPool(ffmpegPath: settings.ffmpegPath);
    final now = DateTime.now();

    final futures = <Future<void>>[];
    var nextToMark = 0;
    void markNext() {
      while (nextToMark < list.length &&
          list[nextToMark].status != ItemStatus.pending) {
        nextToMark++;
      }
      if (nextToMark < list.length) {
        list[nextToMark++].status = ItemStatus.running;
      }
    }

    for (var k = 0; k < list.length; k++) {
      final item = list[k];
      final seq = snapshot.seqStart + k;
      futures.add(
        pool
            .submit(
              ConvertJob(
                path: item.path,
                preset: snapshot,
                cropOverride: cropOverrides[item.path],
              ),
            )
            .then((r) async {
              if (r.skipped == '已取消') return;
              item.status = ItemStatus.running;
              await _finish(item, r, snapshot, seq, claimed, sum, now);
              runDone++;
              if (!_cancelled) markNext();
              notifyListeners();
            }),
      );
    }
    for (var k = 0; k < pool.size; k++) {
      markNext();
    }
    notifyListeners();
    await Future.wait(futures);

    sum.elapsed = DateTime.now().difference(_runStart!);
    sum.cancelled = _cancelled;
    for (final i in list) {
      if (i.status == ItemStatus.running) i.status = ItemStatus.pending;
    }
    running = false;
    summary = sum;
    notifyListeners();
    return sum;
  }

  bool _cancelled = false;

  void cancel() {
    if (!running) return;
    _cancelled = true;
    _pool?.cancelPending();
    notifyListeners();
  }

  void dismissSummary() {
    summary = null;
    notifyListeners();
  }

  void retryFailed() {
    for (final i in items) {
      i.checked = i.status == ItemStatus.failed;
    }
    summary = null;
    onlyFailed = false;
    notifyListeners();
    start();
  }

  Future<void> _finish(
    BatchItem item,
    ConvertResult r,
    ConvertPreset preset,
    int seq,
    Set<String> claimed,
    RunSummary sum,
    DateTime now,
  ) async {
    sum.inBytes += item.size;
    if (r.error != null) {
      item.status = ItemStatus.failed;
      item.message = r.error;
      sum.failed++;
      return;
    }
    if (r.skipped != null) {
      item.status = ItemStatus.skipped;
      item.message = r.skipped;
      sum.skipped++;
      return;
    }
    try {
      final name = renderName(
        preset.nameTemplate,
        source: item.path,
        seq: seq,
        digits: preset.seqDigits,
        width: r.outW,
        height: r.outH,
        taken: r.taken,
        now: now,
      );
      final dir = outputDir(preset, item.path, item.root);
      final ext = r.keepOriginal
          ? p.extension(item.path).replaceFirst('.', '')
          : r.ext;
      final target = resolveConflict(
        p.join(dir, '$name.$ext'),
        preset.conflict,
        claimed,
      );
      if (target == null) {
        item.status = ItemStatus.skipped;
        item.message = '已存在';
        sum.skipped++;
        return;
      }
      await Directory(dir).create(recursive: true);
      final tmp = File('$target.limetmp');
      if (r.keepOriginal) {
        await File(item.path).copy(tmp.path);
      } else {
        await tmp.writeAsBytes(r.bytes!, flush: true);
      }
      final out = await tmp.rename(target);
      if (preset.keepTimestamps) {
        try {
          await out.setLastModified(await File(item.path).lastModified());
        } catch (_) {}
      }
      item.outPath = target;
      item.outSize = await out.length();
      item.status = ItemStatus.done;
      item.message = r.keepOriginal ? '保留原图' : null;
      sum.done++;
      sum.outBytes += item.outSize;
      sum.lastDir = dir;
    } catch (e) {
      item.status = ItemStatus.failed;
      item.message = e is FileSystemException
          ? '${e.message} ${e.osError?.message ?? ''}'.trim()
          : '$e';
      sum.failed++;
    }
  }

  bool get cancelRequested => _cancelled;

  @override
  void dispose() {
    _saveTimer?.cancel();
    _previewTimer?.cancel();
    _pool?.dispose();
    _previewPool?.dispose();
    _clearPreview();
    super.dispose();
  }
}
