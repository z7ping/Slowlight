import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/screens/today_review_screen.dart';
import 'package:slowlight/screens/weekly_review_screen.dart';
import 'package:slowlight/widgets/review/task_30day_tab.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/utils/local_time_boundary.dart';

import '../support/fx_test_host.dart';

class _NoHabits extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => const [];
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

void main() {
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
      )),
    ));
    await tester.pumpAndSettle();
    expect(outputs.isCompleted, isFalse);
    expect(trend.isCompleted, isFalse);
    expect(find.text('本周记录'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
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
      )),
    ));
    await tester.pumpAndSettle();
    expect(trend.isCompleted, isFalse);
    expect(find.text('近 30 天已载入记录'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
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
}
