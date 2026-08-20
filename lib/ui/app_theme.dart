import 'package:flutter/material.dart';
import 'design_tokens.dart';

class AppTheme {
  static const blue = Color(0xFF1478FF);
  static const musicRed = Color(0xFFFF2D55);

  static ThemeData light({Color? seedColor, bool transparentBackground = false}) {
    return _theme(Brightness.light,
        seedColor: seedColor ?? blue,
        transparentBackground: transparentBackground);
  }

  static ThemeData dark({Color? seedColor, bool transparentBackground = false}) {
    return _theme(Brightness.dark,
        seedColor: seedColor ?? blue,
        transparentBackground: transparentBackground);
  }

  static ThemeData _theme(
    Brightness brightness, {
    Color seedColor = blue,
    bool transparentBackground = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness)
        .copyWith(
          primary: isDark ? _lighten(seedColor, 0.18) : seedColor,
          secondary: musicRed,
          tertiary: const Color(0xFF24C768),
          surface: isDark ? const Color(0xFF0B0C10) : Colors.white,
          surfaceContainerLowest: isDark
              ? const Color(0xFF06070A)
              : Colors.white,
          surfaceContainer: isDark
              ? const Color(0xFF151820)
              : const Color(0xFFF4F7FB),
          surfaceContainerHighest: isDark
              ? const Color(0xFF202430)
              : const Color(0xFFEFF5FF),
          onSurface: isDark ? Colors.white : const Color(0xFF080B12),
          onSurfaceVariant: isDark
              ? const Color(0xFFB0B8C6)
              : const Color(0xFF6F7785),
          outline: isDark ? const Color(0xFF4D5668) : const Color(0xFFD2DAE7),
          outlineVariant: isDark
              ? const Color(0xFF303747)
              : const Color(0xFFE7EDF7),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: transparentBackground
          ? Colors.transparent
          : (isDark ? const Color(0xFF06070A) : Colors.white),
      textTheme: const TextTheme(
        labelSmall: TextStyle(fontSize: 10, height: 1.2),
        bodySmall: TextStyle(fontSize: 12, height: 1.3),
        labelMedium: TextStyle(fontSize: 12, height: 1.3),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4),
        labelLarge: TextStyle(fontSize: 14, height: 1.4),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4),
        titleSmall: TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(fontSize: 22, height: 1.4, fontWeight: FontWeight.w700),
        displaySmall: TextStyle(fontSize: 22, height: 1.4, fontWeight: FontWeight.w700),
      ),
      fontFamilyFallback: const [
        'SF Pro Display',
        'SF Pro Text',
        'Roboto',
        'Arial',
      ],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: transparentBackground
            ? Colors.transparent
            : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        // AppBar 会创建自己的 AnnotatedRegion 并覆盖页面级 SystemUiOverlayStyle；
        // 背景为 transparent 时 Flutter 会推断为深色 → 状态栏画白字，
        // 在浅色页面上完全不可见。这里显式指定，与全局主题明暗一致。
        // iOS 的 statusBarBrightness 描述【背景】明暗，Android 的 statusBarIconBrightness 描述【前景】明暗，
        // 两者语义相反，因此必须取镜像值。
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          highlightColor: scheme.primary.withValues(alpha: .08),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF171A22) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .72),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: scheme.primary, width: 1.3),
        ),
      ),
    );
  }

  /// 将颜色向白色方向提亮。
  static Color _lighten(Color color, [double amount = 0.2]) {
    return Color.lerp(color, Colors.white, amount) ?? color;
  }
}
