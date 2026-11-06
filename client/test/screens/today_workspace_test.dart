import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:slowlight/models/today_timeline_item.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/dashboard/dashboard_body.dart';

import '../support/fx_test_host.dart';

void main() {
  final now = DateTime.now();
  final items = [
    TodayTimelineItem(
      id: 'reflection:5', kind: 'observation',
      title: '今天值得留意的一件小事',
      durationMinutes: 0, occurredAt: now,
    ),
    TodayTimelineItem(
      id: 'event:2', kind: 'session_ended',
      title: '', durationMinutes: 25,
      occurredAt: now.subtract(const Duration(minutes: 20)),
    ),
  ];

  Widget host({
    required double width,
    Future<List<TodayTimelineItem>> Function()? timeline,
    VoidCallback? onReview,
    List<Task> tasks = const [],
    List<Habit> habits = const [],
    ValueChanged<Task>? onTaskToggle,
    ValueChanged<Habit>? onHabitToggle,
    VoidCallback? onStartFocus,
    double textScale = 1,
  }) => buildFxTestHost(
    home: Scaffold(body: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: DashboardBody(
        tasks: tasks,
        habits: habits,
        onTaskToggle: onTaskToggle,
        onHabitToggle: onHabitToggle,
        onStartFocus: onStartFocus,
        reviewLoader: () async => {
          'questions': [],
          'facts': {
            'task_completed': 1,
            'habit_checked': 1,
            'focus_minutes': 25,
          },
        },
        dimensionLoader: () async => {
          'dimensions': [
            {
              'key': 'body', 'name': '身体', 'color': '#3B82F6',
              'active_days': [DateTime.now().toIso8601String().substring(0, 10)],
            },
          ],
        },
        timelineLoader: timeline ?? () async => items,
        onViewReview: onReview,
      ),
    )),
  );

  testWidgets('Android 今日前三条优先显示未完成，完成数仍包含全部记录',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The repository can return completed tasks ahead of pending ones.
    // Only the preview is reordered; its total/count must remain unchanged.
    final tasks = [
      for (var id = 1; id <= 5; id++)
        Task(
          id: id,
          listId: 1,
          title: '任务 $id',
          priority: 'none',
          isCompleted: id <= 3,
          createdAt: now,
        ),
    ];
    await tester.pumpWidget(host(
      width: 390,
      tasks: tasks,
      onTaskToggle: (_) {},
    ));
    await tester.pumpAndSettle();

    final section = find.byKey(const ValueKey('today.section.tasks'));
    for (final id in [4, 5, 1]) {
      expect(
        find.descendant(
          of: section,
          matching: find.byKey(ValueKey('today-task-$id')),
        ),
        findsOneWidget,
      );
    }
    for (final id in [2, 3]) {
      expect(
        find.descendant(
          of: section,
          matching: find.byKey(ValueKey('today-task-$id')),
        ),
        findsNothing,
      );
    }
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('today-task-4'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('today-task-5'))).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('today-task-5'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('today-task-1'))).dy),
    );
    expect(find.text('3/5 完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('${width.toInt()} 今日轨迹与四维足迹共存，不阻断任务习惯', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(width: width));
      await tester.pumpAndSettle();
      expect(find.text('今日任务'), findsOneWidget);
      expect(find.text('习惯'), findsOneWidget);
      expect(find.text('今天值得留意的一件小事'), findsOneWidget);
      expect(find.text('专注 25 分钟'), findsOneWidget);
      if (width < 600) {
        // Mobile Today is action-first, while review owns the statistics.
        expect(find.text('今日事实'), findsNothing);
        expect(find.text('最近 7 天 · 四维足迹'), findsNothing);
        expect(find.byKey(const ValueKey('today.section.tasks')), findsOneWidget);
        expect(find.byKey(const ValueKey('today.section.habits')), findsOneWidget);
        expect(find.byKey(const ValueKey('today.section.timeline')), findsOneWidget);
      } else {
        expect(find.text('今日事实'), findsOneWidget);
        expect(find.text('最近 7 天 · 四维足迹'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('移动端严格按照原型呈现任务→习惯→轨迹，标题不再放进卡片',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      width: 390,
      tasks: [
        Task(
          id: 11,
          listId: 1,
          title: '整理今天的计划',
          priority: 'none',
          isCompleted: false,
          createdAt: now,
        ),
      ],
      onTaskToggle: (_) {},
      onStartFocus: () {},
    ));
    await tester.pumpAndSettle();

    final tasks = find.byKey(const ValueKey('today.section.tasks'));
    final habits = find.byKey(const ValueKey('today.section.habits'));
    final timeline = find.byKey(const ValueKey('today.section.timeline'));
    expect(tester.getTopLeft(tasks).dy, lessThan(tester.getTopLeft(habits).dy));
    expect(tester.getTopLeft(habits).dy, lessThan(tester.getTopLeft(timeline).dy));
    expect(find.text('开始专注'), findsOneWidget);
    expect(find.text('记录行动，也记录生活。'), findsNothing);
    expect(find.byKey(const ValueKey('today.mobile.date')), findsOneWidget);

    final title = find.text('今日任务');
    final panel = find.descendant(of: tasks, matching: find.byType(FxCard)).first;
    final row = find.byKey(const ValueKey('today-task-11'));
    // The heading is above the card, not hidden below a large card inset.
    expect(tester.getBottomLeft(title).dy,
        lessThan(tester.getTopLeft(panel).dy));
    expect(tester.getTopLeft(panel).dy - tester.getBottomLeft(title).dy,
        lessThan(20));
    expect(tester.getTopLeft(row).dy - tester.getTopLeft(panel).dy,
        lessThan(18));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 今日习惯图标动作保留 44dp 热区及三种语义',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tapped = <int>[];
    final all = [
      Habit(
        id: 31,
        userId: 1,
        name: '今天阅读',
        icon: '📚',
        color: '#1890ff',
        frequency: 'daily',
        checkedToday: false,
        createdAt: now,
      ),
      Habit(
        id: 32,
        userId: 1,
        name: '今天散步',
        icon: '🚶',
        color: '#52c41a',
        frequency: 'daily',
        checkedToday: true,
        createdAt: now,
      ),
      Habit(
        id: 33,
        userId: 1,
        name: '喝水',
        icon: '💧',
        color: '#1890ff',
        frequency: 'daily',
        checkedToday: true,
        allowMultiplePerDay: true,
        createdAt: now,
      ),
    ];
    await tester.pumpWidget(host(
      width: 360,
      habits: all,
      onHabitToggle: (habit) => tapped.add(habit.id),
    ));
    await tester.pumpAndSettle();

    for (final (id, icon, hint) in [
      (31, LucideIcons.circle, '记录「今天阅读」今天的打卡'),
      (32, LucideIcons.circleCheck, '已记录「今天散步」，点击可取消今天的打卡'),
      (33, LucideIcons.circlePlus, '为「喝水」新增一次记录'),
    ]) {
      final control = find.byKey(ValueKey('today.habit.record.$id'));
      expect(control, findsOneWidget);
      final button = tester.widget<FxIconButton>(control);
      expect(button.icon, icon);
      expect(button.tooltip, hint);
      expect(tester.getSize(control).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
      await tester.ensureVisible(control);
      await tester.tap(control);
      await tester.pump();
    }
    expect(tapped, [31, 32, 33]);
    // These are icon-only actions; status words must not form three buttons.
    expect(find.text('新增'), findsNothing);
    expect(find.text('已记录'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 今日习惯按钮显式可见，标题与打卡分离',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var recordCount = 0;
    await tester.pumpWidget(host(
      width: 390,
      habits: [
        Habit(
          id: 24,
          userId: 1,
          name: '每日阅读',
          icon: '📚',
          color: '#1890ff',
          frequency: 'daily',
          checkedToday: false,
          createdAt: now,
        ),
      ],
      onHabitToggle: (_) => recordCount++,
    ));
    await tester.pumpAndSettle();
    final section = find.byKey(const ValueKey('today.section.habits'));
    final record = find.byKey(const ValueKey('today.habit.record.24'));
    expect(section, findsOneWidget);
    expect(record, findsOneWidget);
    expect(find.text('每天'), findsOneWidget);
    expect(tester.getSize(record).height, greaterThanOrEqualTo(44));
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.pump();
    expect(recordCount, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('Android 360dp 图标操作适应文字放大 $scale',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        width: 360,
        textScale: scale,
        habits: [
          Habit(
            id: 34,
            userId: 1,
            name: '一个标题特别长、仍应保留右侧打卡入口的习惯',
            icon: '📚',
            color: '#52c41a',
            frequency: 'daily',
            createdAt: now,
          ),
        ],
        onHabitToggle: (_) {},
      ));
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('today.habit.34'));
      final action = find.byKey(const ValueKey('today.habit.record.34'));
      expect(row, findsOneWidget);
      expect(action, findsOneWidget);
      final rowRect = tester.getRect(row);
      final actionRect = tester.getRect(action);
      expect(actionRect.left, greaterThan(rowRect.left));
      expect(actionRect.right, lessThanOrEqualTo(rowRect.right + 1));
      expect(actionRect.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('Android 今日卡片收紧内边距，任务热区保持不小于 44dp',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      width: 390,
      tasks: [
        Task(
          id: 11,
          listId: 1,
          title: '整理今天的计划',
          priority: 'none',
          isCompleted: false,
          createdAt: now,
        ),
      ],
      habits: [
        Habit(
          id: 22,
          userId: 1,
          name: '每日阅读',
          icon: '📚',
          color: '#1890ff',
          frequency: 'daily',
          checkedToday: false,
          createdAt: now,
        ),
      ],
      onTaskToggle: (_) {},
    ));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<FxCard>(find.byType(FxCard)).toList();
    expect(cards, isNotEmpty);
    for (final card in cards) {
      final padding = card.padding!.resolve(TextDirection.ltr);
      expect(padding.top, lessThanOrEqualTo(12));
      expect(padding.bottom, lessThanOrEqualTo(12));
    }
    final task = find.byKey(const ValueKey('today-task-11'));
    expect(task, findsOneWidget);
    expect(tester.getSize(task).height, inInclusiveRange(44, 56));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('时间轨迹请求卡住时，今日任务仍可使用', (tester) async {
    final pending = Completer<List<TodayTimelineItem>>();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(width: 1200, timeline: () => pending.future));
    await tester.pump();
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.text('正在读取今天的轨迹…'), findsOneWidget);
    pending.complete(items);
    await tester.pumpAndSettle();
    expect(find.text('专注 25 分钟'), findsOneWidget);
    await disposeFxTestHost(tester);
  });
}
