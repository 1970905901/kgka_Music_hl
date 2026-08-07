import 'dart:async';

import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Toast 类型，决定图标与配色。
enum ToastType { info, success, error }

/// 全局 Toast 服务。
///
/// 通过 [navigatorKey] 挂载到根 Navigator 的 Overlay，不依赖调用处的
/// `BuildContext`，可在任意层（包括 dialog、bottom sheet 之上）显示。
///
/// 用法：
/// 1. 在 `MaterialApp` 中传入 `navigatorKey: Toast.navigatorKey`。
/// 2. 任意位置调用 `Toast.show('提示内容')` 即可。
class Toast {
  Toast._();

  /// 绑定到 MaterialApp 的 navigator key。
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  /// 显示一条 Toast。
  ///
  /// [message] 文本内容；[type] 决定图标与配色（默认 [ToastType.info]）；
  /// [duration] 显示时长（默认 2 秒）。
  static void show(
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _dismissTimer?.cancel();
    _currentEntry?.remove();

    final entry = OverlayEntry(
      builder: (context) => _ToastView(
        message: message,
        type: type,
        onDismissed: () {
          if (_currentEntry != null) {
            _currentEntry?.remove();
            _currentEntry = null;
          }
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      // 触发淡出动画，动画结束后 _ToastView 会调用 onDismissed 移除 entry。
      _currentState?.dismiss();
    });
  }

  static _ToastViewState? _currentState;

  static void _registerState(_ToastViewState state) {
    _currentState = state;
  }

  static void _unregisterState(_ToastViewState state) {
    if (identical(_currentState, state)) {
      _currentState = null;
    }
  }

  /// 快捷方法：信息提示。
  static void info(String message, {Duration? duration}) =>
      show(message, type: ToastType.info, duration: duration ?? const Duration(seconds: 2));

  /// 快捷方法：成功提示。
  static void success(String message, {Duration? duration}) =>
      show(message, type: ToastType.success, duration: duration ?? const Duration(seconds: 2));

  /// 快捷方法：错误提示。
  static void error(String message, {Duration? duration}) =>
      show(message, type: ToastType.error, duration: duration ?? const Duration(seconds: 3));
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.type,
    required this.onDismissed,
  });

  final String message;
  final ToastType type;
  final VoidCallback onDismissed;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    Toast._registerState(this);
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    Toast._unregisterState(this);
    _controller.dispose();
    super.dispose();
  }

  void dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _controller.reverse().whenComplete(() {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (icon, accentColor) = switch (widget.type) {
      ToastType.info => (Icons.info_outline_rounded, colorScheme.primary),
      ToastType.success => (Icons.check_circle_rounded, const Color(0xFF24C768)),
      ToastType.error => (Icons.error_outline_rounded, colorScheme.error),
    };

    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.paddingOf(context).bottom +
          96,
      child: SafeArea(
        top: false,
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF1F242E) : const Color(0xFFFFFFFF))
                          .withValues(alpha: isDark ? .96 : .98),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: accentColor.withValues(alpha: .28),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? .45 : .14),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: accentColor),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1F2B),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
