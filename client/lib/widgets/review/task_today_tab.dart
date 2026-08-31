import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../reflection_composer.dart';
import 'ai_review_card.dart';
import 'reflection_history_card.dart';

class TaskTodayTab extends StatelessWidget {
  final Map<String, dynamic> review;
  final Map<String, dynamic> outputStats;
  final Set<String> ignoredQuestionIds;
  final ValueChanged<String> onIgnoreQuestion;
  final Future<void> Function()? onRefresh;

  const TaskTodayTab({
    super.key,
    required this.review,
    required this.outputStats,
    required this.ignoredQuestionIds,
    required this.onIgnoreQuestion,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = review['facts'] as Map<String, dynamic>? ?? {};
    final patterns = review['patterns'] as Map<String, dynamic>? ?? {};
    final allQuestions = (review['questions'] as List?) ?? [];

    final taskCompleted = facts['task_completed'] ?? 0;
    final taskCreated = facts['task_created'] ?? 0;
    final taskDelta = patterns['task_delta'] ?? 0;
    final taskWeekDelta = patterns['task_week_delta'] ?? 0;
    final todayTasks = (facts['today_completed_tasks'] as List?) ?? [];

    final taskQuestions =
        allQuestions
            .where((q) {
              final question = q as Map<String, dynamic>;
              final type = question['type'] as String? ?? '';
              return [
                'task_backlog',
                'completion_rate',
                'task_focus',
                'quiet_day',
              ].contains(type);
            })
            .where((q) {
              return !ignoredQuestionIds.contains(
                (q as Map<String, dynamic>)['id'],
              );
            })
            .take(2)
            .toList();

    return FxRefresh(
      onRefresh: onRefresh ?? () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _reflectionEntry(context, theme, taskQuestions),
          const SizedBox(height: 12),
          const ReflectionHistoryCard(),
          const SizedBox(height: 18),
          _sectionLabel(theme, title: '事实', subtitle: '这些只是今天留下的记录，不代表评价。'),
          const SizedBox(height: 8),
          _overviewCard(
            theme,
            taskCompleted,
            taskCreated,
            taskDelta,
            taskWeekDelta,
          ),
          const SizedBox(height: 10),
          if (todayTasks.isNotEmpty)
            _completedList(theme, todayTasks)
          else
            _emptyHint(theme),
          const SizedBox(height: 18),
          _sectionLabel(
            theme,
            title: '补充观察',
            subtitle: '如果启用了 AI，它只能基于已有事实和你的记录补充视角。',
          ),
          const SizedBox(height: 8),
          AiReviewCard(review: review),
        ],
      ),
    );
  }

  Widget _reflectionEntry(
    BuildContext context,
    ThemeData theme,
    List questions,
  ) {
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '我的解释',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            questions.isEmpty
                ? '今天有什么值得记住、困惑或想补充的吗？'
                : '系统看到了一些变化。先不用找答案，只写下你自己的理解。',
            style: TextStyle(
              fontSize: SlowlightTypography.secondarySize,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (questions.isEmpty)
            FxButton(
              label: '写下今天的观察',
              icon: Icons.edit_outlined,
              variant: FxButtonVariant.secondary,
              onPressed:
                  () => ReflectionComposer.show(
                    context,
                    prompt: '今天有什么值得记住、困惑或想补充的吗？',
                    contextData: const {'source': 'today_review'},
                  ),
            )
          else
            ...questions.map<Widget>((q) {
              final question = q as Map<String, dynamic>;
              final id = question['id'] as String? ?? '';
              final content = question['content'] as String? ?? '';
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.28,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FxButton(
                          label: '写下我的理解',
                          variant: FxButtonVariant.secondary,
                          size: FxButtonSize.sm,
                          onPressed: () async {
                            final saved = await ReflectionComposer.show(
                              context,
                              questionId: id.isEmpty ? null : id,
                              prompt: content,
                              contextData: {
                                'source': 'today_review',
                                'question_type': question['type'] ?? '',
                              },
                            );
                            if (saved && id.isNotEmpty) onIgnoreQuestion(id);
                          },
                        ),
                        FxButton(
                          label: '先略过',
                          variant: FxButtonVariant.ghost,
                          size: FxButtonSize.sm,
                          onPressed:
                              id.isEmpty ? null : () => onIgnoreQuestion(id),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _sectionLabel(
    ThemeData theme, {
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: SlowlightTypography.captionSize,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _overviewCard(
    ThemeData theme,
    int completed,
    int created,
    int delta,
    int weekDelta,
  ) {
    final hasDelta = delta != 0 || weekDelta != 0;
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _statCol(theme, '$completed', '完成任务')),
              Container(
                width: 1,
                height: 38,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(child: _statCol(theme, '$created', '新建任务')),
            ],
          ),
          if (hasDelta) ...[
            const FxSeparator.horizontal(height: 24),
            if (delta != 0) _deltaRow(theme, delta, '昨天'),
            if (weekDelta != 0) _deltaRow(theme, weekDelta, '上周今天'),
          ],
        ],
      ),
    );
  }

  Widget _statCol(ThemeData theme, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _deltaRow(ThemeData theme, int delta, String compare) {
    final sign = delta > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '较$compare $sign$delta',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _completedList(ThemeData theme, List todayTasks) {
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今天完成了什么',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...todayTasks.map<Widget>(
            (item) => _taskRow(theme, item as Map<String, dynamic>),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(ThemeData theme, Map<String, dynamic> task) {
    final level = task['output_level'] as String? ?? '';
    final listName = task['list_name'] as String? ?? '';
    final completedAt = task['completed_at'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['title'] ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (level.isNotEmpty ||
                    listName.isNotEmpty ||
                    completedAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (level.isNotEmpty) '输出 $level',
                      if (listName.isNotEmpty) listName,
                      if (completedAt.isNotEmpty) completedAt,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(ThemeData theme) {
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 18,
      padding: const EdgeInsets.all(18),
      child: Text(
        '今天还没有完成记录。没有记录也是事实，不需要为了填满回顾而补任务。',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }
}
