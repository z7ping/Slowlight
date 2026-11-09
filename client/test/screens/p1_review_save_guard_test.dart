import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/habit_log.dart';
import 'package:slowlight/models/today_timeline_item.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/screens/today_review_screen.dart';
import 'package:slowlight/screens/weekly_review_screen.dart';
import 'package:slowlight/widgets/review/review_timeline_item.dart';
import 'package:slowlight/widgets/review/task_30day_tab.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/utils/local_time_boundary.dart';

import '../support/fx_test_host.dart';

class _NoHabits extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => const [];
}

class _SameNameHabits extends HabitRepository {
  final now = DateTime.now();
  bool failFirst = false;

  @override
  Future<List<Habit>> getAll() async => [
    Habit(
      id: 21, userId: 1, name: '阅读', icon: '📘',
      createdAt: now,
    ),
    Habit(
      id: 22, userId: 1, name: '阅读', icon: '📘',
      createdAt: now,
    ),
  ];

  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async {
    if (habitId == 21 && failFirst) throw StateError('log read failed');
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final isFirst = habitId == 21;
    return [
      HabitLog(
        id: isFirst ? 201 : failFirst ? 303 : 202,
        habitId: habitId,
        date: date,
        period: '',
        durationMin: 0,
        note: isFirst ? '纸书旧事实'
            : failFirst ? '电子书新事实' : '电子书旧事实',
        // A log added later may have happened earlier than it was recorded.
        occurredAt: DateTime(now.year, now.month, now.day,
            isFirst ? 16 : 8, isFirst ? 30 : 10),
        createdAt: DateTime(now.year, now.month, now.day,
            isFirst ? 19 : 20, 55),
      ),
    ];
  }
}

class _ControlledReflections extends ReflectionRepository {
  int calls = 0;
  bool failRecent = false;
  List<ReflectionEntry> recentEntries = const [];
  final Completer<ReflectionEntry> pending = Completer<ReflectionEntry>();

  @override
  Future<List<ReflectionEntry>> recent({int limit = 20}) async {
    if (failRecent) throw StateError('temporarily cannot read responses');
    return recentEntries;
  }

  @override
  Future<ReflectionEntry> create({
    required String content,
    String entryType = 'reflection',
    String? questionId,
    String? dimensionKey,
    Map<String, dynamic> context = const {},
    List<int> tagIds = const [],
  }) {
    calls++;
    return pending.future;
  }
}

class _DeferredReflections extends _ControlledReflections {
  final Completer<List<ReflectionEntry>> awaiting =
      Completer<List<ReflectionEntry>>();

  @override
  Future<List<ReflectionEntry>> recent({int limit = 20}) => awaiting.future;
}

class _PeriodReflections extends ReflectionRepository {
  final List<ReflectionEntry> entries = [];
  int lookupCalls = 0;
  int createCalls = 0;
  bool failLookup = false;
  bool throwAfterCommit = false;
  String? lastQuestionId;

  @override
  Future<ReflectionEntry?> findPeriodResponse(
    String questionId, {
    String? legacyWeekStart,
    String? legacyWeekEnd,
  }) async {
    lookupCalls++;
    lastQuestionId = questionId;
    if (failLookup) throw StateError('read not confirmed');
    for (final entry in entries.reversed) {
      if (entry.questionId == questionId) return entry;
      if (legacyWeekStart != null && legacyWeekEnd != null &&
          entry.questionId == null &&
          entry.context['source'] == 'weekly_review' &&
          entry.context['week_start'] == legacyWeekStart &&
          entry.context['week_end'] == legacyWeekEnd) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<ReflectionEntry> create({
    required String content,
    String entryType = 'reflection',
    String? questionId,
    String? dimensionKey,
    Map<String, dynamic> context = const {},
    List<int> tagIds = const [],
  }) async {
    createCalls++;
    final saved = ReflectionEntry(
      id: 800 + createCalls,
      entryType: entryType,
      questionId: questionId,
      dimensionKey: dimensionKey,
      content: content,
      context: context,
      createdAt: DateTime.now(),
    );
    entries.add(saved);
    if (throwAfterCommit) throw StateError('ACK lost');
    return saved;
  }
}

void main() {
  testWidgets('P09 定位跨期观察保留原始日期，不冒充今日统计', (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _ControlledReflections();
    final originalDate = DateTime.now().subtract(const Duration(days: 7));
    final observation = ReflectionEntry(
      id: 320,
      entryType: 'observation',
      content: '上周一次真实的工作观察',
      createdAt: originalDate,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TodayReviewScreen(
          focusObservation: observation,
          focusRequestId: 1,
          reflectionRepository: repository,
          habitRepository: _NoHabits(),
          reviewLoader: () async => {
            'facts': <String, dynamic>{},
            'patterns': <String, dynamic>{},
            'questions': <Map<String, dynamic>>[],
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('定位观察 · 原始记录'), findsOneWidget);
    expect(find.text('上周一次真实的工作观察'), findsOneWidget);
    expect(find.text('0 项'), findsOneWidget);
    expect(
      find.textContaining(
        '${originalDate.year}-${originalDate.month.toString().padLeft(2, '0')}-${originalDate.day.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  Widget review(_ControlledReflections repository, {
    List<Map<String, dynamic>> questions = const [],
  }) => buildFxTestHost(
    home: Scaffold(body: TodayReviewScreen(
      reflectionRepository: repository,
      habitRepository: _NoHabits(),
      reviewLoader: () async => {
        'facts': <String, dynamic>{},
        'patterns': <String, dynamic>{},
        'questions': questions,
      },
    )),
  );

  testWidgets('P03 同名习惯部分失败不重复成功行，补记按真实发生时间展示',
      (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final habits = _SameNameHabits();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TodayReviewScreen(
          habitRepository: habits,
          reflectionRepository: _ControlledReflections(),
          reviewLoader: () async => {
            'facts': <String, dynamic>{'habit_checked': 2},
            'patterns': <String, dynamic>{},
            'questions': <Map<String, dynamic>>[],
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('📘 打卡「阅读」'), findsNWidgets(2));
    expect(find.text('08:10'), findsOneWidget);
    expect(find.text('16:30'), findsOneWidget);
    expect(find.textContaining('纸书旧事实'), findsOneWidget);
    expect(find.textContaining('电子书旧事实'), findsOneWidget);

    // The two habits share a display name, but only ID=21 fails now.
    // Keep ID=21's confirmed row; replace, never duplicate, ID=22.
    habits.failFirst = true;
    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();

    expect(find.text('📘 打卡「阅读」'), findsNWidgets(2));
    expect(find.textContaining('纸书旧事实'), findsOneWidget);
    expect(find.textContaining('电子书新事实'), findsOneWidget);
    expect(find.textContaining('电子书旧事实'), findsNothing);
    expect(find.textContaining('部分记录暂时无法加载'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P03 今日事实先展示，不等待挂起的历史回应读取', (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final responses = _DeferredReflections();
    final reviewData = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TodayReviewScreen(
        reflectionRepository: responses,
        habitRepository: _NoHabits(),
        reviewLoader: () => reviewData.future,
      )),
    ));
    await tester.pump();
    expect(find.byType(FxCircularProgress), findsOneWidget);
    reviewData.complete({
      'facts': <String, dynamic>{'task_completed': 4},
      'patterns': <String, dynamic>{},
      'questions': <Map<String, dynamic>>[
        {'id': 'review-q1', 'content': '先核对上次的回应'},
      ],
    });
    await tester.pumpAndSettle();
    // The remaining reflection repository read is still pending.
    expect(responses.awaiting.isCompleted, isFalse);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('留给今天的一句话'), findsOneWidget);
    expect(find.text('先核对上次的回应'), findsOneWidget);
    expect(find.text('正在核对已保存的回应…'), findsOneWidget);
    final saveButton = find.ancestor(
      of: find.text('保存回应'),
      matching: find.byType(FxButton),
    );
    expect(tester.widget<FxButton>(saveButton).onPressed, isNull);
    expect(find.byType(FxCircularProgress), findsNothing);

    responses.awaiting.complete([
      ReflectionEntry(
        id: 501,
        entryType: 'reflection',
        questionId: 'review-q1',
        content: '已确认的单独回应',
        createdAt: DateTime.now(),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('已确认的单独回应'), findsOneWidget);
    expect(find.text('先核对上次的回应'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P03 本周主统计先显示，输出与每日趋势稍后填充', (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final outputs = Completer<Map<String, dynamic>>();
    final trend = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reviewLoader: () async => {
          'task_completed': 8,
          'habit_checked': 6,
          'focus_minutes': 75,
          'habit_last_week': 2,
          'task_last_week': 3,
          'focus_last_week': 60,
          'time_distribution': <Map<String, dynamic>>[],
        },
        outputStatsLoader: () => outputs.future,
        dailyTrendLoader: () => trend.future,
        periodTimelineLoader: () async => ReviewPeriodTimeline(
          observationCount: 3,
          items: [
            TodayTimelineItem(
              id: 'reflection:87',
              kind: 'observation',
              title: '本周真实观察',
              durationMinutes: 0,
              occurredAt: DateTime.now(),
            ),
          ],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(outputs.isCompleted, isFalse);
    expect(trend.isCompleted, isFalse);
    expect(find.text('本周记录'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('观察记录 3 条'), findsOneWidget);
    expect(find.text('本周真实观察'), findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);

    outputs.complete({'this_week': 2, 'total_count': 5});
    trend.complete([
      {'date': '2026-11-06', 'task_completed': 8, 'habit_checked': 6},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('每日记录'), findsOneWidget);
    expect(find.text('输出记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P03 近30天先展示任务事实，习惯汇总随已确认趋势加载', (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final trend = Completer<List<Map<String, dynamic>>>();
    var trendReads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskMonthTab(
        tasksReviewLoader: () async => {
          'summary': {
            'completed_count': 5,
            'created_count': 7,
            'total_days': 30,
          },
          'distribution': <String, dynamic>{},
          'completed_tasks': <Map<String, dynamic>>[],
        },
        dailyTrendLoader: () {
          if (++trendReads == 1) return trend.future;
          throw StateError('趋势刷新失败');
        },
        periodTimelineLoader: () async => ReviewPeriodTimeline(
          observationCount: 12,
          items: [
            TodayTimelineItem(
              id: 'reflection:88',
              kind: 'observation',
              title: '近三十天真实观察',
              durationMinutes: 0,
              occurredAt: DateTime.now(),
            ),
          ],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(trend.isCompleted, isFalse);
    expect(find.text('近 30 天已载入记录'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('观察记录 12 条'), findsOneWidget);
    expect(find.text('近三十天真实观察'), findsOneWidget);
    expect(find.text('习惯记录'), findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);

    trend.complete([
      {'date': '2026-11-05', 'task_completed': 2, 'habit_checked': 4},
      {'date': '2026-11-06', 'task_completed': 3, 'habit_checked': 2},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
    expect(find.text('每日任务完成趋势'), findsOneWidget);

    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();
    expect(trendReads, 2);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('习惯记录（上次核对）'), findsOneWidget);
    expect(find.text('习惯汇总与下方趋势来自上次核对，非本次刷新结果。'),
        findsOneWidget);
    expect(find.text('趋势暂时无法加载，已载入的任务统计仍可查看。'), findsOneWidget);
    expect(find.text('每日任务完成趋势'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('今日数据请求挂起时，本周与近30天仍可独立打开', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final monday = LocalTimeBoundary.weekStart(now);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final rollingStart = DateTime(now.year, now.month, now.day - 29);
    final weekLabel =
        '${monday.month}月${monday.day}日—${sunday.month}月${sunday.day}日';
    final rollingLabel =
        '近 30 天 · ${rollingStart.month}月${rollingStart.day}日—${now.month}月${now.day}日';
    final pendingToday = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TodayReviewScreen(
        reflectionRepository: _ControlledReflections(),
        habitRepository: _NoHabits(),
        reviewLoader: () => pendingToday.future,
      )),
    ));
    await tester.pump();
    expect(find.byType(FxCircularProgress), findsOneWidget);

    await tester.tap(find.text('本周').first);
    await tester.pump();
    expect(find.byType(WeeklyReviewScreen), findsOneWidget);
    expect(find.text(weekLabel), findsOneWidget);

    await tester.tap(find.text('近 30 天').first);
    await tester.pump();
    expect(find.byType(TaskMonthTab), findsOneWidget);
    expect(find.text(rollingLabel), findsOneWidget);

    pendingToday.complete({
      'facts': <String, dynamic>{},
      'patterns': <String, dynamic>{},
      'questions': <Map<String, dynamic>>[],
    });
    await tester.pump();
    expect(find.byType(TaskMonthTab), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 回顾标题卡外展示，空问题保留且工具集中到底部',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(_ControlledReflections()));
    await tester.pumpAndSettle();

    expect(find.text('回看事实，留下自己的理解'), findsOneWidget);
    for (final title in ['今日概况', '发生过的事', '留给今天的一句话']) {
      expect(find.text(title), findsOneWidget);
      expect(find.descendant(
        of: find.byType(FxCard),
        matching: find.text(title),
      ), findsNothing);
    }
    expect(find.byKey(const ValueKey('review.mobile.questions.quiet')),
        findsOneWidget);
    expect(find.text('今天还没有留下记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('review.mobile.related')),
        findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('每周回顾'), findsOneWidget);
    expect(find.text('时间分配'), findsOneWidget);
    expect(find.byType(FxInput), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 有待回应问题时也不能隐藏自由记录草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(
      _ControlledReflections(),
      questions: [
        {'id': 'real-question-1', 'content': '今天有什么值得记住的事？'},
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('今天有什么值得记住的事？'), findsOneWidget);
    expect(find.text('留给今天的一句话'), findsOneWidget);
    expect(find.byType(FxInput), findsNWidgets(2));
    expect(find.text('保存记录'), findsOneWidget);
    expect(find.text('保存回应'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('今日回顾刷新失败保留事实、未保存草稿及重试入口', (tester) async {
    var loads = 0;
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TodayReviewScreen(
        reflectionRepository: _ControlledReflections(),
        habitRepository: _NoHabits(),
        reviewLoader: () async {
          loads++;
          if (loads > 1) throw StateError('暂时离线');
          return {
            'facts': <String, dynamic>{'task_completed': 3},
            'patterns': <String, dynamic>{},
            'questions': <Map<String, dynamic>>[],
          };
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('回顾数据加载失败'), findsNothing);

    await tester.enterText(find.byType(FxInput).first, '未提交的今日草稿');
    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('今日数据刷新未确认，以下仍为上次成功读取的记录。'),
        findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('回顾数据加载失败'), findsNothing);
    expect(find.text('未提交的今日草稿'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('首次今日回顾加载失败仍显示错误与重试', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TodayReviewScreen(
        reflectionRepository: _ControlledReflections(),
        habitRepository: _NoHabits(),
        reviewLoader: () async => throw StateError('离线'),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('回顾数据加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('辅助回应读取失败不抹掉上次确认的记录', (tester) async {
    final repository = _ControlledReflections();
    repository.recentEntries = [
      ReflectionEntry(
        id: 42,
        entryType: 'reflection',
        content: '已经保存的回顾记录',
        createdAt: DateTime.now(),
      ),
    ];
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(repository));
    await tester.pumpAndSettle();
    expect(find.text('已经保存的回顾记录'), findsOneWidget);

    repository.failRecent = true;
    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();

    expect(find.text('已经保存的回顾记录'), findsOneWidget);
    expect(find.textContaining('部分记录暂时无法加载：回应记录'),
        findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('回顾记录保存过程中连续点击只会创建一次', (tester) async {
    final repository = _ControlledReflections();
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FxInput).first, '今天尝试了一件新事');
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);
    expect(repository.calls, 1);
    repository.pending.complete(ReflectionEntry(
      id: 31,
      entryType: 'reflection',
      content: '今天尝试了一件新事',
      createdAt: DateTime(2026),
    ));
    await tester.pump();
    expect(repository.calls, 1);
    await disposeFxTestHost(tester);
  });

  testWidgets('无法确认是否保存时保留草稿，明确核对后才能重新提交', (tester) async {
    final repository = _ControlledReflections();
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FxInput).first, '想保留的草稿');
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    repository.pending.completeError(StateError('服务器响应未知'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('保存结果尚未确认'), findsOneWidget);
    expect(find.text('已核对，允许重新保存'), findsOneWidget);
    expect(find.text('想保留的草稿'), findsOneWidget);
    expect(repository.calls, 1);
    await disposeFxTestHost(tester);
  });
  testWidgets('P03 周/30天事件可逐页查看，失败保留当前页并可重试', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final weekly in [true, false]) {
      var attempts = 0;
      final initial = ReviewPeriodTimeline(
        observationCount: 42,
        hasMore: true,
        items: List.generate(40, (index) => TodayTimelineItem(
          id: 'reflection:${100 - index}',
          kind: 'observation',
          title: '首批观察$index',
          durationMinutes: 0,
          occurredAt: DateTime.now(),
        )),
      );
      Future<ReviewPeriodTimeline> loadPage({required int offset}) async {
        expect(offset, 40);
        if (++attempts == 1) throw StateError('temporary read failure');
        return ReviewPeriodTimeline(
          observationCount: 42,
          items: List.generate(2, (index) => TodayTimelineItem(
            id: 'reflection:${60 - index}',
            kind: 'observation',
            title: '下一页观察$index',
            durationMinutes: 0,
            occurredAt: DateTime.now().subtract(const Duration(hours: 1)),
          )),
        );
      }

      final view = weekly
          ? WeeklyReviewScreen(
              embedded: true,
              reviewLoader: () async => <String, dynamic>{
                'task_completed': 2,
                'habit_checked': 1,
                'focus_minutes': 0,
                'time_distribution': <Map<String, dynamic>>[],
              },
              outputStatsLoader: () async => <String, dynamic>{},
              dailyTrendLoader: () async => <Map<String, dynamic>>[],
              periodTimelineLoader: () async => initial,
              periodTimelinePageLoader: loadPage,
            )
          : TaskMonthTab(
              tasksReviewLoader: () async => <String, dynamic>{
                'summary': <String, dynamic>{
                  'completed_count': 2, 'created_count': 2,
                  'total_days': 30,
                },
                'distribution': <String, dynamic>{},
                'completed_tasks': <Map<String, dynamic>>[],
              },
              dailyTrendLoader: () async => <Map<String, dynamic>>[],
              periodTimelineLoader: () async => initial,
              periodTimelinePageLoader: loadPage,
            );
      await tester.pumpWidget(buildFxTestHost(home: Scaffold(body: view)));
      await tester.pumpAndSettle();
      expect(find.text('观察记录 42 条'), findsOneWidget);
      final open = find.widgetWithText(FxButton, '查看全部事件');
      tester.widget<FxButton>(open).onPressed?.call();
      await tester.pumpAndSettle();
      expect(find.text('第 1 页 · 40 条事件'), findsOneWidget);

      tester.widget<FxButton>(find.widgetWithText(FxButton, '下一页'))
          .onPressed?.call();
      await tester.pumpAndSettle();
      expect(find.textContaining('本页读取未完成'), findsOneWidget);
      expect(find.text('第 1 页 · 40 条事件'), findsOneWidget);
      tester.widget<FxButton>(find.widgetWithText(FxButton, '重试读取'))
          .onPressed?.call();
      await tester.pumpAndSettle();
      expect(find.text('第 2 页 · 2 条事件'), findsOneWidget);
      expect(find.text('下一页观察0'), findsOneWidget);
      expect(find.text('观察记录 42 条'), findsOneWidget);
      tester.widget<FxButton>(find.widgetWithText(FxButton, '上一页'))
          .onPressed?.call();
      await tester.pumpAndSettle();
      expect(find.text('第 1 页 · 40 条事件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    }
  });

  testWidgets('P03 旧版周回应可精确重读，不依赖 recent(100)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _PeriodReflections();
    repo.entries.add(ReflectionEntry(
      id: 11,
      entryType: 'reflection',
      content: '已保存的旧版周回应',
      context: const {
        'source': 'weekly_review',
        'week_start': '2026-11-02',
        'week_end': '2026-11-08',
      },
      createdAt: DateTime(2026, 11, 2),
    ));
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reflectionRepository: repo,
        reviewLoader: () async => {
          'week_start': '2026-11-02',
          'week_end': '2026-11-08',
          'task_completed': 1,
          'time_distribution': <Map<String, dynamic>>[],
        },
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
            observationCount: 0, items: []),
      )),
    ));
    await tester.pumpAndSettle();
    expect(repo.lastQuestionId, 'review-week:2026-11-02:2026-11-08');
    expect(find.text('已保存的旧版周回应'), findsOneWidget);
    expect(find.widgetWithText(FxButton, '保存回应'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P03 桌面30天回应保存/重读并保留父级草稿控制器', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _PeriodReflections();
    final draft = TextEditingController();
    final load = () async => <String, dynamic>{
      'summary': {'completed_count': 2, 'created_count': 2,
        'total_days': 30},
      'distribution': <String, dynamic>{},
      'completed_tasks': <Map<String, dynamic>>[],
    };
    Widget page(Key key) => buildFxTestHost(home: Scaffold(
      body: TaskMonthTab(
        key: key,
        reflectionRepository: repo,
        responseDraftController: draft,
        tasksReviewLoader: load,
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
            observationCount: 0, items: []),
      ),
    ));
    await tester.pumpWidget(page(const ValueKey('first')));
    await tester.pumpAndSettle();
    expect(find.text('近 30 天回应'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, '未提交的周期草稿');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page(const ValueKey('second')));
    await tester.pumpAndSettle();
    expect(draft.text, '未提交的周期草稿');
    tester.widget<FxButton>(find.widgetWithText(FxButton, '保存回应'))
        .onPressed?.call();
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(repo.lastQuestionId, startsWith('review-30d:'));
    expect(repo.entries.single.questionId, startsWith('review-30d:'));
    expect(find.text('未提交的周期草稿'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page(const ValueKey('third')));
    await tester.pumpAndSettle();
    expect(find.text('未提交的周期草稿'), findsOneWidget);
    expect(find.widgetWithText(FxButton, '保存回应'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
    draft.dispose();
  });

  testWidgets('P03 保存回执丢失先锁提交，核对失败仍锁，确认后不重复', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _PeriodReflections()..throwAfterCommit = true;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskMonthTab(
        reflectionRepository: repo,
        tasksReviewLoader: () async => {
          'summary': <String, dynamic>{'completed_count': 1,
            'created_count': 1, 'total_days': 30},
          'distribution': <String, dynamic>{},
          'completed_tasks': <Map<String, dynamic>>[],
        },
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
            observationCount: 0, items: []),
      )),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '已入库但回执丢失');
    tester.widget<FxButton>(find.widgetWithText(FxButton, '保存回应'))
        .onPressed?.call();
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(find.textContaining('保存结果尚未确认'), findsOneWidget);
    expect(find.widgetWithText(FxButton, '保存回应'), findsNothing);

    repo.failLookup = true;
    tester.widget<FxButton>(find.widgetWithText(FxButton, '核对回应'))
        .onPressed?.call();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FxButton, '保存回应'), findsNothing);
    expect(repo.createCalls, 1);

    repo.failLookup = false;
    tester.widget<FxButton>(find.widgetWithText(FxButton, '核对回应'))
        .onPressed?.call();
    await tester.pumpAndSettle();
    expect(find.text('已入库但回执丢失'), findsOneWidget);
    expect(find.widgetWithText(FxButton, '保存回应'), findsNothing);
    expect(repo.createCalls, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 回顾指标可筛选，轨迹可展开，草稿不丢失', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 1150);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    });
    final responses = _ControlledReflections()
      ..recentEntries = [
        ReflectionEntry(
          id: 991,
          entryType: 'observation',
          content: '读书前把手机放远，比较容易静下来。',
          createdAt: DateTime.now(),
        ),
      ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TodayReviewScreen(
        reflectionRepository: responses,
        habitRepository: _NoHabits(),
        reviewLoader: () async => {
          'facts': <String, dynamic>{
            'task_completed': 1,
            'today_completed_tasks': [
              {
                'id': 711,
                'title': '给朋友回一封邮件',
                'completed_at': DateTime.now().toIso8601String(),
              },
            ],
            'focus_minutes': 25,
            'focus_count': 1,
          },
          'patterns': <String, dynamic>{},
          'questions': <Map<String, dynamic>>[],
        },
      )),
    ));
    await tester.pumpAndSettle();

    Iterable<ReviewTimelineItem> rows() =>
        tester.widgetList<ReviewTimelineItem>(
            find.byType(ReviewTimelineItem));
    expect(rows().map((item) => item.kind),
        containsAll(['task_completed', 'observation', 'session_ended']));
    expect(rows().every((item) => item.compact), isTrue);

    await tester.enterText(find.byType(FxInput).first, '这是一条未保存草稿');
    await tester.tap(find.byKey(const ValueKey('review.metric.task_completed')));
    await tester.pumpAndSettle();
    expect(rows().length, 1);
    expect(rows().single.kind, 'task_completed');
    expect(find.text('这是一条未保存草稿'), findsOneWidget);

    await tester.tap(find.text('完成「给朋友回一封邮件」'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewTimelineItem), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('review.metric.task_completed')));
    await tester.pumpAndSettle();
    expect(rows().length, 3);
    expect(find.text('这是一条未保存草稿'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

}
