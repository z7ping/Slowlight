import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/models/calendar_record.dart';
import 'package:slowlight/screens/calendar_screen.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:flutter/foundation.dart';

import '../support/fx_test_host.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('月视图下拉刷新仅使用 FxRefresh 指示器，保留已确认事项', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final date = DateTime(2026, 8, 21);
    final refreshed = Completer<CalendarMonthData>();
    var reads = 0;
    CalendarMonthData monthData(String title) => CalendarMonthData(
      month: DateTime(2026, 8),
      records: [
        CalendarRecord(
          id: 'test-plan',
          type: CalendarRecordType.task,
          kind: CalendarRecordKind.plan,
          date: date,
          title: title,
          timeLabel: '14:00',
        ),
      ],
    );
    Future<CalendarMonthData> load(DateTime month) {
      reads++;
      return reads == 1
          ? Future.value(monthData('原任务'))
          : refreshed.future;
    }
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: date,
        monthLoader: load,
      )),
    ));
    await tester.pumpAndSettle();

    final oldRecord = find.byKey(
      const ValueKey('calendar-grid-record-test-plan'),
    );
    expect(oldRecord, findsOneWidget);
    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    final pending = refresh.onRefresh();
    await tester.pump();
    expect(reads, 2);
    expect(oldRecord, findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);

    refreshed.complete(monthData('新任务'));
    await pending;
    await tester.pumpAndSettle();
    expect(find.textContaining('新任务'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('跨月七日视图下拉保留已有日期列，邻月仍重新读取', (tester) async {
    SharedPreferences.setMockInitialValues({'calendar.view_mode': 'week'});
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final augustRefresh = Completer<CalendarMonthData>();
    final septemberRefresh = Completer<CalendarMonthData>();
    final reads = <int, int>{};
    CalendarMonthData data(DateTime month, String title) =>
        CalendarMonthData(month: month, records: [
          if (month.month == 9)
            CalendarRecord(
              id: 'neighbor-task',
              type: CalendarRecordType.task,
              kind: CalendarRecordKind.plan,
              date: DateTime(2026, 9, 1),
              title: title,
              timeLabel: '10:00',
            ),
        ]);
    Future<CalendarMonthData> load(DateTime month) {
      final count = (reads[month.month] ?? 0) + 1;
      reads[month.month] = count;
      if (count == 1) {
        return Future.value(data(month, '跨月旧任务'));
      }
      return month.month == 8
          ? augustRefresh.future
          : septemberRefresh.future;
    }
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: DateTime(2026, 8, 31),
        monthLoader: load,
        headerInAppBar: true,
      )),
    ));
    await tester.pumpAndSettle();
    final oldRecord = find.byKey(
      const ValueKey('calendar-timeline-record-neighbor-task'),
    );
    expect(oldRecord, findsOneWidget);
    expect(reads[9], 1);

    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    final pending = refresh.onRefresh();
    await tester.pump();
    expect(oldRecord, findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);

    augustRefresh.complete(data(DateTime(2026, 8), ''));
    await tester.pump();
    expect(reads[9], 2);
    expect(oldRecord, findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);

    septemberRefresh.complete(data(DateTime(2026, 9), '跨月新任务'));
    await pending;
    await tester.pumpAndSettle();
    expect(oldRecord, findsOneWidget);
    expect(find.textContaining('跨月新任务'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('首次无记录的日历仍显示内容加载指示器', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final first = Completer<CalendarMonthData>();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: DateTime(2026, 8),
        monthLoader: (_) => first.future,
      )),
    ));
    await tester.pump();
    expect(find.byType(FxCircularProgress), findsOneWidget);
    first.complete(CalendarMonthData(
      month: DateTime(2026, 8),
      records: const [],
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FxCircularProgress), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('月历 Tab 重入静默刷新且保留选中月份与日期', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var reads = 0;
    final requested = <DateTime>[];
    Future<CalendarMonthData> load(DateTime month) async {
      reads++;
      requested.add(month);
      return CalendarMonthData(month: month, records: const []);
    }
    Widget app(int tick) => buildFxTestHost(
      home: Scaffold(
        body: CalendarScreen(
          initialMonth: DateTime(2026, 8),
          initialSelectedDate: DateTime(2026, 8, 21),
          monthLoader: load,
          refreshTick: tick,
        ),
      ),
    );

    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(requested.every((value) => value.year == 2026 && value.month == 8),
        isTrue);
    expect(find.textContaining('8 月 21 日'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


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
    expect(find.byKey(const ValueKey('calendar-view-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-filter')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-month-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.chevronRight).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-day-2026-09-21')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('calendar-month-label'))).data,
        '2026 年 9 月');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  Future<void> selectCalendarView(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('calendar-view-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(FxMenuItem<CalendarViewMode>),
      matching: find.text(name),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Android 月历格始终展示任务名称，切到三日再回月历不退化成圆点',
      (tester) async {
    await pumpCalendar(tester, width: 360);
    final preview = find.byKey(
      const ValueKey('calendar-grid-record-task-plan'),
    );
    expect(preview, findsOneWidget);
    expect(
      find.descendant(
        of: preview,
        matching: find.textContaining('提交季度报告'),
      ),
      findsOneWidget,
    );
    await selectCalendarView(tester, '三日');
    expect(preview, findsNothing);
    await selectCalendarView(tester, '月');
    expect(preview, findsOneWidget);
    expect(
      find.descendant(
        of: preview,
        matching: find.textContaining('提交季度报告'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('窄屏月历同日多条实际记录时仍优先预览任务名称',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final day = DateTime(2026, 8, 21);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: CalendarScreen(
          initialMonth: DateTime(2026, 8),
          initialSelectedDate: day,
          monthLoader: (requested) async => CalendarMonthData(
            month: requested,
            records: [
              CalendarRecord(
                id: 'habit-a',
                type: CalendarRecordType.habit,
                kind: CalendarRecordKind.actual,
                date: day,
                title: '晨读',
              ),
              CalendarRecord(
                id: 'habit-b',
                type: CalendarRecordType.habit,
                kind: CalendarRecordKind.actual,
                date: day,
                title: '运动',
              ),
              CalendarRecord(
                id: 'actual-task',
                type: CalendarRecordType.task,
                kind: CalendarRecordKind.actual,
                date: day,
                title: '补齐单测',
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final taskPreview = find.byKey(
      const ValueKey('calendar-grid-record-actual-task'),
    );
    expect(taskPreview, findsOneWidget);
    expect(
      find.descendant(
        of: taskPreview,
        matching: find.textContaining('补齐单测'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar-grid-record-habit-b')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('日历菜单仅展示月、日、三日、七日四个视图', (tester) async {
    await pumpCalendar(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-view-toggle')));
    await tester.pumpAndSettle();
    final menuItems = find.byType(FxMenuItem<CalendarViewMode>);
    expect(menuItems, findsNWidgets(4));
    for (final text in ['月', '日', '三日', '七日']) {
      expect(
        find.descendant(of: menuItems, matching: find.text(text)),
        findsOneWidget,
      );
    }
    await tester.tap(find.descendant(
      of: menuItems,
      matching: find.text('日'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-date-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-selected-timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-timeline-record-task-plan')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-2026-08-21')), findsNothing);
    expect(find.byKey(const ValueKey('calendar-period-add-task')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-period-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-timeline-record-task-next-day')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('七日视图 360dp 一屏显示七个日期并可滑动换周', (tester) async {
    await pumpCalendar(tester, width: 360);
    await selectCalendarView(tester, '七日');
    expect(find.byKey(const ValueKey('calendar-date-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-selected-timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-period-day-2026-8-17')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-period-day-2026-8-23')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-period-add-task')), findsOneWidget);
    final strip = find.byKey(const ValueKey('calendar-date-strip'));
    expect(find.descendant(of: strip, matching: find.byType(SingleChildScrollView)), findsNothing);
    await tester.drag(strip, const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('三日时间轴使用三列，同一日期栏与小时列严格对齐', (tester) async {
    await pumpCalendar(tester, width: 360);
    await selectCalendarView(tester, '三日');
    final day = find.byKey(const ValueKey('calendar-period-day-2026-8-21'));
    final hour = find.byKey(const ValueKey('calendar-hour-slot-2026-8-21'));
    expect(day, findsOneWidget);
    expect(hour, findsOneWidget);
    expect((tester.getSize(day).width - tester.getSize(hour).width).abs(),
        lessThan(1));
    expect(find.byKey(const ValueKey('calendar-timeline-record-task-plan')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-untimed-toggle')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('七日 360dp 七列与小时轴等宽，只有日期圆点选中', (tester) async {
    await pumpCalendar(tester, width: 360);
    await selectCalendarView(tester, '七日');
    final first = find.byKey(const ValueKey('calendar-period-day-2026-8-17'));
    final slot = find.byKey(const ValueKey('calendar-hour-slot-2026-8-17'));
    expect(first, findsOneWidget);
    expect(slot, findsOneWidget);
    expect((tester.getSize(first).width - tester.getSize(slot).width).abs(),
        lessThan(1));
    expect(find.byKey(const ValueKey('calendar-period-day-2026-8-23')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('没有原生时刻的专注和习惯保留在折叠记录，不伪造时间块',
      (tester) async {
    await pumpCalendar(tester);
    await selectCalendarView(tester, '日');
    expect(find.byKey(const ValueKey('calendar-timeline-record-task-plan')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-timeline-record-focus-day')),
        findsNothing);
    final toggle = find.byKey(const ValueKey('calendar-untimed-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-untimed-record-focus-day')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 点击时间轴空白位置使用统一编辑器预填日期时间',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(home: Scaffold(
      body: CalendarScreen(
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: DateTime(2026, 8, 21),
        monthLoader: (requested) async =>
            CalendarMonthData(month: requested, records: const []),
        createListsOverride: [
          TodoList(
            id: 1, name: '收集箱', isInbox: true,
            color: '#8db5a0', createdAt: DateTime(2026),
          ),
        ],
      ),
    )));
    await tester.pumpAndSettle();
    await selectCalendarView(tester, '日');
    final slot = find.byKey(const ValueKey('calendar-hour-slot-2026-8-21'));
    expect(slot, findsOneWidget);
    final start = tester.getTopLeft(slot);
    await tester.tapAt(Offset(start.dx + 8, start.dy + 12));
    await tester.pumpAndSettle();
    final editor = find.byType(TaskDetailSheet);
    expect(editor, findsOneWidget);
    final task = tester.widget<TaskDetailSheet>(editor).task;
    expect(task.dueDate, DateTime(2026, 8, 21));
    expect(task.dueTime, '08:00');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 360dp 顶部年月与周期、视图、筛选不溢出', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = CalendarHeaderController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(buildFxTestHost(home: Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 8,
        title: CalendarMonthTitle(controller: controller),
        leading: const Icon(LucideIcons.menu),
        actions: [CalendarHeaderActions(controller: controller)],
      ),
      body: CalendarScreen(
        headerController: controller,
        headerInAppBar: true,
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: DateTime(2026, 8, 21),
        monthLoader: loader,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-month-label')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-period-prev')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-period-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-view-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-filter')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 时间栏滚动后仍固定，日期与时间列对齐', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({'calendar.view_mode': 'threeDays'});
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(home: Scaffold(
      body: CalendarScreen(
        headerInAppBar: true,
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: DateTime(2026, 8, 21),
        monthLoader: (requested) async =>
            CalendarMonthData(month: requested, records: records),
      ),
    )));
    await tester.pumpAndSettle();
    final strip = find.byKey(const ValueKey('calendar-date-strip'));
    expect(strip, findsOneWidget);
    final before = tester.getTopLeft(strip).dy;
    await tester.drag(find.byKey(const ValueKey('calendar-scroll-view')),
        const Offset(0, -400));
    await tester.pumpAndSettle();
    expect((tester.getTopLeft(strip).dy - before).abs(), lessThan(1));
    final date = find.byKey(const ValueKey('calendar-period-day-2026-8-21'));
    final slot = find.byKey(const ValueKey('calendar-hour-slot-2026-8-21'));
    expect((tester.getSize(date).width - tester.getSize(slot).width).abs(),
        lessThan(1));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 月视图使用紧凑当日明细而非大统计卡片', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(home: Scaffold(
      body: CalendarScreen(
        headerInAppBar: true,
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: DateTime(2026, 8, 21),
        monthLoader: loader,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-selected-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-record-task-plan')), findsOneWidget);
    expect(find.text('当日足迹'), findsNothing);
    expect(find.text('当日任务'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('月格实际需要的 5 周不补虚构第 6 周', (tester) async {
    await tester.pumpWidget(buildFxTestHost(home: Scaffold(
      body: CalendarScreen(
        initialMonth: DateTime(2026, 2),
        initialSelectedDate: DateTime(2026, 2, 12),
        monthLoader: (requested) async =>
            CalendarMonthData(month: requested, records: const []),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-day-2026-03-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-2026-03-08')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('凌晨真实时刻和未知时刻独立保留，不误标未定', (tester) async {
    await tester.pumpWidget(buildFxTestHost(home: Scaffold(
      body: CalendarScreen(
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: DateTime(2026, 8, 21),
        monthLoader: (requested) async =>
            CalendarMonthData(month: requested, records: [
              CalendarRecord(
                id: 'early-native', type: CalendarRecordType.task,
                kind: CalendarRecordKind.plan,
                date: DateTime(2026, 8, 21), title: '晨间任务',
                timeLabel: '06:30',
              ),
              CalendarRecord(
                id: 'unknown-native', type: CalendarRecordType.habit,
                kind: CalendarRecordKind.actual,
                date: DateTime(2026, 8, 21), title: '习惯记录',
                timeLabel: '上午',
              ),
            ]),
      ),
    )));
    await tester.pumpAndSettle();
    await selectCalendarView(tester, '日');
    final known = find.byKey(const ValueKey('calendar-other-time-toggle'));
    final unknown = find.byKey(const ValueKey('calendar-untimed-toggle'));
    expect(known, findsOneWidget);
    expect(unknown, findsOneWidget);
    await tester.ensureVisible(known);
    await tester.tap(known);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-untimed-record-early-native')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('三日跨月加载相邻月份记录，不以无记录代替未加载', (tester) async {
    final requestedMonths = <int>[];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: CalendarScreen(
          initialMonth: DateTime(2026, 8),
          initialSelectedDate: DateTime(2026, 8, 31),
          monthLoader: (requested) async {
            requestedMonths.add(requested.month);
            return CalendarMonthData(month: requested, records: [
              if (requested.month == 9)
                CalendarRecord(
                  id: 'sep-plan',
                  type: CalendarRecordType.task,
                  kind: CalendarRecordKind.plan,
                  date: DateTime(2026, 9, 1),
                  timeLabel: '09:00',
                  title: '跨月计划',
                ),
            ]);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await selectCalendarView(tester, '三日');
    expect(requestedMonths, containsAll([8, 9]));
    await tester.tap(find.byKey(const ValueKey('calendar-period-day-2026-9-1')));
    await tester.pumpAndSettle();
    // Selecting the second day must not move the three-day window.
    expect(find.byKey(const ValueKey('calendar-period-day-2026-8-31')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-period-day-2026-9-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-timeline-record-sep-plan')), findsOneWidget);
    expect(find.text('跨月计划'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('跨月读取失败明确提示重试，不伪造空日期', (tester) async {
    var failSeptember = true;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: DateTime(2026, 8),
        initialSelectedDate: DateTime(2026, 8, 31),
        monthLoader: (requested) async {
          if (requested.month == 9 && failSeptember) {
            throw StateError('unavailable');
          }
          return CalendarMonthData(month: requested, records: const []);
        },
      )),
    ));
    await tester.pumpAndSettle();
    await selectCalendarView(tester, '七日');
    expect(find.text('部分日期读取失败'), findsOneWidget);
    expect(find.text('这天没有记录'), findsNothing);
    failSeptember = false;
    await tester.tap(find.text('重新加载').last);
    await tester.pumpAndSettle();
    expect(find.text('部分日期读取失败'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-period-day-2026-9-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('恢复上次保存的日历视图', (tester) async {
    SharedPreferences.setMockInitialValues({'calendar.view_mode': 'threeDays'});
    await pumpCalendar(tester);
    expect(find.byKey(const ValueKey('calendar-date-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-selected-timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-2026-08-21')), findsNothing);
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

    expect(find.byKey(const ValueKey('calendar-month-label')), findsOneWidget);
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
