import 'dart:io';

import 'package:flutter/material.dart';

import '../models/enums.dart';

class LimeTheme {
  /// 界面字体：优先系统 UI 字体，CJK 用对应平台的黑体兜底，避免粗细不一
  static String? get _fontFamily {
    if (Platform.isWindows) return 'Segoe UI';
    if (Platform.isMacOS) return null; // 走系统默认 SF Pro
    return null;
  }

  static const List<String> _fallback = [
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'WenQuanYi Micro Hei',
    'Arial',
  ];

  static ThemeData build(
    Brightness brightness,
    int accent, {
    double radius = 10,
    double fontScale = 1.0,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(accent),
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);

    final base = isDark ? ThemeData.dark() : ThemeData.light();
    // 统一字重：只用 w400 / w500 / w600，避免同一界面粗细跳变
    TextStyle t(double size, [FontWeight w = FontWeight.w400]) => TextStyle(
      fontSize: size * fontScale,
      fontWeight: w,
      height: 1.35,
      letterSpacing: 0,
    );

    final textTheme = base.textTheme
        .copyWith(
          displayLarge: t(30, FontWeight.w500),
          headlineSmall: t(18, FontWeight.w600),
          titleLarge: t(15, FontWeight.w600),
          titleMedium: t(13.5, FontWeight.w600),
          titleSmall: t(12.5, FontWeight.w500),
          bodyLarge: t(13),
          bodyMedium: t(12.5),
          bodySmall: t(11.5),
          labelLarge: t(12.5, FontWeight.w500),
          labelMedium: t(11.5),
          labelSmall: t(11),
        )
        .apply(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fallback,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );

    final menuSurface = isDark ? const Color(0xFF23252A) : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fallback,
      textTheme: textTheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF16171A)
          : const Color(0xFFF5F6F7),
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: isDark ? Colors.white12 : Colors.black12,
      ),
      // —— 菜单：不透明背景 + 圆角 + 阴影，不再和画面糊在一起 ——
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: isDark ? 0.35 : 0.16),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: r,
              side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
            ),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          minimumSize: const WidgetStatePropertyAll(Size(180, 32)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius * 0.6),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: menuSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 14,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: r,
              side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
            ),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: menuSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 2),
        ),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark
            ? Colors.white10
            : Colors.black.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius * 0.7),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius * 0.7),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        overlayShape: RoundSliderOverlayShape(overlayRadius: 11),
        thumbSize: WidgetStatePropertyAll(Size(14, 14)),
      ),
      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        trackOutlineWidth: const WidgetStatePropertyAll(1),
        thumbIcon: const WidgetStatePropertyAll(
          Icon(Icons.circle, size: 8, color: Colors.transparent),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius * 0.6),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius * 0.7),
            ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius * 0.7),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xF02A2C31) : const Color(0xF03A3D42),
          borderRadius: BorderRadius.circular(radius * 0.6),
        ),
        textStyle: TextStyle(
          color: Colors.white,
          fontSize: 11.5 * fontScale,
          height: 1.3,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: isDark ? 0.28 : 0.24),
        ),
      ),
    );
  }

  /// 画布背景色
  static Color canvasColor(BackgroundStyle style, ColorScheme scheme) {
    switch (style) {
      case BackgroundStyle.theme:
        return scheme.brightness == Brightness.dark
            ? const Color(0xFF121316)
            : const Color(0xFFEDEEF0);
      case BackgroundStyle.black:
        return Colors.black;
      case BackgroundStyle.dark:
        return const Color(0xFF1E1F22);
      case BackgroundStyle.light:
        return const Color(0xFFE6E7E9);
      case BackgroundStyle.white:
        return Colors.white;
      case BackgroundStyle.checker:
        return scheme.brightness == Brightness.dark
            ? const Color(0xFF1A1B1E)
            : const Color(0xFFF0F1F3);
    }
  }

  /// 浮层（标题栏 / 状态窗 / 缩略图栏）用的表面色
  static Color overlaySurface(ColorScheme scheme, {double alpha = 0.9}) {
    final dark = scheme.brightness == Brightness.dark;
    return (dark ? const Color(0xFF1D1F23) : Colors.white).withValues(
      alpha: alpha,
    );
  }
}

/// 棋盘格背景（看透明图）
class CheckerPainter extends CustomPainter {
  CheckerPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final a = Paint()
      ..color = dark ? const Color(0xFF232427) : const Color(0xFFFFFFFF);
    final b = Paint()
      ..color = dark ? const Color(0xFF1B1C1F) : const Color(0xFFE2E3E5);
    canvas.drawRect(Offset.zero & size, a);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final odd = (((x / cell).floor() + (y / cell).floor()) % 2) == 1;
        if (odd) canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), b);
      }
    }
  }

  @override
  bool shouldRepaint(CheckerPainter old) => old.dark != dark;
}
