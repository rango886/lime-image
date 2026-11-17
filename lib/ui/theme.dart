import 'dart:io';

import 'package:flutter/material.dart';

import '../models/enums.dart';

/// 中性灰阶：R=G=B，不掺任何色相；亮色接近白、暗色接近黑，但都不用纯 #FFF / #000
class LimeNeutral {
  // 暗色（深黑）
  static const darkBg = Color(0xFF0E0E0E); // 页面底色
  static const darkCanvas = Color(0xFF0B0B0B); // 看图画布
  static const darkSurface = Color(0xFF141414);
  static const darkLow = Color(0xFF171717);
  static const darkMid = Color(0xFF1B1B1B);
  static const darkHigh = Color(0xFF212121);
  static const darkHighest = Color(0xFF282828);
  static const darkMenu = Color(0xFF1C1C1C);
  static const darkOverlay = Color(0xFF151515);
  static const darkText = Color(0xFFEDEDED);
  static const darkTextDim = Color(0xFFA6A6A6);
  static const darkOutline = Color(0xFF6E6E6E);
  static const darkOutlineDim = Color(0xFF2C2C2C);

  // 亮色（近白）
  static const lightBg = Color(0xFFFAFAFA);
  static const lightCanvas = Color(0xFFF3F3F3);
  static const lightSurface = Color(0xFFFDFDFD);
  static const lightLow = Color(0xFFF7F7F7);
  static const lightMid = Color(0xFFF2F2F2);
  static const lightHigh = Color(0xFFEDEDED);
  static const lightHighest = Color(0xFFE7E7E7);
  static const lightMenu = Color(0xFFFDFDFD);
  static const lightOverlay = Color(0xFFFCFCFC);
  static const lightText = Color(0xFF1A1A1A);
  static const lightTextDim = Color(0xFF5E5E5E);
  static const lightOutline = Color(0xFF8F8F8F);
  static const lightOutlineDim = Color(0xFFE0E0E0);
}

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
    final isDark = brightness == Brightness.dark;
    final accentColor = Color(accent);
    final onAccent =
        ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
        ? const Color(0xFFFAFAFA)
        : const Color(0xFF111111);
    // 强调色只用于高亮（primary / 选中态），所有底色、文字、描边都换成中性灰，
    // 避免 fromSeed 把强调色的色相混进背景里
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: brightness,
        ).copyWith(
          primary: accentColor,
          onPrimary: onAccent,
          surfaceTint: Colors.transparent,
          surface: isDark ? LimeNeutral.darkSurface : LimeNeutral.lightSurface,
          onSurface: isDark ? LimeNeutral.darkText : LimeNeutral.lightText,
          onSurfaceVariant: isDark
              ? LimeNeutral.darkTextDim
              : LimeNeutral.lightTextDim,
          surfaceDim: isDark ? LimeNeutral.darkBg : LimeNeutral.lightHighest,
          surfaceBright: isDark
              ? LimeNeutral.darkHighest
              : LimeNeutral.lightSurface,
          surfaceContainerLowest: isDark
              ? LimeNeutral.darkCanvas
              : LimeNeutral.lightSurface,
          surfaceContainerLow: isDark
              ? LimeNeutral.darkLow
              : LimeNeutral.lightLow,
          surfaceContainer: isDark ? LimeNeutral.darkMid : LimeNeutral.lightMid,
          surfaceContainerHigh: isDark
              ? LimeNeutral.darkHigh
              : LimeNeutral.lightHigh,
          surfaceContainerHighest: isDark
              ? LimeNeutral.darkHighest
              : LimeNeutral.lightHighest,
          outline: isDark ? LimeNeutral.darkOutline : LimeNeutral.lightOutline,
          outlineVariant: isDark
              ? LimeNeutral.darkOutlineDim
              : LimeNeutral.lightOutlineDim,
          inverseSurface: isDark ? LimeNeutral.darkText : LimeNeutral.lightText,
          onInverseSurface: isDark ? LimeNeutral.darkBg : LimeNeutral.lightBg,
          shadow: Colors.black,
          scrim: Colors.black,
        );
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

    final menuSurface = isDark ? LimeNeutral.darkMenu : LimeNeutral.lightMenu;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fallback,
      textTheme: textTheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: isDark
          ? LimeNeutral.darkBg
          : LimeNeutral.lightBg,
      canvasColor: isDark ? LimeNeutral.darkSurface : LimeNeutral.lightSurface,
      cardColor: isDark ? LimeNeutral.darkMid : LimeNeutral.lightSurface,
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
          color: isDark ? const Color(0xF02E2E2E) : const Color(0xF03A3A3A),
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
            ? LimeNeutral.darkCanvas
            : LimeNeutral.lightCanvas;
      case BackgroundStyle.black:
        return Colors.black;
      case BackgroundStyle.dark:
        return const Color(0xFF1E1E1E);
      case BackgroundStyle.light:
        return const Color(0xFFE6E6E6);
      case BackgroundStyle.white:
        return Colors.white;
      case BackgroundStyle.checker:
        return scheme.brightness == Brightness.dark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFF0F0F0);
    }
  }

  /// 浮层（标题栏 / 状态窗 / 缩略图栏）用的表面色
  static Color overlaySurface(ColorScheme scheme, {double alpha = 0.9}) {
    final dark = scheme.brightness == Brightness.dark;
    return (dark ? LimeNeutral.darkOverlay : LimeNeutral.lightOverlay)
        .withValues(alpha: alpha);
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
      ..color = dark ? const Color(0xFF232323) : const Color(0xFFFCFCFC);
    final b = Paint()
      ..color = dark ? const Color(0xFF1A1A1A) : const Color(0xFFE2E2E2);
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
