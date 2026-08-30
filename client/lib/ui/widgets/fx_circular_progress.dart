import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 统一圆形进度。
///
/// [value] 为 null 时显示不确定加载；有值时显示 0.0~1.0 的确定进度。
/// 使用 Flutter Canvas/Animation 基础设施绘制，不依赖 Material
/// CircularProgressIndicator。
class FxCircularProgress extends StatefulWidget {
  const FxCircularProgress({
    super.key,
    this.value,
    this.backgroundColor,
    this.color,
    this.valueColor,
    this.strokeWidth = 4,
    this.strokeAlign = 0,
    this.semanticsLabel,
    this.semanticsValue,
    this.strokeCap = StrokeCap.round,
    this.constraints,
  });

  final double? value;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;
  final double strokeWidth;
  final double strokeAlign;
  final String? semanticsLabel;
  final String? semanticsValue;
  final StrokeCap strokeCap;
  final BoxConstraints? constraints;

  @override
  State<FxCircularProgress> createState() => _FxCircularProgressState();
}

class _FxCircularProgressState extends State<FxCircularProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant FxCircularProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.value == null) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final effectiveColor =
        widget.valueColor?.value ?? widget.color ?? theme.colorScheme.primary;
    final repaint = Listenable.merge([
      if (widget.value == null) _controller,
      if (widget.valueColor != null) widget.valueColor!,
    ]);

    return Semantics(
      label: widget.semanticsLabel,
      value: widget.semanticsValue,
      child: ConstrainedBox(
        constraints: widget.constraints ??
            const BoxConstraints.tightFor(width: 36, height: 36),
        child: CustomPaint(
          painter: _FxCircularProgressPainter(
            value: widget.value,
            animation: _controller,
            backgroundColor: widget.backgroundColor,
            color: effectiveColor,
            strokeWidth: widget.strokeWidth,
            strokeAlign: widget.strokeAlign,
            strokeCap: widget.strokeCap,
            repaint: repaint,
          ),
        ),
      ),
    );
  }
}

class _FxCircularProgressPainter extends CustomPainter {
  _FxCircularProgressPainter({
    required this.value,
    required this.animation,
    required this.backgroundColor,
    required this.color,
    required this.strokeWidth,
    required this.strokeAlign,
    required this.strokeCap,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final double? value;
  final Animation<double> animation;
  final Color? backgroundColor;
  final Color color;
  final double strokeWidth;
  final double strokeAlign;
  final StrokeCap strokeCap;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortestSide = math.min(size.width, size.height);
    final alignInset = strokeWidth * ((strokeAlign + 1) / 2);
    final radius = math.max(0, shortestSide / 2 - alignInset);
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (backgroundColor case final background?) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = background
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap;

    if (value case final progress?) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        paint,
      );
      return;
    }

    final phase = animation.value;
    final start = -math.pi / 2 + math.pi * 2 * phase;
    final sweep = math.pi * (0.8 + 0.5 * math.sin(phase * math.pi * 2));
    canvas.drawArc(rect, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _FxCircularProgressPainter oldDelegate) {
    return value != oldDelegate.value ||
        backgroundColor != oldDelegate.backgroundColor ||
        color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        strokeAlign != oldDelegate.strokeAlign ||
        strokeCap != oldDelegate.strokeCap;
  }
}
