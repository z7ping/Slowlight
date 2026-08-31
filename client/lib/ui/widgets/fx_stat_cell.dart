import 'package:flutter/material.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';

/// FxStatCell — 统计值展示单元。
///
/// value 使用页面标题级别强调，suffix/label 使用辅助与说明文字语义。
class FxStatCell extends StatelessWidget {
  final String value;
  final String label;
  final String? suffix;
  final Color? backgroundColor;
  final Border? border;
  final double borderRadius;

  const FxStatCell({
    super.key,
    required this.value,
    required this.label,
    this.suffix,
    this.backgroundColor,
    this.border,
    this.borderRadius = SlowlightRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SlowlightSpacing.xl,
        vertical: SlowlightSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        border: border,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: SlowlightTypography.pageTitle(context).copyWith(
                fontWeight: FontWeight.w700,
              ),
              children: [
                TextSpan(text: value),
                if (suffix != null)
                  TextSpan(
                    text: suffix,
                    style: SlowlightTypography.secondary(context).copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
