import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/controllers/habit_controller.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/habit_log.dart';
import 'package:slowlight/models/habit_schedule_rule.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';
import 'package:slowlight/widgets/habit_heatmap.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

class _EmptyHabitRepo extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [];
}

class _SampleHabitRepo extends HabitRepository {
  _SampleHabitRepo({this.fail = false});
  final bool fail;

  @override
  Future<List<Habit>> getAll() async {
    if (fail) throw StateError('网络不可用');
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final oldDate = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    return [
      Habit(
        id: 1,
        userId: 1,
        name: '每日阅读',
        icon: '📚',
        color: '#1890ff',
        frequency: 'daily',
        durationMin: 20,
        preferredPeriod: 'evening',
        checkedToday: false,
        checkedDays: [oldDate],
        streakCount: 1,
        createdAt: now.subtract(const Duration(days: 10)),
      ),
      Habit(
        id: 2,
        userId: 1,
        name: '户外散步',
        icon: '🚶',
        color: '#52c41a',
        frequency: 'daily',
        checkedToday: true,
        checkedDays: const [],
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ];
  }

  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async => [];
}

class _OverviewHabitRepo extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [
    Habit(
      id: 11, userId: 1, name: '每天阅读', createdAt: DateTime(2026),
      checkedToday: true, goalPeriod: 'week', goalValue: 3, goalMet: true,
    ),
    Habit(
      id: 12, userId: 1, name: '每周散步', createdAt: DateTime(2026),
      checkedToday: true, goalPeriod: 'week', goalValue: 4, goalMet: false,
    ),
    Habit(
      id: 13, userId: 1, name: '练习写字', createdAt: DateTime(2026),
      checkedToday: false, periodTarget: 2, periodCount: 2,
    ),
  ];
}

class _DelayedHabitsRepo extends HabitRepository {
  final first = Completer<List<Habit>>();
  final second = Completer<List<Habit>>();
  int reads = 0;

  @override
  Future<List<Habit>> getAll() => ++reads == 1 ? first.future : second.future;
}

class _DelayedLogsRepo extends HabitRepository {
  final first = Completer<List<HabitLog>>();
  final latest = Completer<List<HabitLog>>();
  int reads = 0;

  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) {
    return ++reads == 1 ? first.future : latest.future;
  }
}

class _P05HistoryRepo extends HabitRepository {
  _P05HistoryRepo(this.habit);
  final Habit habit;
  final next = Completer<List<HabitLog>>();
  int reads = 0;

  HabitLog fact(int id) => HabitLog(
    id: id,
    habitId: habit.id,
    date: HabitScheduleRule.dayKey(DateTime.now()),
    period: '',
    durationMin: 0,
    note: '记录 $id',
    createdAt: DateTime.now(),
  );

  @override
  Future<List<Habit>> getAll() async => [habit];

  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async {
    reads++;
    if (reads == 1) return [fact(1), fact(2), fact(3), fact(4)];
    return next.future;
  }
}

class _P05SingleLogRepo extends HabitRepository {
  int? deletedId;
  final habit = Habit(
    id: 79, userId: 1, name: '精确撤销记录', icon: '✅',
    color: '#52c41a', frequency: 'custom', checkedToday: true,
    canCheckIn: true,
    scheduleRule: const {
      'kind': 'interval', 'unit': 'hour', 'every': 2,
      'anchor_date': '2026-01-01', 'anchor_time': '08:00',
    },
    createdAt: DateTime.now(),
  );

  @override
  Future<List<Habit>> getAll() async => [habit];

  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async =>
      deletedId == null ? [
        HabitLog(
          id: 501, habitId: 79,
          date: HabitScheduleRule.dayKey(DateTime.now()),
          durationMin: 0, period: '', note: '独立事实',
          createdAt: DateTime.now(),
        ),
      ] : [];

  @override
  Future<List<HabitLog>> logsForVerification(int habitId) => logs(habitId);

  @override
  Future<void> deleteLog(int habitId, int logId) async {
    if (habitId != 79) throw StateError('wrong habit');
    deletedId = logId;
  }

  @override
  Future<Map<String, dynamic>> uncheckIn(int habitId) async =>
      throw StateError('day-level cancel must never be called');
}

class _LostDeleteAckRepo extends _P05SingleLogRepo {
  int attempts = 0;

  @override
  Future<void> deleteLog(int habitId, int logId) async {
    attempts++;
    await super.deleteLog(habitId, logId);
    throw StateError('删除已提交，但响应丢失');
  }
}

class _UnverifiedDeleteRepo extends _P05SingleLogRepo {
  @override
  Future<List<HabitLog>> logsForVerification(int habitId) async =>
      throw StateError('remote read failed; cached log is not evidence');
}

void main() {
  testWidgets('X06 缓存已消失但云端无法核实时不得误报撤销成功', (tester) async {
    tester.view.physicalSize = const Size(1100, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _UnverifiedDeleteRepo();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habits.details.79')));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('habits.logs.cancel.501'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销记录'));
    await tester.pumpAndSettle();

    expect(repo.deletedId, 501);
    expect(find.text('记录已撤销'), findsNothing);
    expect(find.textContaining('撤销结果未确认'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X06 撤销响应丢失时仅重读单条日志，不重复发送删除', (tester) async {
    tester.view.physicalSize = const Size(1100, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _LostDeleteAckRepo();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habits.details.79')));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('habits.logs.cancel.501'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销记录'));
    await tester.pumpAndSettle();

    expect(repo.attempts, 1);
    expect(repo.deletedId, 501);
    expect(find.byKey(const ValueKey('habits.logs.cancel.501')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P1-9 习惯卡片详情展开/收起复用可中断轻过渡', (tester) async {
    tester.view.physicalSize = const Size(1100, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _P05SingleLogRepo())),
    ));
    await tester.pumpAndSettle();

    final motion = find.byKey(const ValueKey('habits.motion.79'));
    expect(motion, findsOneWidget);
    expect(tester.widget<AnimatedSize>(motion).duration,
        const Duration(milliseconds: 180));
    final toggle = find.byKey(const ValueKey('habits.details.79'));
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('本月记录'), findsOneWidget);
    // Reverse before the previous animation has finished.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('本月记录'), findsNothing);
    expect(toggle, findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P05 单条撤销按日志身份删除，不误用仍可打卡的日级 toggle', (tester) async {
    tester.view.physicalSize = const Size(1100, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _P05SingleLogRepo();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habits.details.79')));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('habits.logs.cancel.501'));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('撤销这条记录'), findsOneWidget);
    await tester.tap(find.text('撤销记录'));
    await tester.pumpAndSettle();
    expect(repo.deletedId, 501);
    expect(find.byKey(const ValueKey('habits.logs.cancel.501')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P05 历史刷新保留已读记录与核对状态', (tester) async {
    tester.view.physicalSize = const Size(1100, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _P05HistoryRepo(Habit(
      id: 77, userId: 1, name: '历史记录', icon: '📖',
      color: '#1890ff', frequency: 'daily', createdAt: DateTime.now(),
    ));
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('habits.details.77'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('记录 1'), findsOneWidget);
    expect(find.text('查看全部 4 条记录'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(repo.reads, 2);
    expect(find.textContaining('正在核对记录'), findsOneWidget);
    expect(find.text('记录 1'), findsOneWidget);
    repo.next.complete([repo.fact(5), repo.fact(4), repo.fact(3),
      repo.fact(2), repo.fact(1)]);
    await tester.pumpAndSettle();
    expect(find.textContaining('正在核对记录'), findsNothing);
    expect(find.text('记录 5'), findsOneWidget);
    expect(find.text('查看全部 5 条记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P05 V3 目标达标不隐藏多次记录入口', (tester) async {
    tester.view.physicalSize = const Size(1050, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _P05HistoryRepo(Habit(
      id: 78, userId: 1, name: '本期已经达标', icon: '✅',
      color: '#52c41a', frequency: 'custom',
      scheduleRule: const {
        'version': 1, 'kind': 'goal', 'unit': 'week',
        'every': 1, 'anchor_date': '2026-01-01',
        'anchor_time': '08:00', 'target_count': 1,
        'same_day_multiple': true,
      },
      checkedToday: true, canCheckIn: true,
      allowMultiplePerDay: false, periodCount: 2, periodTarget: 1,
      createdAt: DateTime.now(),
    ));
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    final button = tester.widget<FxButton>(
      find.byKey(const ValueKey('habits.today.78')),
    );
    expect(button.label, '新增记录');
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P09 搜索定位命中习惯，复用正式卡片展开真实记录', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: HabitToolScreen(
          repository: _SampleHabitRepo(),
          focusHabitId: 2,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('habits.card.2')), findsOneWidget);
    final details = tester.widget<FxButton>(
      find.byKey(const ValueKey('habits.details.2')),
    );
    expect(details.label, contains('收起'));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  test('P05 展开详情中途发生新打卡，旧请求不能覆盖最新记录', () async {
    final repository = _DelayedLogsRepo();
    final controller = HabitController(repository: repository);
    final pending = controller.loadLogs(7);
    final afterWrite = controller.loadLogs(7);
    expect(repository.reads, 1);
    expect(controller.isLoadingLogs(7), isTrue);

    final now = DateTime.now();
    HabitLog log(int id) => HabitLog(
      id: id,
      habitId: 7,
      date: '2026-11-07',
      period: 'morning',
      durationMin: 0,
      note: '记录 $id',
      createdAt: now,
    );
    repository.first.complete([log(1)]);
    await Future<void>.delayed(Duration.zero);
    expect(repository.reads, 2);
    expect(controller.isLoadingLogs(7), isTrue);
    expect(controller.logsFor(7), isEmpty); // stale response is never shown

    repository.latest.complete([log(1), log(2)]);
    await Future.wait([pending, afterWrite]);
    expect(controller.isLoadingLogs(7), isFalse);
    expect(controller.logsFor(7).map((item) => item.id), [1, 2]);
    expect(controller.logErrorFor(7), isNull);
    controller.dispose();
  });


  testWidgets('今天的创建意图只打开一次既有习惯编辑器', (tester) async {
    var opens = 0;
    Future<HabitEditorValue?> editor(BuildContext context, {Habit? habit}) async {
      opens++;
      return null;
    }

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: HabitToolScreen(
          repository: _EmptyHabitRepo(),
          editor: editor,
          createOnOpen: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(opens, 1);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: HabitToolScreen(
          repository: _EmptyHabitRepo(),
          editor: editor,
          createOnOpen: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 展开月记录使用七列方块并铺满右侧容器', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _SampleHabitRepo())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habits.details.1')));
    await tester.pumpAndSettle();

    expect(find.byType(HabitHeatmap), findsOneWidget);
    final heatmap = find.byKey(const ValueKey('habit-month-heatmap-grid'));
    expect(heatmap, findsOneWidget);
    final grid = tester.widget<GridView>(heatmap);
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 7);
    expect(delegate.childAspectRatio, 1);
    final available = tester.getSize(find.byType(HabitHeatmap));
    expect(tester.getSize(heatmap).width, closeTo(available.width, 1));
    expect(tester.getSize(heatmap).width, greaterThan(150));

    final today = DateTime.now();
    final todayKey = 'habit-heatmap-day-${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    expect(find.byKey(ValueKey(todayKey), skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('09 Android 360dp 首页同时可见习惯概况与添加操作', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _EmptyHabitRepo())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('习惯'), findsOneWidget);
    expect(find.text('0 个习惯 · 今日 0 个有记录'), findsOneWidget);
    expect(find.text('添加习惯'), findsOneWidget);
    expect(find.text('创建第一个习惯'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  test('P1-7 旧习惯列表迟到不会覆盖已经读取的新目标状态', () async {
    final repo = _DelayedHabitsRepo();
    final controller = HabitController(repository: repo);
    final initial = controller.load();
    final newer = controller.load();
    repo.second.complete([
      Habit(
        id: 2, userId: 1, name: '更新后的习惯',
        createdAt: DateTime(2026),
        goalPeriod: 'week', goalValue: 2, goalMet: true,
      ),
    ]);
    await newer;
    repo.first.complete([
      Habit(
        id: 1, userId: 1, name: '旧响应',
        createdAt: DateTime(2026),
        checkedToday: true,
      ),
    ]);
    await initial;
    expect(controller.habits.single.name, '更新后的习惯');
    expect(habitOverviewCounts(controller.habits).met, 1);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('P1-7 习惯数、今天有记录的习惯数与本期达标分别计算', () {
    final habits = [
      Habit(id: 1, userId: 1, name: '阅读', createdAt: DateTime(2026),
        checkedToday: true, goalPeriod: 'week', goalValue: 3,
        goalMet: true),
      Habit(id: 2, userId: 1, name: '行走', createdAt: DateTime(2026),
        checkedToday: true, goalPeriod: 'week', goalValue: 2,
        goalMet: false),
      Habit(id: 3, userId: 1, name: '运动', createdAt: DateTime(2026),
        periodTarget: 2, periodCount: 2),
      Habit(id: 4, userId: 1, name: '无目标', createdAt: DateTime(2026)),
    ];
    final result = habitOverviewCounts(habits);
    expect(result.total, 4);
    expect(result.recordedToday, 2);
    expect(result.targets, 3);
    expect(result.met, 2);
  });

  testWidgets('P1-7 Android 概况分别展示习惯、今日日志条数与周期达标',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(
        repository: _OverviewHabitRepo(),
        todayLogCountLoader: () async => 4,
      )),
    ));
    await tester.pumpAndSettle();

    // Two distinct habits have logs today; four actual events, not two.
    expect(find.text('3 个习惯 · 今日 2 个有记录'), findsOneWidget);
    expect(find.text('今日日志 4 条 · 本期达标 2/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P1-7 今日日志读取失败不能展示伪造的零条',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(
        repository: _OverviewHabitRepo(),
        todayLogCountLoader: () => Future<int>.error(StateError('offline')),
      )),
    ));
    await tester.pumpAndSettle();

    expect(find.text('今日日志待核对'), findsOneWidget);
    expect(find.text('本期达标 2/3'), findsOneWidget);
    expect(find.text('今日日志 0 条'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P1-7 后发的刷新成功不得被更早日志统计结果覆盖',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final first = Completer<int>();
    final second = Completer<int>();
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(
        repository: _OverviewHabitRepo(),
        todayLogCountLoader: () => ++reads == 1 ? first.future : second.future,
      )),
    ));
    await tester.pump();
    await tester.pump();
    expect(reads, 1);

    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pump();
    await tester.pump();
    expect(reads, 2);
    second.complete(5);
    await refresh;
    await tester.pump();
    first.complete(99);
    await tester.pump();

    expect(find.text('今日日志 5 条'), findsOneWidget);
    expect(find.text('今日日志 99 条'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('09 Android 超大字体仍可访问习惯添加', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(body: HabitToolScreen(repository: _EmptyHabitRepo())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('添加习惯'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('Android 360dp 习惯卡紧凑，七日事实只读且保持可读宽度',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _SampleHabitRepo())),
    ));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('habits.card.1'));
    final second = find.byKey(const ValueKey('habits.card.2'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    final between = tester.getTopLeft(second).dy -
        tester.getBottomLeft(first).dy;
    expect(between, closeTo(SlowlightSpacing.md, 1));

    final weekDay = find.byKey(const ValueKey('habits.week.1.0'));
    expect(weekDay, findsOneWidget);
    expect(tester.getSize(weekDay).width, closeTo(7, 1));
    expect(tester.getSize(weekDay).height, closeTo(7, 1));
    final barriersBefore = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(weekDay);
    await tester.pumpAndSettle();
    // A read-only history marker cannot open a record/backfill sheet.
    expect(find.byType(ModalBarrier).evaluate().length, barriersBefore);
    expect(find.byKey(const ValueKey('habits.today.1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('折叠卡片可见习惯、频率、今日操作和近七日，展开显示详情', (tester) async {
    tester.view.physicalSize = const Size(1080, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _SampleHabitRepo())),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('habits.card.1')), findsOneWidget);
    expect(find.text('每日阅读'), findsOneWidget);
    expect(find.text('每天 · 傍晚 · 20 分钟'), findsOneWidget);
    expect(find.text('今日已记录 1/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('habits.today.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('habits.week.1.0')), findsOneWidget);
    expect(find.byKey(const ValueKey('habits.week.1.6')), findsOneWidget);
    expect(find.text('当前连续'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('habits.details.1')));
    await tester.pumpAndSettle();
    expect(find.text('当前连续'), findsOneWidget);
    expect(find.text('已记录天数'), findsOneWidget);
    expect(find.text('最近记录'), findsOneWidget);
    expect(find.text('补卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('习惯打卡操作轻量且右边缘对齐，七日概览无需展开', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _SampleHabitRepo())),
    ));
    await tester.pumpAndSettle();

    const pendingKey = ValueKey('habits.today.1');
    const recordedKey = ValueKey('habits.today.2');
    final pending = find.byKey(pendingKey);
    final recorded = find.byKey(recordedKey);
    final pendingCheckbox = find.descendant(
      of: pending,
      matching: find.byType(FxCheckbox),
    );
    final recordedCheckbox = find.descendant(
      of: recorded,
      matching: find.byType(FxCheckbox),
    );
    expect(pendingCheckbox, findsOneWidget);
    expect(recordedCheckbox, findsOneWidget);
    expect(tester.widget<FxCheckbox>(pendingCheckbox).value, isFalse);
    expect(tester.widget<FxCheckbox>(recordedCheckbox).value, isTrue);
    expect(tester.getSize(pending).width, greaterThanOrEqualTo(44));
    expect(tester.getTopRight(pending).dx,
        closeTo(tester.getTopRight(recorded).dx, 1));
    expect(find.descendant(
      of: find.byKey(const ValueKey('habits.expand.1')),
      matching: find.byType(Icon),
    ), findsNothing);

    // Week status and explicit details link are visible before expanding.
    expect(find.byKey(const ValueKey('habits.week.1.0')), findsOneWidget);
    expect(find.byKey(const ValueKey('habits.week.1.6')), findsOneWidget);
    expect(find.byKey(const ValueKey('habits.details.1')), findsOneWidget);
    expect(find.text('当前连续'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 习惯页依原型显示紧凑图标、七日点阵和筛选语义',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _SampleHabitRepo())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 个习惯 · 今日 1 个有记录'), findsOneWidget);
    expect(find.text('今日未记录'), findsOneWidget);
    expect(find.text('今日有记录'), findsOneWidget);

    final iconBox = find.byKey(const ValueKey('habits.icon.1'));
    expect(tester.getSize(iconBox).width, closeTo(32, 1));
    expect(tester.getSize(iconBox).height, closeTo(32, 1));

    final week = find.byKey(const ValueKey('habits.week.1.0'));
    final detail = find.byKey(const ValueKey('habits.details.1'));
    expect(tester.getSize(week).width, closeTo(7, 1));
    expect(tester.getSize(week).height, closeTo(7, 1));
    expect(find.descendant(
      of: find.byKey(const ValueKey('habits.card.1')),
      matching: find.text('详情'),
    ), findsOneWidget);
    expect(tester.getSize(detail).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('筛选全部、待记录、已记录来自仓库真实状态', (tester) async {
    tester.view.physicalSize = const Size(1080, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _SampleHabitRepo())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('每日阅读'), findsOneWidget);
    expect(find.text('户外散步'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('habits.filter_pending')));
    await tester.pumpAndSettle();
    expect(find.text('每日阅读'), findsOneWidget);
    expect(find.text('户外散步'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('habits.filter_done')));
    await tester.pumpAndSettle();
    expect(find.text('户外散步'), findsOneWidget);
    expect(find.text('每日阅读'), findsNothing);
    await disposeFxTestHost(tester);
  });

  testWidgets('仓库出错时提示失败而不误称为空习惯', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(
        repository: _SampleHabitRepo(fail: true),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('习惯加载失败'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('还没有习惯记录'), findsNothing);
    await disposeFxTestHost(tester);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('有数据习惯卡 $platform × $scale：主要动作不溢出',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        tester.view.physicalSize = platform == TargetPlatform.android
            ? const Size(360, 800)
            : const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(buildFxTestHost(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(body: HabitToolScreen(repository: _SampleHabitRepo())),
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('habits.card.1')), findsOneWidget);
        expect(find.byKey(const ValueKey('habits.today.1')), findsOneWidget);
        expect(find.text('每日阅读'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

  testWidgets('习惯编辑名称为空不静默失败，错误数字不再变成 0', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(body: HabitEditorDialog()),
    ));
    await tester.pump();

    await tester.tap(find.text('创建习惯'));
    await tester.pump();
    expect(find.text('请填写习惯名称'), findsOneWidget);

    await tester.enterText(find.byType(FxInput).first, '每日阅读');
    await tester.ensureVisible(find.text('记录与目标'));
    await tester.tap(find.text('记录与目标'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final target = find.byWidgetPredicate((widget) =>
        widget is FxInput && widget.label == '目标天数');
    await tester.ensureVisible(target);
    await tester.enterText(target, '错误数字');
    await tester.ensureVisible(find.text('创建习惯'));
    await tester.tap(find.text('创建习惯'));
    await tester.pump();
    expect(find.text('目标天数必须是 0 或正整数'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
