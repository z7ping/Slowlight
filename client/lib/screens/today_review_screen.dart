import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/habit.dart';
import '../models/habit_log.dart';
import '../models/reflection_entry.dart';
import '../repositories/habit_repository.dart';
import '../repositories/reflection_repository.dart';
import '../services/api/review_api.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';
import '../widgets/reminder_review_body.dart';
import '../widgets/review/review_timeline_item.dart';
import '../widgets/review/task_30day_tab.dart';
import 'stats_screen.dart';
import 'time_distribution_screen.dart';
import 'weekly_review_screen.dart';

/// 回顾：看事实 → 回应问题 → 留下解释。
/// 回顾页采用已确认的 Android / Windows 响应式信息结构；组件复用 Fx。
class TodayReviewScreen extends StatefulWidget {
  final String initialReviewMode;

  const TodayReviewScreen({super.key, this.initialReviewMode = 'tasks'});

  @override
  State<TodayReviewScreen> createState() => _TodayReviewScreenState();
}

class _TodayReviewScreenState extends State<TodayReviewScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _review = {};
  List<ReflectionEntry> _reflections = const [];
  List<_TodayHabitFact> _todayHabitFacts = const [];
  int _viewIndex = 0;
  int _periodIndex = 0;
  final Set<String> _answered = {};
  final Set<String> _expanded = {};
  final Map<String, TextEditingController> _answerControllers = {};
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialReviewMode == 'rest') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRestReview());
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    for (final controller in _answerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Map<String, dynamic> question) {
    final id = question['id']?.toString() ?? '';
    final key = id.isEmpty ? question['content']?.toString() ?? '' : id;
    return _answerControllers.putIfAbsent(key, TextEditingController.new);
  }

  String _questionKey(Map<String, dynamic> question) {
    final id = question['id']?.toString() ?? '';
    return id.isEmpty ? question['content']?.toString() ?? '' : id;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait<dynamic>([
        ReviewApi.getTodayReview(),
        ReflectionRepository()
            .recent(limit: 30)
            .catchError((_) => <ReflectionEntry>[]),
        _loadTodayHabitFacts().catchError((_) => <_TodayHabitFact>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _review = values[0] as Map<String, dynamic>;
        _reflections = values[1] as List<ReflectionEntry>;
        _todayHabitFacts = values[2] as List<_TodayHabitFact>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<_TodayHabitFact>> _loadTodayHabitFacts() async {
    final repository = HabitRepository();
    final habits = await repository.getAll();
    final now = DateTime.now();
    final dateKey = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    final monthKey = '${now.year}-${_two(now.month)}';
    final facts = <_TodayHabitFact>[];

    for (final habit in habits) {
      try {
        final logs = await repository.logs(habit.id, month: monthKey);
        for (final log in logs) {
          if (log.date == dateKey) {
            facts.add(_TodayHabitFact(habit: habit, log: log));
          }
        }
      } catch (_) {
        // 单个习惯日志读取失败不阻断整页回顾。
      }
    }
    facts.sort((a, b) => a.log.createdAt.compareTo(b.log.createdAt));
    return facts;
  }

  Future<void> _openRestReview() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReminderReviewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_viewIndex != 0) {
                return Row(
                  children: [
                    FxButton(
                      label: '返回回顾',
                      variant: FxButtonVariant.ghost,
                      size: FxButtonSize.sm,
                      onPressed: () => setState(() => _viewIndex = 0),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _viewIndex == 1 ? '完整统计' : '时间分配',
                        style: SlowlightTypography.cardTitle(context),
                      ),
                    ),
                  ],
                );
              }
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _periodTitle(),
                    style: SlowlightTypography.pageTitle(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _periodDescription(),
                    style: SlowlightTypography.secondary(context).copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final compact = constraints.maxWidth < 700;
              final periods = FxSegmented(
                labels: const ['今天', '本周', '近 30 天'],
                selectedIndex: _periodIndex,
                onChanged: (index) => setState(() => _periodIndex = index),
                expanded: compact,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 12), periods],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  periods,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: switch (_viewIndex) {
            1 => const StatsScreen(embedded: true),
            2 => const TimeDistributionScreen(),
            _ => _overviewBody(),
          },
        ),
      ],
    );
  }

  String _periodTitle() {
    final now = DateTime.now();
    return switch (_periodIndex) {
      1 => '本周回顾',
      2 => '近 30 天回顾',
      _ => '${now.month} 月 ${now.day} 日 · 今天',
    };
  }

  String _periodDescription() => switch (_periodIndex) {
    1 => '看见一周的节奏与变化',
    2 => '回看长期积累的行为轨迹',
    _ => '行为留下轨迹，时间让自我显影',
  };

  Widget _overviewBody() {
    if (_loading) return const Center(child: FxCircularProgress());
    if (_error != null) return _errorView();
    return switch (_periodIndex) {
      1 => const WeeklyReviewScreen(embedded: true),
      2 => const TaskMonthTab(),
      _ => _todayBody(),
    };
  }

  Widget _todayBody() {
    final facts = Map<String, dynamic>.from(
      _review['facts'] as Map? ?? const {},
    );
    final patterns = Map<String, dynamic>.from(
      _review['patterns'] as Map? ?? const {},
    );
    final today = DateTime.now();
    final hasReflections = _reflections.any(
      (entry) => entry.entryType == 'reflection' &&
          _sameDay(entry.createdAt, today),
    );
    final questions = (_review['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((q) => Map<String, dynamic>.from(q))
        .where((q) {
          final id = q['id']?.toString() ?? '';
          return !_answered.contains(_questionKey(q)) &&
              (id.isEmpty ||
                  !_reflections.any((entry) => entry.questionId == id));
        })
        .take(1)
        .toList(growable: false);

    return FxRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _snapshotCard(facts),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final timeline = _factsCard(facts);
                      final reflection = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_hasChanges(patterns)) ...[
                            _patternsCard(patterns),
                            const SizedBox(height: 16),
                          ],
                          if (questions.isNotEmpty) _questionsCard(questions),
                          if (hasReflections) ...[
                            if (questions.isNotEmpty) const SizedBox(height: 16),
                            _reflectionsCard(),
                          ],
                          if (questions.isEmpty) ...[
                            if (hasReflections) const SizedBox(height: 16),
                            _freeNoteCard(),
                          ],
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FxButton(
                              label: '查看休息回顾 →',
                              variant: FxButtonVariant.link,
                              size: FxButtonSize.sm,
                              onPressed: _openRestReview,
                            ),
                          ),
                        ],
                      );
                      if (constraints.maxWidth < 760) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            timeline,
                            const SizedBox(height: 16),
                            reflection,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 12, child: timeline),
                          const SizedBox(width: 16),
                          Expanded(flex: 10, child: reflection),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _snapshotCard(Map<String, dynamic> facts) {
    final tasks = (facts['task_completed'] as num?)?.toInt() ?? 0;
    final habits = (facts['habit_checked'] as num?)?.toInt() ?? 0;
    final focus = (facts['focus_minutes'] as num?)?.toInt() ?? 0;
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '今日概况'),
          const SizedBox(height: 8),
          FxResponsiveFormGrid(
            minColumnWidth: 96,
            maxColumns: 3,
            horizontalGap: 8,
            verticalGap: 8,
            children: [
              FxStatCell(value: '$tasks', label: '完成任务'),
              FxStatCell(value: '$habits', label: '习惯打卡'),
              FxStatCell(value: '$focus', label: '专注分钟'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FxButton(
                label: '查看完整统计 →',
                variant: FxButtonVariant.link,
                size: FxButtonSize.sm,
                onPressed: () => setState(() => _viewIndex = 1),
              ),
              FxButton(
                label: '查看时间分配 →',
                variant: FxButtonVariant.link,
                size: FxButtonSize.sm,
                onPressed: () => setState(() => _viewIndex = 2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasChanges(Map<String, dynamic> patterns) =>
      ((patterns['focus_delta'] as num?)?.toInt() ?? 0) != 0 ||
      ((patterns['habit_delta'] as num?)?.toInt() ?? 0) != 0 ||
      ((patterns['task_delta'] as num?)?.toInt() ?? 0) != 0;

  Widget _freeNoteCard() {
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '留给今天的一句话'),
          const SizedBox(height: 8),
          Text(
            '今天最值得记住的一件事是什么？',
            style: SlowlightTypography.secondary(context).copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FxInput(
            controller: _noteController,
            placeholder: '写下一点想法…',
            maxLines: 3,
            style: SlowlightTypography.body(context),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FxButton(
              label: '保存记录',
              size: FxButtonSize.sm,
              onPressed: _saveNote,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNote() async {
    final content = _noteController.text.trim();
    if (content.isEmpty) return;
    try {
      final saved = await ReflectionRepository().create(
        content: content,
        context: const {'source': 'review', 'question_type': 'free_note'},
      );
      if (!mounted) return;
      setState(() {
        _reflections = [saved, ..._reflections].take(30).toList();
        _noteController.clear();
      });
      FxNotice.showContent(context, const Text('记录已保存'));
    } catch (_) {
      if (!mounted) return;
      FxNotice.showContent(context, const Text('保存记录失败'));
    }
  }

  Widget _factsCard(Map<String, dynamic> facts) {
    final items = <ReviewTimelineItem>[];
    final tasks = (facts['today_completed_tasks'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);

    for (final raw in tasks) {
      final task = Map<String, dynamic>.from(raw);
      final completedAt = DateTime.tryParse(
        task['completed_at']?.toString() ?? '',
      )?.toLocal();
      items.add(
        ReviewTimelineItem(
          color: AppTheme.chartGreen,
          time: completedAt == null ? '今天' : _clockTime(completedAt),
          title: '完成「${task['title'] ?? ''}」',
          note:
              (task['list_name']?.toString() ?? '').isEmpty
                  ? null
                  : task['list_name'].toString(),
        ),
      );
    }

    if (_todayHabitFacts.isNotEmpty) {
      for (final fact in _todayHabitFacts) {
        final log = fact.log;
        items.add(
          ReviewTimelineItem(
            color: ColorUtils.safeParse(fact.habit.color),
            time: '${_two(log.createdAt.hour)}:${_two(log.createdAt.minute)}',
            title: '${fact.habit.icon} 打卡「${fact.habit.name}」',
            note: _habitFactNote(log),
          ),
        );
      }
    } else {
      final habitChecked = (facts['habit_checked'] as num?)?.toInt() ?? 0;
      if (habitChecked > 0) {
        items.add(
          ReviewTimelineItem(
            color: AppTheme.chartYellow,
            time: '今天',
            title: '习惯打卡 $habitChecked 次',
          ),
        );
      }
    }

    final focusMinutes = (facts['focus_minutes'] as num?)?.toInt() ?? 0;
    final focusCount = (facts['focus_count'] as num?)?.toInt() ?? 0;
    if (focusMinutes > 0 || focusCount > 0) {
      final distribution = (facts['tag_distribution'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      final note =
          distribution.isEmpty
              ? '当前数据源只提供今日专注汇总'
              : '主要投入：${distribution.first['name'] ?? ''}';
      items.add(
        ReviewTimelineItem(
          color: AppTheme.info,
          time: '今天',
          title: '专注 $focusMinutes 分钟 · $focusCount 次',
          note: note,
        ),
      );
    }

    final today = DateTime.now();
    for (final entry in _reflections
        .where((entry) =>
            entry.entryType == 'observation' &&
            _sameDay(entry.createdAt, today))
        .take(5)) {
      items.add(
        ReviewTimelineItem(
          color: AppTheme.chartPurple,
          time: _clockTime(entry.createdAt),
          title: '记录观察',
          note: entry.content,
        ),
      );
    }

    // 仅已知精确时间的记录参与时间排序；无时间的汇总置于末尾。
    items.sort(compareReviewTimelineItems);

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '行为轨迹'),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const FxEmptyState(
              icon: LucideIcons.footprints,
              title: '今天还没有留下行为记录',
              subtitle: '先记录一件真实发生的事，轨迹就会出现在这里。',
              padding: EdgeInsets.symmetric(vertical: 24),
            )
          else
            ...List.generate(
              items.length,
              (index) => ReviewTimelineItem(
                color: items[index].color,
                time: items[index].time,
                title: items[index].title,
                note: items[index].note,
                last: index == items.length - 1,
              ),
            ),
        ],
      ),
    );
  }

  String? _habitFactNote(HabitLog log) {
    final parts = <String>[];
    if (log.durationMin > 0) parts.add('${log.durationMin} 分钟');
    final period = _periodLabel(log.period);
    if (period.isNotEmpty) parts.add(period);
    if (log.note.trim().isNotEmpty) parts.add('“${log.note.trim()}”');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String _periodLabel(String value) => switch (value) {
    'morning' => '☀️ 早晨',
    'afternoon' => '下午',
    'evening' => '傍晚',
    'night' => '🌙 晚间',
    _ => '',
  };

  Widget _questionsCard(List<Map<String, dynamic>> questions) {
    final theme = Theme.of(context);
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '值得想一想'),
          const SizedBox(height: 10),
          if (questions.isEmpty)
            Text(
              '今天暂时没有需要回应的问题。',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            ...List.generate(questions.length, (index) {
              final question = questions[index];
              final key = _questionKey(question);
              final expanded = index == 0 || _expanded.contains(key);
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == questions.length - 1 ? 0 : 10,
                ),
                child: FxInkWell(
                  borderRadius: BorderRadius.circular(SlowlightRadius.md),
                  onTap:
                      index == 0
                          ? null
                          : () => setState(() {
                            if (expanded) {
                              _expanded.remove(key);
                            } else {
                              _expanded.add(key);
                            }
                          }),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(SlowlightRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question['content']?.toString() ?? '',
                          style: SlowlightTypography.body(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (!expanded) ...[
                          const SizedBox(height: 6),
                          Text(
                            '尚未回应 · 点击展开',
                            style: SlowlightTypography.caption(
                              context,
                            ).copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          // FxInput 自带表面、焦点边框，不叠加第二层容器边框。
                          FxInput(
                            controller: _controllerFor(question),
                            placeholder: '直接在这里写下你的回应…',
                            maxLines: 4,
                            style: SlowlightTypography.body(context),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FxButton(
                              label: '保存回应',
                              size: FxButtonSize.sm,
                              onPressed: () => _saveAnswer(question),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _patternsCard(Map<String, dynamic> patterns) {
    final facts = <String>[];
    final focusDelta = (patterns['focus_delta'] as num?)?.toInt() ?? 0;
    final habitDelta = (patterns['habit_delta'] as num?)?.toInt() ?? 0;
    final taskDelta = (patterns['task_delta'] as num?)?.toInt() ?? 0;

    if (focusDelta != 0) {
      facts.add('· 专注时长较昨天 ${_signed(focusDelta)} 分钟');
    }
    if (habitDelta != 0) {
      facts.add('· 习惯打卡较昨天 ${_signed(habitDelta)} 次');
    }
    if (taskDelta != 0) {
      facts.add('· 完成任务较昨天 ${_signed(taskDelta)} 个');
    }
    if (facts.isEmpty) {
      facts.add('· 今天与昨天的主要行为数量暂时没有明显变化');
    }

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '变化', trailing: '与昨天相比'),
          const SizedBox(height: 8),
          ...facts.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                text,
                style: SlowlightTypography.secondary(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reflectionsCard() {
    final today = DateTime.now();
    final entries = _reflections
        .where((entry) =>
            entry.entryType == 'reflection' &&
            _sameDay(entry.createdAt, today))
        .take(5)
        .toList(growable: false);
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '我的理解'),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(
              '今天还没有留下回应。',
              style: SlowlightTypography.secondary(context).copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.context['question_prompt']
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true) ...[
                    Text(
                      '回应：${entry.context['question_prompt']}',
                      style: SlowlightTypography.caption(context).copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    entry.content,
                    style: SlowlightTypography.body(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _clockTime(entry.createdAt),
                    style: SlowlightTypography.caption(context).copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Future<void> _saveAnswer(Map<String, dynamic> question) async {
    final controller = _controllerFor(question);
    final content = controller.text.trim();
    if (content.isEmpty) return;
    final id = question['id']?.toString() ?? '';

    try {
      final saved = await ReflectionRepository().create(
        content: content,
        questionId: id.isEmpty ? null : id,
        context: {
          'source': 'review',
          'question_type': question['type'] ?? '',
          'question_prompt': question['content']?.toString() ?? '',
        },
      );
      if (!mounted) return;
      setState(() {
        _reflections = [saved, ..._reflections].take(30).toList();
        _answered.add(_questionKey(question));
        _expanded.remove(_questionKey(question));
        controller.clear();
      });
      FxNotice.showContent(context, Text('回应已保存'));
    } catch (_) {
      if (!mounted) return;
      FxNotice.showContent(context, Text('保存回应失败'));
    }
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';
  String _two(int value) => value.toString().padLeft(2, '0');
  String _clockTime(DateTime value) =>
      '${_two(value.hour)}:${_two(value.minute)}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('回顾数据加载失败', style: SlowlightTypography.cardTitle(context)),
          const SizedBox(height: 12),
          FxButton(
            label: '重试',
            variant: FxButtonVariant.secondary,
            onPressed: _load,
          ),
        ],
      ),
    );
  }
}

class _TodayHabitFact {
  final Habit habit;
  final HabitLog log;

  const _TodayHabitFact({required this.habit, required this.log});
}
