import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';
import 'fx_spinner.dart';

/// FxButton — 按钮组件。
///
/// Fx 统一按钮语义、尺寸、交互和触摸区域；视觉仍以 ShadButton 为底座。
/// 文字尺度由 SlowlightTypography 的平台语义统一解析，触控密度由平台密度层
/// 统一提供，避免 Fx 组件各自判断 Windows / Android。
enum FxButtonVariant { primary, secondary, outline, ghost, destructive, link }

enum FxButtonSize { sm, md, lg }

class FxButton extends StatefulWidget {
  final String label;
  final FutureOr<void> Function()? onPressed;
  final FxButtonVariant variant;
  final FxButtonSize size;
  final IconData? icon;
  /// Brand marks and other non-font icons share the existing FxButton geometry.
  final Widget? leading;
  final bool expanded;
  final Color? foregroundColor;

  const FxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FxButtonVariant.primary,
    this.size = FxButtonSize.md,
    this.icon,
    this.leading,
    this.expanded = false,
    this.foregroundColor,
  });

  @override
  State<FxButton> createState() => _FxButtonState();
}

/// Async actions are locked until their Future completes. Navigation and
/// synchronous selection remain instant, without an artificial time window.
class _FxButtonState extends State<FxButton> {
  bool _running = false;

  Future<void> _invoke() async {
    final action = widget.onPressed;
    if (_running || action == null) return;
    setState(() => _running = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  VoidCallback? get _effectiveAction =>
      widget.onPressed == null || _running ? null : _invoke;

  bool get _isCompactAction => widget.size == FxButtonSize.sm;

  TextStyle _textMetrics(BuildContext context) {
    final source = SlowlightTypography.componentButton(
      context,
      compact: _isCompactAction,
    );

    // Fx 只覆写排版尺度，不接管 ShadButton 各变体的前景色。
    // color 保持 null 时会继承 ShadButton 的 DefaultTextStyle：例如亮色主题
    // primary 的黑底白字、dark zinc 的浅底深字，以及 destructive 等语义色。
    return TextStyle(
      fontSize: source.fontSize,
      fontWeight: source.fontWeight,
      height: source.height,
      letterSpacing: source.letterSpacing,
      color: widget.foregroundColor,
    );
  }

  // 紧凑图标与标题的既定 6px 关系仅属于 FxButton。
  static const double _compactIconGap = 6;

  Widget _buildChild(BuildContext context) {
    final text = Text(widget.label,
        style: _textMetrics(context), textAlign: TextAlign.center);
    if (widget.icon != null || widget.leading != null) {
      final iconSize = _isCompactAction
          ? SlowlightIconSize.compactAction
          : SlowlightIconSize.sm;
      return Row(
        mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.leading != null)
            SizedBox(width: iconSize, height: iconSize, child: widget.leading!)
          else
            Icon(
              widget.icon,
              size: iconSize,
              color: widget.foregroundColor,
            ),
          SizedBox(
            width: _isCompactAction ? _compactIconGap : SlowlightSpacing.md,
          ),
          if (widget.expanded) Flexible(child: text) else text,
        ],
      );
    }
    return text;
  }

  ShadButtonSize get _shadSize {
    switch (widget.size) {
      case FxButtonSize.sm:
        return ShadButtonSize.sm;
      case FxButtonSize.lg:
        return ShadButtonSize.lg;
      case FxButtonSize.md:
        return ShadButtonSize.regular;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.expanded) return _buildButton(context);
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedWidth) return _buildButton(context);
      // 复用 ShadButton 的 expands 能力约束内容；大字号长文案允许换行，
      // 按实际文字高度增长，不缩字或裁掉关键动作。
      final mobile = SlowlightPlatformDensity.usesMobileTouchTargets;
      final padding = switch (widget.size) {
        FxButtonSize.sm => mobile ? 14.0 : 10.0,
        FxButtonSize.md => mobile ? 16.0 : 14.0,
        FxButtonSize.lg => mobile ? 20.0 : 18.0,
      };
      final iconWidth = widget.icon == null && widget.leading == null
          ? 0.0
          : (_isCompactAction
              ? SlowlightIconSize.compactAction + _compactIconGap
              : SlowlightIconSize.sm + SlowlightSpacing.md);
      final painter = TextPainter(
        text: TextSpan(text: widget.label, style: _textMetrics(context)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(
          maxWidth: math.max(
              1.0, constraints.maxWidth - padding * 2 - iconWidth - 8));
      final minHeight = mobile
          ? (widget.size == FxButtonSize.lg
              ? 48.0
              : SlowlightControlSize.minTouchTarget)
          : switch (widget.size) {
              FxButtonSize.sm => SlowlightControlSize.buttonSm,
              FxButtonSize.md => SlowlightControlSize.button,
              FxButtonSize.lg => SlowlightControlSize.buttonLg,
            };
      final verticalSpace = switch (widget.size) {
        FxButtonSize.sm => SlowlightSpacing.md,
        FxButtonSize.md => SlowlightSpacing.xl,
        FxButtonSize.lg => SlowlightSpacing.xxxl,
      };
      final height = math.max(minHeight, painter.height + verticalSpace);
      painter.dispose();
      return _buildButton(context, height: height);
    });
  }

  // Android 的最低命中高度必须属于 ShadButton 本身，而非外层空白。
  // 按真实文本倍率增长，避免 200% 系统字号被固定 44dp 裁切。
  double _mobileButtonHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: widget.label, style: _textMetrics(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final textHeight = painter.height;
    painter.dispose();
    final minHeight = widget.size == FxButtonSize.lg
        ? 48.0
        : SlowlightControlSize.minTouchTarget;
    final verticalSpace = switch (widget.size) {
      FxButtonSize.sm => SlowlightSpacing.md,
      FxButtonSize.md => SlowlightSpacing.xl,
      FxButtonSize.lg => SlowlightSpacing.xxxl,
    };
    return math.max(minHeight, textHeight + verticalSpace);
  }

  Widget _buildButton(BuildContext context, {double? height}) {
    final effectiveHeight = height ??
        (SlowlightPlatformDensity.usesMobileTouchTargets
            ? _mobileButtonHeight(context)
            : null);
    // Keep the original label's layout while an async write is pending.
    // Only the content changes; ShadButton retains its width, hit target,
    // variant/foreground and built-in disabled state. No second button.
    final baseChild = _buildChild(context);
    final child = !_running ? baseChild : Stack(
      alignment: Alignment.center,
      children: [
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: baseChild,
        ),
        Positioned.fill(
          child: Center(
            child: Builder(
              builder: (buttonContext) => FxSpinner(
                size: widget.size == FxButtonSize.sm ? 14 : 18,
                color: widget.foregroundColor ??
                    DefaultTextStyle.of(buttonContext).style.color,
                semanticsLabel: '处理中',
              ),
            ),
          ),
        ),
      ],
    );
    final Widget button;
    switch (widget.variant) {
      case FxButtonVariant.primary:
        button = ShadButton(
          onPressed: _effectiveAction,
          size: _shadSize,
          expands: widget.expanded,
          height: effectiveHeight,
          child: child,
        );
        break;
      case FxButtonVariant.secondary:
        button = ShadButton.secondary(
          onPressed: _effectiveAction,
          size: _shadSize,
          expands: widget.expanded,
          height: effectiveHeight,
          child: child,
        );
        break;
      case FxButtonVariant.outline:
        button = ShadButton.outline(
          onPressed: _effectiveAction,
          size: _shadSize,
          expands: widget.expanded,
          height: effectiveHeight,
          child: child,
        );
        break;
      case FxButtonVariant.ghost:
        button = ShadButton.ghost(
          onPressed: _effectiveAction,
          size: _shadSize,
          expands: widget.expanded,
          height: effectiveHeight,
          child: child,
        );
        break;
      case FxButtonVariant.destructive:
        button = ShadButton.destructive(
          onPressed: _effectiveAction,
          size: _shadSize,
          expands: widget.expanded,
          height: effectiveHeight,
          child: child,
        );
        break;
      case FxButtonVariant.link:
        button = ShadButton.link(
          onPressed: _effectiveAction,
          size: _shadSize,
          expands: widget.expanded,
          height: effectiveHeight,
          child: child,
        );
        break;
    }
    return button;
  }
}
