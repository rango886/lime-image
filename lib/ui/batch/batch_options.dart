import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../batch/batch_state.dart';
import '../../batch/convert_preset.dart';
import '../../batch/naming.dart';
import '../../l10n/strings.dart';
import '../widgets.dart';

const double _labelW = 76;

/// 右栏：预设和各组参数
class BatchOptions extends StatefulWidget {
  const BatchOptions({super.key, required this.state});
  final BatchState state;

  @override
  State<BatchOptions> createState() => _BatchOptionsState();
}

class _BatchOptionsState extends State<BatchOptions> {
  final TextEditingController _template = TextEditingController();
  final ScrollController _scroll = ScrollController();

  BatchState get s => widget.state;
  ConvertPreset get c => s.preset;

  @override
  void dispose() {
    _template.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _set(void Function(ConvertPreset p) fn) => s.update(fn);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _PresetBar(state: s),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: AbsorbPointer(
            absorbing: s.running,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: s.running ? 0.5 : 1,
              child: Scrollbar(
                controller: _scroll,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  children: [
                    ..._section('orient', lt('方向'), _orientSummary(), _orient),
                    ..._section('crop', lt('裁切'), _cropSummary(), _crop),
                    ..._section('resize', lt('尺寸'), _resizeSummary(), _resize),
                    ..._section('format', lt('格式'), _formatSummary(), _format),
                    ..._section('output', lt('输出'), _outputSummary(), _output),
                    ..._section('name', lt('文件名'), _nameSummary(), _name),
                    ..._section('meta', lt('元数据'), c.metadata.label, _meta),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _section(
    String id,
    String title,
    String summary,
    List<Widget> Function() body,
  ) {
    final folded = s.collapsed.contains(id);
    return [
      SectionHeader(
        title,
        collapsed: folded,
        summary: summary,
        onToggle: () => s.toggleSection(id),
      ),
      if (!folded) ...[...body(), const SizedBox(height: 10)],
    ];
  }

  Widget _row(String label, Widget control) =>
      SettingRow(label, control, labelWidth: _labelW);

  Widget _drop<T>(
    String label,
    T value,
    List<T> items,
    String Function(T) labelOf,
    ValueChanged<T> onChanged,
  ) => _row(
    label,
    LimeDropdown<T>(
      value: value,
      items: items,
      labelOf: labelOf,
      onChanged: onChanged,
      width: double.infinity,
    ),
  );

  Widget _switch(String label, bool v, ValueChanged<bool> onChanged) =>
      _row(label, LimeSwitch(value: v, onChanged: onChanged));

  Widget _slider(
    String label,
    num v,
    double min,
    double max,
    ValueChanged<int> onChanged, {
    String unit = '',
  }) => _row(
    label,
    LimeSlider(
      value: v.toDouble(),
      min: min,
      max: max,
      divisions: (max - min).round(),
      unit: unit,
      valueWidth: 40,
      onChanged: (x) => onChanged(x.round()),
    ),
  );

  Widget _num(
    double v,
    ValueChanged<double> onChanged, {
    String? unit,
    double min = 0,
    double max = 100000,
    double width = 84,
    int digits = 0,
  }) => LimeNumberField(
    value: v,
    onChanged: onChanged,
    unit: unit,
    min: min,
    max: max,
    width: width,
    digits: digits,
  );

  Widget _times() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text('×', style: Theme.of(context).textTheme.bodyMedium),
  );

  // —— 方向 ——
  String _orientSummary() {
    final parts = <String>[
      if (c.rotate != RotateBy.none) c.rotate.label,
      if (c.flipH) lt('水平翻转'),
      if (c.flipV) lt('垂直翻转'),
    ];
    return parts.isEmpty ? lt('不变') : parts.join(' · ');
  }

  List<Widget> _orient() => [
    _switch(lt('自动摆正'), c.autoOrient, (v) => _set((p) => p.autoOrient = v)),
    _row(
      lt('旋转'),
      LimeSegmented<RotateBy>(
        value: c.rotate,
        items: RotateBy.values,
        labelOf: (r) => r.label,
        onChanged: (v) => _set((p) => p.rotate = v),
      ),
    ),
    _row(
      lt('翻转'),
      Row(
        children: [
          LimeIconToggle(
            icon: Icons.swap_horiz,
            tooltip: lt('水平翻转'),
            value: c.flipH,
            onChanged: (v) => _set((p) => p.flipH = v),
          ),
          const SizedBox(width: 6),
          LimeIconToggle(
            icon: Icons.swap_vert,
            tooltip: lt('垂直翻转'),
            value: c.flipV,
            onChanged: (v) => _set((p) => p.flipV = v),
          ),
        ],
      ),
    ),
    if (c.hasUserTransform)
      _row(
        lt('应用于'),
        LimeSegmented<RotateScope>(
          value: c.rotateScope,
          items: RotateScope.values,
          labelOf: (v) => v.label,
          onChanged: (v) => _set((p) => p.rotateScope = v),
        ),
      ),
  ];

  // —— 裁切 ——
  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  String _cropSummary() {
    final base = switch (c.crop) {
      CropMode.none => c.crop.label,
      CropMode.ratio => '${_fmtNum(c.ratioW)}:${_fmtNum(c.ratioH)}',
      CropMode.margin => c.crop.label,
      CropMode.fixed => '${c.fixedW} × ${c.fixedH}',
      CropMode.trim => c.crop.label,
    };
    return c.cropAlignActive ? '$base · ÷${c.cropAlign}' : base;
  }

  static const _aligns = [8, 16, 32, 64, 128];

  /// 对齐倍数：预设 + 自定义，0 = 关
  List<Widget> _alignRows(int v, ValueChanged<int> onChanged) => [
    _row(
      lt('对齐倍数'),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          LimeChip(
            label: lt('关'),
            dim: true,
            selected: v <= 1,
            onTap: () => onChanged(0),
          ),
          for (final n in _aligns)
            LimeChip(
              label: '$n',
              dim: true,
              selected: v == n,
              onTap: () => onChanged(n),
            ),
        ],
      ),
    ),
    _row(
      '',
      Align(
        alignment: Alignment.centerLeft,
        child: _num(
          v.toDouble(),
          (x) => onChanged(x.round()),
          unit: 'px',
          max: 4096,
          width: 100,
        ),
      ),
    ),
  ];

  Widget _hint(String text) => _row(
    '',
    Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.outline),
    ),
  );

  static const _ratios = [(1.0, 1.0), (4.0, 3.0), (3.0, 2.0), (16.0, 9.0)];

  List<Widget> _crop() => [
    _drop<CropMode>(
      lt('方式'),
      c.crop,
      CropMode.values,
      (m) => m.label,
      (v) => _set((p) => p.crop = v),
    ),
    if (c.crop == CropMode.ratio) ...[
      _row(
        lt('比例'),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final (w, h) in _ratios)
              LimeChip(
                label: '${w.round()}:${h.round()}',
                dim: true,
                selected:
                    (c.ratioW == w && c.ratioH == h) ||
                    (c.ratioW == h && c.ratioH == w),
                onTap: () => _set((p) {
                  p.ratioW = w;
                  p.ratioH = h;
                }),
              ),
          ],
        ),
      ),
      _row(
        '',
        Row(
          children: [
            _num(
              c.ratioW,
              (v) => _set((p) => p.ratioW = v),
              min: 0.01,
              max: 1000,
              width: 64,
              digits: c.ratioW == c.ratioW.roundToDouble() ? 0 : 2,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(':', style: Theme.of(context).textTheme.bodyMedium),
            ),
            _num(
              c.ratioH,
              (v) => _set((p) => p.ratioH = v),
              min: 0.01,
              max: 1000,
              width: 64,
              digits: c.ratioH == c.ratioH.roundToDouble() ? 0 : 2,
            ),
          ],
        ),
      ),
      _switch(
        lt('自动横竖'),
        c.ratioFollowOrientation,
        (v) => _set((p) => p.ratioFollowOrientation = v),
      ),
      _anchorRow(),
    ],
    if (c.crop == CropMode.margin) ...[
      _row(
        lt('上 / 下'),
        Row(
          children: [
            _num(c.marginTop, (v) => _set((p) => p.marginTop = v), width: 72),
            const SizedBox(width: 6),
            _num(
              c.marginBottom,
              (v) => _set((p) => p.marginBottom = v),
              width: 72,
            ),
          ],
        ),
      ),
      _row(
        lt('左 / 右'),
        Row(
          children: [
            _num(c.marginLeft, (v) => _set((p) => p.marginLeft = v), width: 72),
            const SizedBox(width: 6),
            _num(
              c.marginRight,
              (v) => _set((p) => p.marginRight = v),
              width: 72,
            ),
          ],
        ),
      ),
      _row(
        lt('单位'),
        SizedBox(
          width: 110,
          child: LimeSegmented<MarginUnit>(
            value: c.marginUnit,
            items: MarginUnit.values,
            labelOf: (u) => u == MarginUnit.px ? 'px' : '%',
            onChanged: (v) => _set((p) => p.marginUnit = v),
          ),
        ),
      ),
    ],
    if (c.crop == CropMode.fixed) ...[
      _row(
        lt('尺寸'),
        Row(
          children: [
            _num(
              c.fixedW.toDouble(),
              (v) => _set((p) => p.fixedW = v.round()),
              min: 1,
              width: 72,
            ),
            _times(),
            _num(
              c.fixedH.toDouble(),
              (v) => _set((p) => p.fixedH = v.round()),
              min: 1,
              width: 72,
            ),
          ],
        ),
      ),
      _anchorRow(),
    ],
    if (c.crop == CropMode.trim) ...[
      _slider(
        lt('容差'),
        c.trimTolerance,
        0,
        80,
        (v) => _set((p) => p.trimTolerance = v),
      ),
      _row(
        lt('留边'),
        Align(
          alignment: Alignment.centerLeft,
          child: _num(
            c.trimPadding.toDouble(),
            (v) => _set((p) => p.trimPadding = v.round()),
            unit: 'px',
            max: 2000,
          ),
        ),
      ),
    ],
    if (c.crop == CropMode.fixed)
      _row(
        lt('对齐倍数'),
        Text(
          lt('固定尺寸下不生效'),
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      )
    else ...[
      ..._alignRows(c.cropAlign, (v) => _set((p) => p.cropAlign = v)),
      // 按比例已经有位置选择；其他模式开了对齐才需要决定从哪边裁
      if (c.cropAlign > 1 && c.crop != CropMode.ratio) _anchorRow(),
    ],
  ];

  Widget _anchorRow() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelW,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              lt('位置'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        AnchorPicker(
          value: c.anchor,
          onChanged: (v) => _set((p) => p.anchor = v),
        ),
      ],
    ),
  );

  // —— 尺寸 ——
  String _resizeSummary() {
    final base = switch (c.resize) {
      ResizeMode.none => c.resize.label,
      ResizeMode.percent => '${c.resizeValue.round()}%',
      ResizeMode.fit => '${c.fitW} × ${c.fitH}',
      ResizeMode.pixels => '${_fmtNum(c.megapixels)}M',
      _ => '${c.resize.label} ${c.resizeValue.round()}px',
    };
    return c.resizeAlignActive ? '$base · ÷${c.resizeAlign}' : base;
  }

  static const _megapixels = [0.25, 0.5, 1.0, 2.0, 4.0];

  List<Widget> _resize() => [
    _drop<ResizeMode>(
      lt('方式'),
      c.resize,
      ResizeMode.values,
      (m) => m.label,
      (v) => _set((p) => p.resize = v),
    ),
    if (c.resize == ResizeMode.longEdge ||
        c.resize == ResizeMode.shortEdge ||
        c.resize == ResizeMode.width ||
        c.resize == ResizeMode.height) ...[
      _row(
        '',
        Align(
          alignment: Alignment.centerLeft,
          child: _num(
            c.resizeValue,
            (v) => _set((p) => p.resizeValue = v),
            unit: 'px',
            min: 1,
            max: 65535,
            width: 100,
          ),
        ),
      ),
      _row(
        '',
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final v in const [1080, 1920, 2560, 3840])
              LimeChip(
                label: '$v',
                dim: true,
                selected: c.resizeValue == v,
                onTap: () => _set((p) => p.resizeValue = v.toDouble()),
              ),
          ],
        ),
      ),
    ],
    if (c.resize == ResizeMode.percent)
      _slider(
        lt('比例'),
        c.resizeValue.clamp(1, 200),
        1,
        200,
        (v) => _set((p) => p.resizeValue = v.toDouble()),
        unit: '%',
      ),
    if (c.resize == ResizeMode.fit)
      _row(
        lt('宽 × 高'),
        Row(
          children: [
            _num(
              c.fitW.toDouble(),
              (v) => _set((p) => p.fitW = v.round()),
              min: 1,
              max: 65535,
              width: 72,
            ),
            _times(),
            _num(
              c.fitH.toDouble(),
              (v) => _set((p) => p.fitH = v.round()),
              min: 1,
              max: 65535,
              width: 72,
            ),
          ],
        ),
      ),
    if (c.resize == ResizeMode.pixels) ...[
      _row(
        '',
        Align(
          alignment: Alignment.centerLeft,
          child: _num(
            c.megapixels,
            (v) => _set((p) => p.megapixels = v),
            unit: 'M',
            min: 0.01,
            max: 1000,
            width: 100,
            digits: 2,
          ),
        ),
      ),
      _row(
        '',
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final v in _megapixels)
              LimeChip(
                label: '${_fmtNum(v)}M',
                dim: true,
                selected: c.megapixels == v,
                onTap: () => _set((p) => p.megapixels = v),
              ),
          ],
        ),
      ),
      _hint(lt('1M = 1024 × 1024 像素')),
    ],
    if (c.resize != ResizeMode.none) ...[
      ..._alignRows(c.resizeAlign, (v) => _set((p) => p.resizeAlign = v)),
      if (c.resizeAlign > 1) _hint(lt('缩放后居中裁掉多余的边，不变形')),
      _switch(lt('不放大'), c.noUpscale, (v) => _set((p) => p.noUpscale = v)),
      _drop<ResizeFilter>(
        lt('插值'),
        c.filter,
        ResizeFilter.values,
        (f) => f.label,
        (v) => _set((p) => p.filter = v),
      ),
    ],
  ];

  // —— 格式 ——
  String _formatSummary() => switch (c.format) {
    OutputFormat.jpeg => 'JPEG ${c.jpegQuality}',
    OutputFormat.webp => c.webpLossless ? 'WebP' : 'WebP ${c.webpQuality}',
    OutputFormat.avif => 'AVIF ${c.avifQuality}',
    _ => c.format.label,
  };

  static const _bgColors = [0xFFFFFFFF, 0xFFE0E0E0, 0xFF808080, 0xFF000000];

  List<Widget> _format() {
    final f = c.format;
    final available = OutputFormat.values
        .where((x) => x == f || !s.capsReady || s.canEncode(x))
        .toList();
    final keep = f == OutputFormat.keep;
    final lossyNow =
        f == OutputFormat.jpeg ||
        f == OutputFormat.avif ||
        (f == OutputFormat.webp && !c.webpLossless);
    final noAlpha = keep || f == OutputFormat.jpeg || f == OutputFormat.avif;
    final scheme = Theme.of(context).colorScheme;

    return [
      _drop<OutputFormat>(
        lt('格式'),
        f,
        available,
        (x) => x.label,
        (v) => _set((p) => p.format = v),
      ),
      if (s.capsReady && !s.canEncode(f))
        _row(
          '',
          Text(
            lt('需要 ffmpeg'),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: scheme.error),
          ),
        ),
      if (f == OutputFormat.jpeg || keep)
        _slider(
          keep ? 'JPEG' : lt('质量'),
          c.jpegQuality,
          1,
          100,
          (v) => _set((p) => p.jpegQuality = v),
        ),
      if (f == OutputFormat.jpeg)
        _row(
          lt('色度'),
          LimeSegmented<JpegSubsampling>(
            value: c.jpegSubsampling,
            items: JpegSubsampling.values,
            labelOf: (x) => x.label,
            onChanged: (v) => _set((p) => p.jpegSubsampling = v),
          ),
        ),
      if (f == OutputFormat.webp)
        _switch(
          lt('无损'),
          c.webpLossless,
          (v) => _set((p) => p.webpLossless = v),
        ),
      if ((f == OutputFormat.webp && !c.webpLossless) || keep)
        _slider(
          keep ? 'WebP' : lt('质量'),
          c.webpQuality,
          1,
          100,
          (v) => _set((p) => p.webpQuality = v),
        ),
      if (f == OutputFormat.webp)
        _slider(
          lt('压缩等级'),
          c.webpEffort,
          0,
          6,
          (v) => _set((p) => p.webpEffort = v),
        ),
      if (f == OutputFormat.avif) ...[
        _slider(
          lt('质量'),
          c.avifQuality,
          1,
          100,
          (v) => _set((p) => p.avifQuality = v),
        ),
        _slider(
          lt('速度'),
          c.avifSpeed,
          0,
          10,
          (v) => _set((p) => p.avifSpeed = v),
        ),
      ],
      if (f == OutputFormat.tiff)
        _row(
          lt('压缩'),
          LimeSegmented<TiffCompression>(
            value: c.tiffCompression,
            items: TiffCompression.values,
            labelOf: (x) => x.label,
            onChanged: (v) => _set((p) => p.tiffCompression = v),
          ),
        ),
      if (lossyNow) ...[
        _switch(lt('限制大小'), c.limitSize, (v) => _set((p) => p.limitSize = v)),
        if (c.limitSize)
          _row(
            '',
            Align(
              alignment: Alignment.centerLeft,
              child: _num(
                c.maxKb.toDouble(),
                (v) => _set((p) => p.maxKb = v.round()),
                unit: 'KB',
                min: 1,
                max: 1000000,
                width: 100,
              ),
            ),
          ),
      ],
      if (noAlpha)
        _row(
          lt('透明底色'),
          Row(
            children: [
              for (final col in _bgColors)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _set((p) => p.background = col),
                      child: Container(
                        width: 21,
                        height: 21,
                        decoration: BoxDecoration(
                          color: Color(col),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.background == col
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: c.background == col ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      _row(
        lt('动图'),
        LimeSegmented<AnimatedPolicy>(
          value: c.animated,
          items: AnimatedPolicy.values,
          labelOf: (x) => x.label,
          onChanged: (v) => _set((p) => p.animated = v),
        ),
      ),
      _switch(
        lt('避免变大'),
        c.keepIfLarger,
        (v) => _set((p) => p.keepIfLarger = v),
      ),
    ];
  }

  // —— 输出 ——
  String _outputSummary() => switch (c.place) {
    OutputPlace.subfolder => c.subfolder,
    OutputPlace.custom => c.customDir.isEmpty ? c.place.label : c.customDir,
    _ => c.place.label,
  };

  Future<void> _pickDir() async {
    final dir = await getDirectoryPath(
      initialDirectory: c.customDir.isEmpty ? null : c.customDir,
    );
    if (dir == null) return;
    s.rememberDir(dir);
    _set((p) => p.customDir = dir);
  }

  List<Widget> _output() => [
    _row(
      lt('位置'),
      LimeSegmented<OutputPlace>(
        value: c.place,
        items: OutputPlace.values,
        labelOf: (x) => x.label,
        onChanged: (v) => _set((p) => p.place = v),
      ),
    ),
    if (c.place == OutputPlace.subfolder)
      _row(
        lt('名称'),
        LimeTextField(
          value: c.subfolder,
          onChanged: (v) => _set((p) => p.subfolder = v.trim()),
        ),
      ),
    if (c.place == OutputPlace.custom) ...[
      _row(
        lt('文件夹'),
        Row(
          children: [
            Expanded(
              child: LimeTextField(
                value: c.customDir,
                onChanged: (v) => _set((p) => p.customDir = v.trim()),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: lt('浏览'),
              iconSize: 16,
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: _pickDir,
            ),
            if (s.recentDirs.isNotEmpty)
              MenuAnchor(
                menuChildren: [
                  for (final d in s.recentDirs)
                    MenuItemButton(
                      onPressed: () {
                        s.rememberDir(d);
                        _set((p) => p.customDir = d);
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text(d, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
                builder: (context, ctl, _) => IconButton(
                  tooltip: lt('最近使用'),
                  iconSize: 16,
                  icon: const Icon(Icons.history),
                  onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
                ),
              ),
          ],
        ),
      ),
      _switch(
        lt('保持目录结构'),
        c.keepStructure,
        (v) => _set((p) => p.keepStructure = v),
      ),
    ],
    _row(
      lt('重名时'),
      LimeSegmented<ConflictPolicy>(
        value: c.conflict,
        items: ConflictPolicy.values,
        labelOf: (x) => x.label,
        onChanged: (v) => _set((p) => p.conflict = v),
      ),
    ),
    _drop<AfterRun>(
      lt('完成后'),
      c.afterRun,
      AfterRun.values,
      (x) => x.label,
      (v) => _set((p) => p.afterRun = v),
    ),
  ];

  // —— 文件名 ——
  String _nameSummary() {
    final ext = c.format == OutputFormat.keep ? '' : '.${c.extFor(c.format)}';
    return '${c.nameTemplate}$ext';
  }

  void _insertVar(String v) {
    final t = _template;
    final sel = t.selection;
    final text = t.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, v);
    t.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + v.length),
    );
    _set((p) => p.nameTemplate = next);
  }

  List<Widget> _name() => [
    _row(
      lt('模板'),
      LimeTextField(
        value: c.nameTemplate,
        controller: _template,
        live: true,
        onChanged: (v) => _set((p) => p.nameTemplate = v),
      ),
    ),
    _row(
      '',
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final v in kNameVariables)
            LimeChip(label: v, dim: true, onTap: () => _insertVar(v)),
        ],
      ),
    ),
    if (c.nameTemplate.contains('{n}'))
      _row(
        lt('序号'),
        Row(
          children: [
            _num(
              c.seqStart.toDouble(),
              (v) => _set((p) => p.seqStart = v.round()),
              width: 72,
              max: 999999,
            ),
            const SizedBox(width: 8),
            Text(lt('位数'), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 6),
            _num(
              c.seqDigits.toDouble(),
              (v) => _set((p) => p.seqDigits = v.round()),
              width: 52,
              min: 1,
              max: 8,
            ),
          ],
        ),
      ),
    if (c.format == OutputFormat.jpeg || c.format == OutputFormat.keep)
      _row(
        lt('扩展名'),
        SizedBox(
          width: 130,
          child: LimeSegmented<bool>(
            value: c.jpegLongExt,
            items: const [false, true],
            labelOf: (v) => v ? '.jpeg' : '.jpg',
            onChanged: (v) => _set((p) => p.jpegLongExt = v),
          ),
        ),
      ),
  ];

  // —— 元数据 ——
  List<Widget> _meta() => [
    _drop<MetadataPolicy>(
      'EXIF',
      c.metadata,
      MetadataPolicy.values,
      (x) => x.label,
      (v) => _set((p) => p.metadata = v),
    ),
    _switch(
      lt('保留修改时间'),
      c.keepTimestamps,
      (v) => _set((p) => p.keepTimestamps = v),
    ),
  ];
}

// ---------------------------------------------------------------------------
// 预设栏
// ---------------------------------------------------------------------------

class _PresetBar extends StatelessWidget {
  const _PresetBar({required this.state});
  final BatchState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final scheme = Theme.of(context).colorScheme;
    final names = s.presets.map((e) => e.name).toList();
    final current = s.presetName;
    final items = <String?>[if (current == null) null, ...names];

    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: LimeDropdown<String?>(
                value: current,
                items: items,
                width: double.infinity,
                enabled: !s.running,
                labelOf: (n) => n ?? lt('未保存的设置'),
                onChanged: (n) {
                  final np = s.presets.where((e) => e.name == n).firstOrNull;
                  if (np != null) s.applyPreset(np);
                },
              ),
            ),
            SizedBox(
              width: 18,
              child: s.dirty && current != null
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            IconButton(
              tooltip: lt('保存预设'),
              iconSize: 17,
              icon: const Icon(Icons.save_outlined),
              onPressed: s.running || !s.dirty
                  ? null
                  : () =>
                        current == null ? _saveAs(context, s) : s.savePreset(),
            ),
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => _saveAs(context, s),
                  leadingIcon: const Icon(Icons.add, size: 15),
                  child: Text(lt('另存为…')),
                ),
                MenuItemButton(
                  onPressed: current == null
                      ? null
                      : () => _rename(context, s, current),
                  leadingIcon: const Icon(Icons.edit_outlined, size: 15),
                  child: Text(lt('重命名…')),
                ),
                MenuItemButton(
                  onPressed: current == null
                      ? null
                      : () => _delete(context, s, current),
                  leadingIcon: const Icon(Icons.delete_outline, size: 15),
                  child: Text(lt('删除')),
                ),
                const Divider(height: 9),
                MenuItemButton(
                  onPressed: () => _import(s),
                  leadingIcon: const Icon(Icons.file_open_outlined, size: 15),
                  child: Text(lt('导入…')),
                ),
                MenuItemButton(
                  onPressed: () => _export(s),
                  leadingIcon: const Icon(Icons.ios_share, size: 15),
                  child: Text(lt('导出…')),
                ),
              ],
              builder: (context, ctl, _) => IconButton(
                iconSize: 18,
                icon: const Icon(Icons.more_horiz),
                onPressed: s.running
                    ? null
                    : () => ctl.isOpen ? ctl.close() : ctl.open(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<String?> _askName(
    BuildContext context,
    String title,
    String initial,
  ) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 300,
          child: ImeScope(
            child: TextField(
              controller: ctl,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lt('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text(lt('确定')),
          ),
        ],
      ),
    ).whenComplete(ctl.dispose);
  }

  static Future<void> _saveAs(BuildContext context, BatchState s) async {
    final name = await _askName(
      context,
      lt('另存为预设'),
      s.presetName ?? lt('新预设'),
    );
    if (name == null || name.isEmpty) return;
    // 预设按名字存成文件，Windows 文件名不分大小写
    if (_taken(s, name, except: s.presetName)) {
      if (!context.mounted) return;
      final ok = await _confirm(context, lt('覆盖预设「{0}」？', [name]));
      if (!ok) return;
    }
    await s.savePreset(name);
  }

  static bool _taken(BatchState s, String name, {String? except}) =>
      s.presets.any(
        (e) =>
            e.name.toLowerCase() == name.toLowerCase() &&
            e.name.toLowerCase() != except?.toLowerCase(),
      );

  static Future<void> _rename(
    BuildContext context,
    BatchState s,
    String from,
  ) async {
    final name = await _askName(context, lt('重命名预设'), from);
    if (name == null || name.isEmpty || name == from) return;
    if (_taken(s, name, except: from)) {
      if (!context.mounted) return;
      final ok = await _confirm(context, lt('覆盖预设「{0}」？', [name]));
      if (!ok) return;
    }
    await s.renamePreset(from, name);
  }

  static Future<void> _delete(
    BuildContext context,
    BatchState s,
    String name,
  ) async {
    final ok = await _confirm(context, lt('删除预设「{0}」？', [name]));
    if (ok) await s.deletePreset(name);
  }

  static Future<bool> _confirm(BuildContext context, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lt('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(lt('确定')),
            ),
          ],
        ),
      ) ??
      false;

  static const _json = XTypeGroup(label: 'JSON', extensions: ['json']);

  static Future<void> _import(BatchState s) async {
    final f = await openFile(acceptedTypeGroups: [_json]);
    if (f != null) await s.importPreset(f.path);
  }

  static Future<void> _export(BatchState s) async {
    final loc = await getSaveLocation(
      acceptedTypeGroups: [_json],
      suggestedName: '${s.presetName ?? 'preset'}.json',
    );
    if (loc != null) await s.exportPreset(loc.path);
  }
}
