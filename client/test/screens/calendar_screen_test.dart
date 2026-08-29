import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/calendar_record.dart';
import 'package:slowlight/screens/calendar_screen.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
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
  }) {
    return ShadTheme(
      data: ThemeManager.shadLight,
      child: MaterialApp(
        theme: ThemeManager.lightTheme,
        home: Scaffold(
          body: CalendarScreen(
            monthLoader: loader,
            initialMonth: month,
            initialSelectedDate: selected,
            createTaskOverride: createTask,
          ),
        ),
      ),
    );
  }

  Future<void> pumpCalendar(
    WidgetTester tester, {
    double width = 1200,
    Future<void> Function(BuildContext, DateTime)? createTask,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp(createTask: createTask));
    await tester.pumpAndSettle();
  }

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
  });

  testWidgets('切换日期后下方数据联动', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-08-22')));
    await tester.pump();

    expect(find.text('8 月 22 日 · 周六'), findsOneWidget);
    expect(find.text('计划与实际 · 共 1 条完整记录'), findsOneWidget);
    expect(find.text('整理会议记录'), findsWidgets);
  });

  testWidgets('计划筛选只影响月格，不隐藏下方完整数据', (tester) async {
    await pumpCalendar(tester);

    expect(find.byKey(const ValueKey('calendar-grid-record-habit-read')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-filter-plan')));
    await tester.pump();

    expect(find.byKey(const ValueKey('calendar-grid-record-habit-read')),
        findsNothing);
    expect(find.byKey(const ValueKey('calendar-record-habit-read')),
        findsOneWidget);
    expect(find.text('计划与实际 · 共 4 条完整记录'), findsOneWidget);
  });

  testWidgets('新建任务携带选中日期', (tester) async {
    DateTime? createdFor;
    await pumpCalendar(
      tester,
      createTask: (_, date) async => createdFor = date,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('calendar-add-task')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('calendar-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-add-task')));
    await tester.pumpAndSettle();

    expect(createdFor, DateTime(2026, 8, 21));
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
  });

  testWidgets('窄屏仍可浏览月格和当日列表', (tester) async {
    await pumpCalendar(tester, width: 420);

    expect(find.byKey(const ValueKey('calendar-scroll-view')), findsOneWidget);
    expect(find.text('当日任务'), findsOneWidget);
    expect(find.text('当日足迹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
