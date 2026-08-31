import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxProgress — 统一线性进度反馈。
///
/// [value] 为 null 时使用 shadcn_ui 的不确定进度动画；否则取 0.0~1.0。
class FxProgress extends StatelessWidget {
  final double? value;
  final double? height;
  final Color? color;
  final Color? backgroundColor;
  final String? semanticsLabel;
  final String? semanticsValue;

  const FxProgress({
    super.key,
    this.value,
    this.height,
    this.color,
    this.backgroundColor,
    this.semanticsLabel,
    this.semanticsValue,
  });

  @override
  Widget build(BuildContext context) {
    return ShadProgress(
      value: value,
      minHeight: height,
      color: color,
      backgroundColor: backgroundColor,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
    );
  }
}

/// FxProgressRing — 圆形进度反馈。
///
/// Shad 暂无对应圆环组件，因此由 Fx 层统一绘制；业务层只提供进度和中心内容。
/// 这类平台无关的可视化能力不要求业务层直接依赖 Material ProgressIndicator。
class FxProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;
  final Widget? child;
  final String? semanticsLabel;
  final String? semanticsValue;

  const FxProgressRing({
    super.key,
    required this.value,
    required this.size,
    required this.strokeWidth,
    required this.color,
    required this.backgroundColor,
    this.child,
    this.semanticsLabel,
    this.semanticsValue,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: semanticsLabel,
      value: semanticsValue,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FxProgressRingPainter(
            value: normalized,
            strokeWidth: strokeWidth,
            color: color,
            backgroundColor: backgroundColor,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _FxProgressRingPainter extends CustomPainter {
  final double value;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;

  const _FxProgressRingPainter({
    required this.value,
    required this.strokeWidth,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        progress,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FxProgressRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.color != color ||
      oldDelegate.backgroundColor != backgroundColor;
}
