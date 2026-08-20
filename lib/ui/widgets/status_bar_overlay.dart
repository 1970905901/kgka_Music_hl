import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 状态栏前景色覆盖组件。
///
/// 将一个页面（或局部子树）的状态栏前景色统一设置为与背景明暗相匹配：
/// - [brightness] 表示页面背景的整体明暗。
///   - [Brightness.light]：浅色背景 → 状态栏使用黑色文字/图标。
///   - [Brightness.dark]：深色背景 → 状态栏使用白色文字/图标。
///
/// 同时兼容 iOS（[SystemUiOverlayStyle.statusBarBrightness]）与
/// Android（[SystemUiOverlayStyle.statusBarIconBrightness]），避免在各页面
/// 重复编写两份几乎一致的 [SystemUiOverlayStyle]。
class StatusBarOverlay extends StatelessWidget {
  const StatusBarOverlay({
    super.key,
    required this.brightness,
    required this.child,
  });

  /// 页面背景的明暗。浅色背景传 [Brightness.light]，深色背景传 [Brightness.dark]。
  final Brightness brightness;

  /// 被覆盖状态栏样式的子树。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 浅色背景 → 黑色前景（Brightness.dark）；深色背景 → 白色前景（Brightness.light）。
    // 该 foreground 同时用于 iOS（statusBarBrightness）与 Android（statusBarIconBrightness）。
    final foreground = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: foreground,
        statusBarBrightness: foreground,
      ),
      child: child,
    );
  }
}
