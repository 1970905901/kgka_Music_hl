import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 状态栏前景色覆盖组件。
///
/// 将一个页面（或局部子树）的状态栏前景色统一设置为与背景明暗相匹配：
/// - [brightness] 表示页面背景的整体明暗。
///   - [Brightness.light]：浅色背景 → 状态栏使用黑色文字/图标。
///   - [Brightness.dark]：深色背景 → 状态栏使用白色文字/图标。
///
/// iOS（[SystemUiOverlayStyle.statusBarBrightness]）描述的是状态栏【背景】的明暗，
/// 系统据此自动选取对比前景色；Android（[SystemUiOverlayStyle.statusBarIconBrightness]）
/// 描述的是【前景】（图标/文字）的明暗。两者语义相反，因此取值必须相反：
/// 浅色背景 → statusBarBrightness: [Brightness.light]（iOS 黑字）/
/// statusBarIconBrightness: [Brightness.dark]（Android 黑图标）；
/// 深色背景 → 两者取镜像值。
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
    final isDarkBackground = brightness == Brightness.dark;

    // Android：该属性描述的是前景（图标/文字）的明暗。
    // 深色背景 → 白色前景；浅色背景 → 黑色前景。
    final iconBrightness =
        isDarkBackground ? Brightness.light : Brightness.dark;

    // iOS：该属性描述的是状态栏背后【背景】的明暗，系统据此自动选取对比前景色。
    // 因此它必须与 iconBrightness 相反，否则 iOS 会画出与背景同色、完全看不见的文字。
    final iosBarBrightness =
        isDarkBackground ? Brightness.dark : Brightness.light;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: iosBarBrightness,
      ),
      child: child,
    );
  }
}
