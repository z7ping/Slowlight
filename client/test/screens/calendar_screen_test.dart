import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:slowlight/models/calendar_record.dart';
import 'package:slowlight/screens/calendar_screen.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:flutter/foundation.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Android 日历选中日期传入统一创建 Sheet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final selectedDate = DateTime(2026, 8, 21);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: CalendarScreen(
          initialMonth: DateTime(2026, 8),
          initialSelectedDate: selectedDate,
          monthLoader: (requested) async => CalendarMonthData(
            month: requested,
            records: const [],
          ),
          createListsOverride: [
            TodoList(
              id: 1, name: '收集箱', isInbox: true,
              color: '#8db5a0', createdAt: DateTime(2026),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final create = find.byKey(const ValueKey('calendar-add-task'));
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    expect(tester.widget<TaskDetailSheet>(detail).isCreating, isTrue);
    expect(tester.widget<TaskDetailSheet>(detail).task.dueDate, selectedDate);
    expect(find.descendant(of: detail, matching: find.text('新建任务')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  final month = DateTime(2026, 8, 1);
  final selected = DateTime(2026, 8, 21);
  final records = [
    CalendarRecord(
      id: 'task-plan',
      type: CalendarRecordType.task,
      kind: CalendarRecordKind.plan,
      date: selected,
      title: '提交季度报告',
      timeLabel: '14:00',
      priority: 'urgent_important',
    ),
    CalendarRecord(
      id: 'habit-read',
      type: CalendarRecordType.habit,
      kind: CalendarRecordKind.actual,
      date: selected,
      title: '📚 阅读',
      durationMin: 30,
      completed: true,
    ),
    CalendarRecord(
      id: 'focus-day',
      type: CalendarRecordType.focus,
      kind: CalendarRecordKind.actual,
      date: selected,
      title: '深度专注',
      durationMin: 50,
      completed: true,
    ),
    CalendarRecord(
      id: 'reflection-day',
      type: CalendarRecordType.reflection,
      kind: CalendarRecordKind.actual,
      date: selected,
      title: '下午切换任务较频繁',
      description: '连续工作块偏短。',
      completed: true,
    ),
    CalendarRecord(
      id: 'task-next-day',
      type: CalendarRecordType.task,
      kind: CalendarRecordKind.plan,
      date: DateTime(2026, 8, 22),
      title: '整理会议记录',
    ),
  ];

  Future<CalendarMonthData> loader(DateTime requested) async =>
      CalendarMonthData(month: requested, records: records);

  Widget buildApp({
    Future<void> Function(BuildContext, DateTime)? createTask,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: CalendarScreen(
          monthLoader: loader,
          initialMonth: month,
          initialSelectedDate: selected,
          createTaskOverride: createTask,
        ),
      ),
    );
  }

  Future<void> pumpCalendar(
    WidgetTester tester, {
    double width = 1200,
    double height = 1000,
    TextScaler textScaler = TextScaler.noScaling,
    Future<void> Function(BuildContext, DateTime)? createTask,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildApp(createTask: createTask, textScaler: textScaler),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('P08 月度部分来源失败不伪装成当日完整记录', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: month,
        initialSelectedDate: selected,
        monthLoader: (requested) async => CalendarMonthData(
          month: requested,
          records: [records.first],
          unavailableTypes: const {CalendarRecordType.habit},
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('已载入 1 条记录（部分待核对）'), findsOneWidget);
    expect(find.textContaining('习惯记录暂时不可用'), findsOneWidget);
    expect(find.textContaining('完整记录'), findsNothing);
    await disposeFxTestHost(tester);
  });

  testWidgets('P08 部分来源重试保留原月格直到新结果确认', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final retry = Completer<CalendarMonthData>();
    var calls = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: month,
        initialSelectedDate: selected,
        monthLoader: (requested) {
          calls++;
          if (calls == 1) {
            return Future.value(CalendarMonthData(
              month: requested,
              records: [records.first],
              unavailableTypes: const {CalendarRecordType.reflection},
            ));
          }
          return retry.future;
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-record-task-plan')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-partial-retry')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-partial-retry')));
    await tester.pump();
    expect(find.byKey(const ValueKey('calendar-record-task-plan')),
        findsOneWidget);
    expect(find.textContaining('已载入 1 条记录（部分待核对）'),
        findsOneWidget);
    retry.complete(CalendarMonthData(month: month, records: records));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-partial-retry')),
        findsNothing);
    expect(find.text('计划与实际 · 共 4 条完整记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('还原高密度月历与当日完整记录', (tester) async {
    await pumpCalendar(tester);

    expect(find.text('2026 年 8 月'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('calendar-day-2026-07-27')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('calendar-day-2026-09-06')), findsOneWidget);
    expect(find.text('当日任务'), findsOneWidget);
    expect(find.text('当日足迹'), findsOneWidget);
    expect(find.text('计划与实际 · 共 4 条完整记录'), findsOneWidget);
    expect(find.text('任务 0/1'), findsOneWidget);
    expect(find.text('习惯 1'), findsOneWidget);
    expect(find.text('专注 50min'), findsOneWidget);
    expect(find.text('观察 1'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('单行年月标题可切月，浮层和筛选各保留一处入口', (tester) async {
    await pumpCalendar(tester);
    expect(find.byKey(const ValueKey('calendar-month-label')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-filter')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-month-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.chevronRight));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-day-2026-09-21')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('calendar-month-label'))).data,
        '2026 年 9 月');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('选中日期只显示浅色底与描边，不用阴影涂满日程', (tester) async {
    await pumpCalendar(tester);

    final selectedDay = tester.widget<Container>(
      find.byKey(const ValueKey('calendar-day-2026-08-21')),
    );
    final selectedDecoration = selectedDay.decoration! as BoxDecoration;
    final selectedBorder = selectedDecoration.border! as Border;

    expect(selectedDecoration.boxShadow, isNull);
    expect(selectedBorder.top.style, BorderStyle.solid);
    expect(selectedBorder.left.style, BorderStyle.solid);
    expect(selectedBorder.top.width, greaterThan(1));

    final otherDay = tester.widget<Container>(
      find.byKey(const ValueKey('calendar-day-2026-08-22')),
    );
    final otherBorder = (otherDay.decoration! as BoxDecoration).border! as Border;
    expect(otherBorder.top, BorderSide.none);
    expect(otherBorder.left, BorderSide.none);
    expect(otherBorder.right.style, BorderStyle.solid);
    expect(otherBorder.bottom.style, BorderStyle.solid);
    expect(selectedBorder.top.color, isNot(otherBorder.right.color));

    // 修复选中态时，日期选择和日程预览仍然正常展示。
    expect(find.byKey(const ValueKey('calendar-grid-record-habit-read')),
        findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('切换日期后下方数据联动', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-08-22')));
    await tester.pump();

    expect(find.text('8 月 22 日 · 周六'), findsOneWidget);
    expect(find.text('计划与实际 · 共 1 条完整记录'), findsOneWidget);
    expect(find.text('整理会议记录'), findsWidgets);
    await disposeFxTestHost(tester);
  });

  testWidgets('计划筛选只影响月格，不隐藏下方完整数据', (tester) async {
    await pumpCalendar(tester);

    expect(find.byKey(const ValueKey('calendar-grid-record-habit-read')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-grid-record-habit-read')),
        findsNothing);
    expect(find.byKey(const ValueKey('calendar-record-habit-read')),
        findsOneWidget);
    expect(find.text('计划与实际 · 共 4 条完整记录'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('新建任务携带选中日期', (tester) async {
    DateTime? createdFor;
    await pumpCalendar(
      tester,
      createTask: (_, date) async => createdFor = date,
    );

    final addTask = find.byKey(const ValueKey('calendar-add-task'));
    await tester.scrollUntilVisible(
      addTask,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(addTask);
    await tester.pumpAndSettle();
    await tester.tap(addTask);
    await tester.pumpAndSettle();

    expect(createdFor, DateTime(2026, 8, 21));
    await disposeFxTestHost(tester);
  });

  testWidgets('P08 点击月格记录同时切换当日明细选中日期', (tester) async {
    await pumpCalendar(tester);
    final nextDay = find.byKey(
        const ValueKey('calendar-grid-record-task-next-day'));
    await tester.ensureVisible(nextDay);
    await tester.tap(nextDay);
    await tester.pumpAndSettle();
    expect(find.text('8 月 22 日 · 周六'), findsOneWidget);
    expect(find.text('计划与实际 · 共 1 条完整记录'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('点击足迹记录打开详情', (tester) async {
    await pumpCalendar(tester);

    await tester.drag(
      find.byKey(const ValueKey('calendar-scroll-view')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('calendar-record-reflection-day')));
    await tester.pumpAndSettle();

    expect(find.text('连续工作块偏短。'), findsOneWidget);
    expect(find.text('观察 · 实际'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('01 Android 窄屏可切换月格筛选，日明细仍展示完整事实', (tester) async {
    await pumpCalendar(tester, width: 360);

    expect(find.byKey(const ValueKey('calendar-filter')), findsOneWidget);
    expect(find.text('月格筛选'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计划').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-grid-record-habit-read')),
        findsNothing);
    expect(find.byKey(const ValueKey('calendar-record-habit-read')),
        findsOneWidget);
    expect(find.text('计划与实际 · 共 4 条完整记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('窄屏仍可浏览月格和当日列表', (tester) async {
    await pumpCalendar(tester, width: 420);

    expect(find.byKey(const ValueKey('calendar-scroll-view')), findsOneWidget);
    expect(find.text('当日任务'), findsOneWidget);
    expect(find.text('当日足迹'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('360dp 与 200% 字体缩放下日历主路径无溢出', (tester) async {
    await pumpCalendar(
      tester,
      width: 360,
      height: 1000,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('2026 年 8 月'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-scroll-view')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('calendar-selected-title')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('当日任务'), findsOneWidget);
    expect(find.text('当日足迹'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
