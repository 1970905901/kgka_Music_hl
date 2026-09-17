import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全局通用的液态玻璃快速返回顶部按钮。
///
/// 监听绑定的 [ScrollController]，当滚动距离超过 [threshold] 时平滑浮现，
/// 点击后以平滑曲线滚回顶部，并在滚回顶部后自动淡出消失。
class ScrollToTopButton extends StatefulWidget {
  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.threshold = 320.0,
    this.animationDuration = const Duration(milliseconds: 220),
    this.scrollDuration = const Duration(milliseconds: 380),
    this.scrollCurve = Curves.easeOutCubic,
    this.onScrollToTop,
    this.size = 44.0,
  });

  /// 绑定的滚动控制器。
  final ScrollController controller;

  /// 触发显示的滚动距离阈值（像素）。
  final double threshold;

  /// 按钮淡入淡出与缩放的动画时长。
  final Duration animationDuration;

  /// 回滚到顶部的动画时长。
  final Duration scrollDuration;

  /// 回滚到顶部的动画曲线。
  final Curve scrollCurve;

  /// 点击滚回顶部时的额外回调。
  final VoidCallback? onScrollToTop;

  /// 按钮直径大小。
  final double size;

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _visible = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkScroll();
    });
  }

  @override
  void didUpdateWidget(covariant ScrollToTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      _checkScroll();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _checkScroll();
  }

  void _checkScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    final shouldShow = widget.controller.offset >= widget.threshold;
    if (shouldShow != _visible) {
      setState(() => _visible = shouldShow);
    }
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    widget.onScrollToTop?.call();
    if (widget.controller.hasClients) {
      widget.controller.animateTo(
        0.0,
        duration: widget.scrollDuration,
        curve: widget.scrollCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBgColor = isDark
        ? colorScheme.surfaceContainerHighest.withValues(alpha: .55)
        : Colors.white.withValues(alpha: .85);

    final effectiveBorderColor = isDark
        ? Colors.white.withValues(alpha: .18)
        : Colors.white.withValues(alpha: .92);

    return AnimatedScale(
      scale: _visible ? (_isPressed ? 0.92 : 1.0) : 0.6,
      duration: widget.animationDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: widget.animationDuration,
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !_visible,
          child: Tooltip(
            message: '返回顶部',
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => setState(() => _isPressed = false),
              onTapCancel: () => setState(() => _isPressed = false),
              onTap: _scrollToTop,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: .38)
                          : const Color(0x18000000),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: effectiveBgColor,
                        border: Border.all(
                          color: effectiveBorderColor,
                          width: 1.0,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 26,
                          color: colorScheme.primary,
                        ),
                      ),
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
