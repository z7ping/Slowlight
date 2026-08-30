import 'package:flutter/material.dart';

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
/// 视觉与交互以 docs/design/mockups/index.html 的「回顾」页为基线。
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
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final views = FxSegmented(
                labels: const ['概览', '统计', '时间分配'],
                selectedIndex: _viewIndex,
                onChanged: (index) => setState(() => _viewIndex = index),
                expanded: compact,
              );
              final period = _viewIndex == 0
                  ? FxSegmented(
                      labels: const ['今天', '本周', '本月'],
                      selectedIndex: _periodIndex,
                      onChanged: (index) =>
                          setState(() => _periodIndex = index),
                      expanded: compact,
                    )
                  : const SizedBox.shrink();

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: double.infinity, child: views),
                    if (_viewIndex == 0) ...[
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: period),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  views,
                  if (_viewIndex == 0) ...[
                    const Spacer(),
                    period,
                  ],
                ],
              );
            },
          ),
        ),
        if (_viewIndex == 0 && _periodIndex == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _todaySummary(),
                style: SlowlightTypography.caption(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
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

  Widget _overviewBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorView();
    return switch (_periodIndex) {
      1 => const WeeklyReviewScreen(),
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
    final questions = (_review['questions'] as List? ?? const [])
        .whereType<Map>()
        .map((q) => Map<String, dynamic>.from(q))
        .where((q) => !_answered.contains(q['id']?.toString() ?? ''))
        .take(2)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 760;
              final factsCard = _factsCard(facts);
              final right = Column(
                children: [
                  _questionsCard(questions),
                  const SizedBox(height: 14),
                  _patternsCard(patterns),
                  const SizedBox(height: 14),
                  _restCard(),
                ],
              );

              if (!desktop) {
                return Column(
                  children: [
                    factsCard,
                    const SizedBox(height: 14),
                    right,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 12, child: factsCard),
                  const SizedBox(width: 16),
                  Expanded(flex: 10, child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _factsCard(Map<String, dynamic> facts) {
    final items = <ReviewTimelineItem>[];
    final tasks = (facts['today_completed_tasks'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);

    for (final raw in tasks) {
      final task = Map<String, dynamic>.from(raw);
      items.add(
        ReviewTimelineItem(
          color: AppTheme.chartGreen,
          time: task['completed_at']?.toString().isNotEmpty == true
              ? task['completed_at'].toString()
              : '今天',
          title: '✅ 完成「${task['title'] ?? ''}」',
          note: (task['list_name']?.toString() ?? '').isEmpty
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
      final note = distribution.isEmpty
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
        .where((entry) => _sameDay(entry.createdAt, today))
        .take(5)) {
      items.add(
        ReviewTimelineItem(
          color: AppTheme.chartPurple,
          time: '${_two(entry.createdAt.hour)}:${_two(entry.createdAt.minute)}',
          title: entry.entryType == 'observation' ? '写下观察' : '留下解释',
          note: entry.content,
        ),
      );
    }

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '事实'),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              '今天还没有足够的事实记录。先去记录几件事？',
              style: SlowlightTypography.secondary(context).copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
          const FxSectionHeader(title: '回应问题'),
          const SizedBox(height: 10),
          if (questions.isEmpty)
            Text(
              '今天暂时没有需要回应的问题。',
              style: SlowlightTypography.secondary(context).copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  onTap: index == 0
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
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question['content']?.toString() ?? '',
                          style: SlowlightTypography.body(context).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!expanded) ...[
                          const SizedBox(height: 6),
                          Text(
                            '尚未回应 · 点击展开',
                            style:
                                SlowlightTypography.caption(context).copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: FxInput(
                              controller: _controllerFor(question),
                              placeholder: '直接在这里写下你的回应…',
                              maxLines: 4,
                              style: SlowlightTypography.body(context),
                            ),
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
          const FxSectionHeader(title: '模式', trailing: '与昨天相比'),
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

  Widget _restCard() {
    final facts = Map<String, dynamic>.from(
      _review['facts'] as Map? ?? const {},
    );
    final focus = (facts['focus_minutes'] as num?)?.toInt() ?? 0;
    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      onTap: _openRestReview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(
            title: '休息',
            trailing: '今日 · 来自休息提醒',
          ),
          const SizedBox(height: 7),
          Text(
            '今天已记录专注 $focus 分钟；休息日志可在休息回顾中查看。',
            style: SlowlightTypography.secondary(context).copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '查看休息回顾（日志 / 7 天 / 30 天 / 分析）→',
            style: SlowlightTypography.caption(context).copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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
      await ReflectionRepository().create(
        content: content,
        questionId: id.isEmpty ? null : id,
        context: {
          'source': 'review',
          'question_type': question['type'] ?? '',
        },
      );
      if (!mounted) return;
      setState(() {
        if (id.isNotEmpty) _answered.add(id);
        _expanded.remove(_questionKey(question));
        controller.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('回应已保存'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('保存回应失败'),
        ),
      );
    }
  }

  String _todaySummary() {
    final now = DateTime.now();
    final facts = Map<String, dynamic>.from(
      _review['facts'] as Map? ?? const {},
    );
    final count = ((facts['task_completed'] as num?)?.toInt() ?? 0) +
        ((facts['habit_checked'] as num?)?.toInt() ?? 0) +
        ((facts['focus_count'] as num?)?.toInt() ?? 0) +
        _reflections.where((entry) => _sameDay(entry.createdAt, now)).length;
    return '${now.month} 月 ${now.day} 日 · 共 $count 条行为记录';
  }

  String _signed(int value) => value > 0 ? '+$value' : '$value';
  String _two(int value) => value.toString().padLeft(2, '0');
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '回顾数据加载失败',
            style: SlowlightTypography.cardTitle(context),
          ),
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
