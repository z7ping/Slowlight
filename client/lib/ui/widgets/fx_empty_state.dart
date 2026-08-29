import 'package:flutter/material.dart';

import '../typography_tokens.dart';

/// FxEmptyState — 空状态统一表达。
class FxEmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  final double emojiSize;

  const FxEmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.action,
    this.padding = const EdgeInsets.symmetric(vertical: 48),
    this.emojiSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: emojiSize)),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SlowlightTypography.cardTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}
