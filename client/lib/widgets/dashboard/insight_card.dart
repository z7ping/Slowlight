import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../reflection_composer.dart';

/// 洞察项只是“值得看一眼的问题”，不携带系统替用户决定的下一步。
class Insight {
  final String id;
  final String content;
  final String type;
  final String? actionLabel;
  final String? actionHint;

  Insight({
    required this.id,
    required this.content,
    required this.type,
    this.actionLabel,
    this.actionHint,
  });

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? '',
    );
  }
}

/// Today 只显示少量值得留意的问题，深入解释留给用户和 Review。
class InsightCard extends StatelessWidget {
  final List<Insight> insights;
  final int maxDisplay;
  final Set<String> ignoredIds;
  final ValueChanged<String>? onIgnore;
  final ValueChanged<Insight>? onAction;

  const InsightCard({
    super.key,
    required this.insights,
    this.maxDisplay = 1,
    this.ignoredIds = const {},
    this.onIgnore,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final visibleInsights = insights
        .where((i) => !ignoredIds.contains(i.id))
        .take(maxDisplay)
        .toList();

    return FxCard(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '值得留意',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleInsights.isEmpty)
            _buildEmptyState(context)
          else
            ...visibleInsights.map((item) => _buildItem(context, item)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        '今天暂时没有特别需要关注的变化。',
        style: TextStyle(
          fontSize: AppTheme.textSm,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, Insight insight) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insight.content,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FxButton(
                label: '写下想法',
                variant: FxButtonVariant.secondary,
                size: FxButtonSize.sm,
                onPressed: () async {
                  final saved = await ReflectionComposer.show(
                    context,
                    questionId: insight.id.isEmpty ? null : insight.id,
                    prompt: insight.content,
                    contextData: {'question_type': insight.type},
                  );
                  if (saved && insight.id.isNotEmpty) {
                    onIgnore?.call(insight.id);
                  }
                },
              ),
              FxButton(
                label: '暂时略过',
                variant: FxButtonVariant.ghost,
                size: FxButtonSize.sm,
                onPressed: insight.id.isEmpty
                    ? null
                    : () => onIgnore?.call(insight.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
