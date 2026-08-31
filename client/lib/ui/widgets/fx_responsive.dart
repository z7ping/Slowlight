import 'package:flutter/material.dart';

import '../typography_tokens.dart';

/// Fx 响应式表单网格。
///
/// 依据组件拿到的真实可用宽度决定列数，不读取整窗宽度，也不使用
/// “字体到某个倍率就强制单列”的开关。文字放大只会提高单列所需宽度，
/// 因而 Windows 中等窗口和 Android 大字体都能自然退化。
class FxResponsiveFormGrid extends StatelessWidget {
  final List<Widget> children;
  final double minColumnWidth;
  final int maxColumns;
  final double horizontalGap;
  final double verticalGap;

  const FxResponsiveFormGrid({
    super.key,
    required this.children,
    this.minColumnWidth = 240,
    this.maxColumns = 2,
    this.horizontalGap = 12,
    this.verticalGap = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final scaleFactor = 1 + ((scale - 1).clamp(0.0, 1.0) * .35);
        final effectiveMinWidth = minColumnWidth * scaleFactor;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : effectiveMinWidth;
        var columns =
            ((availableWidth + horizontalGap) /
                    (effectiveMinWidth + horizontalGap))
                .floor();
        columns = columns.clamp(1, maxColumns).toInt();
        final width =
            (availableWidth - horizontalGap * (columns - 1)) / columns;

        return Wrap(
          spacing: horizontalGap,
          runSpacing: verticalGap,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

/// Fx 统一表单字段容器。
class FxFormField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? helperText;

  const FxFormField({
    super.key,
    required this.label,
    required this.child,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: SlowlightTypography.componentFieldLabel(context).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText!,
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
