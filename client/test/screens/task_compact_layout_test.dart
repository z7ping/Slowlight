import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/services/data_service.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/task_tool_screen.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:slowlight/widgets/task_swipe_row.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

/// Deterministic Cloud-like toggle source for X03 stale Undo verification.
class _X03ToggleTaskService implements DataService {
  bool completed = false;
  int completedRevision = 0;
  bool failReadAfterWrite = false;
  int completions = 0;
  int undoCalls = 0;
  int postpones = 0;
  int postponeUndos = 0;
  DateTime? dueDate;

  Task get current => Task(
    id: 903,
    listId: 1,
    title: '撤销状态测试任务',
    priority: 'none',
    isCompleted: completed,
    createdAt: DateTime(2026, 11, 8),
    completedAt: completed
        ? DateTime(2026, 11, 8).add(Duration(seconds: completedRevision))
        : null,
    dueDate: dueDate,
  );

  @override
  Future<List<Task>> getTodayTasks() async => [current];

  @override
  Future<List<Task>> getAllTasks() async {
    if (failReadAfterWrite && completions > 0) {
      throw StateError('任务列表本轮读取失败');
    }
    return [current];
  }

  @override
  Future<List<Task>> getCompletedTasks() async =>
      completed ? [current] : <Task>[];

  @override
  Future<List<TodoList>> getLists() async => [
    TodoList(id: 1, name: '收集箱', color: '#808080',
      isInbox: true, createdAt: DateTime(2026, 11, 8)),
  ];

  @override
  Future<Task> completeTask(int localId, int? serverId) async =>
      setTaskCompletion(localId, serverId,
        completed: true, expectedCompleted: false);

  @override
  Future<Task> uncompleteTask(int localId, int? serverId) async =>
      setTaskCompletion(localId, serverId,
        completed: false, expectedCompleted: true,
        expectedCompletedAt: current.completedAt);

  @override
  Future<Task> setTaskCompletion(
    int localId,
    int? serverId, {
    required bool completed,
    required bool expectedCompleted,
    DateTime? expectedCompletedAt,
  }) async {
    if (this.completed != expectedCompleted ||
        (expectedCompleted &&
         (expectedCompletedAt == null ||
          current.completedAt == null ||
          !current.completedAt!.isAtSameMomentAs(expectedCompletedAt)))) {
      throw StateError('任务状态已变化');
    }
    if (completed) {
      completions++;
      completedRevision++;
    } else {
      undoCalls++;
    }
    this.completed = completed;
    return current;
  }

  @override
  Future<Task> postponeTask(int localId, int? serverId) async {
    postpones++;
    final now = DateTime.now();
    dueDate = DateTime(now.year, now.month, now.day + 1);
    return current;
  }

  @override
  Future<Task> restorePostponedDueDate(
    int localId,
    int? serverId, {
    required DateTime expectedDueDate,
    DateTime? originalDueDate,
  }) async {
    if (dueDate == null ||
        !dueDate!.isAtSameMomentAs(expectedDueDate) || completed) {
      throw StateError('任务日期已变化，无法撤销顺延');
    }
    postponeUndos++;
    dueDate = originalDueDate;
    return current;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('X03 左滑顺延后可撤销原始无日期任务', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _X03ToggleTaskService();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataService: data)),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.text('撤销状态测试任务'), const Offset(-110, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('顺延'));
    await tester.pumpAndSettle();

    expect(data.postpones, 1);
    expect(data.dueDate, isNotNull);
    final undo = tester.widget<FxNoticeAction>(find.byType(FxNoticeAction));
    undo.onPressed();
    await tester.pumpAndSettle();
    expect(data.postponeUndos, 1);
    expect(data.dueDate, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X03 顺延后日期被其他操作改变，旧撤销不会覆盖它', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _X03ToggleTaskService();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataService: data)),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.text('撤销状态测试任务'), const Offset(-110, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('顺延'));
    await tester.pumpAndSettle();

    final undo = tester.widget<FxNoticeAction>(find.byType(FxNoticeAction));
    final changedDate = DateTime(2030, 5, 21);
    data.dueDate = changedDate;
    undo.onPressed();
    await tester.pumpAndSettle();
    expect(data.postponeUndos, 0);
    expect(data.dueDate, changedDate);
    expect(find.textContaining('任务日期已变化'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X03 当前仍完成时，通知撤销只执行一次恢复待办', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _X03ToggleTaskService();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataService: data)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('tasks.row.903')),
      matching: find.byType(FxInkWell),
    ).last);
    await tester.pumpAndSettle();
    final undo = tester.widget<FxNoticeAction>(
      find.byType(FxNoticeAction),
    );
    undo.onPressed();
    await tester.pumpAndSettle();

    expect(data.completions, 1);
    expect(data.undoCalls, 1);
    expect(data.completed, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X03 旧撤销通知不能重新完成已经恢复待办的任务', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _X03ToggleTaskService();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataService: data)),
    ));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('tasks.row.903'));
    final toggles = find.descendant(
      of: row, matching: find.byType(FxInkWell),
    );
    await tester.tap(toggles.last);
    await tester.pumpAndSettle();
    expect(data.completions, 1);
    expect(data.completed, isTrue);
    final undoAction = find.byType(FxNoticeAction);
    expect(undoAction, findsOneWidget);

    // A second device or route has already uncompleted this task.
    data.completed = false;
    tester.widget<FxNoticeAction>(undoAction).onPressed();
    await tester.pumpAndSettle();
    expect(data.undoCalls, 0);
    expect(data.completed, isFalse);
    expect(find.textContaining('任务已是待办状态'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X03 旧撤销无法撤销另一次完成周期', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _X03ToggleTaskService();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataService: data)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('tasks.row.903')),
      matching: find.byType(FxInkWell),
    ).last);
    await tester.pumpAndSettle();

    final staleUndo = tester.widget<FxNoticeAction>(
      find.byType(FxNoticeAction),
    );
    // Another device uncompletes and then completes the same task again.
    data.completed = false;
    data.completedRevision++;
    data.completed = true;
    staleUndo.onPressed();
    await tester.pumpAndSettle();
    expect(data.undoCalls, 0);
    expect(data.completed, isTrue);
    expect(find.textContaining('新的完成记录'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X03 完成写入后列表刷新失败不误报成功或提供撤销', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _X03ToggleTaskService()..failReadAfterWrite = true;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataService: data)),
    ));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('tasks.row.903'));
    await tester.tap(find.descendant(
      of: row, matching: find.byType(FxInkWell),
    ).last);
    await tester.pumpAndSettle();
    expect(data.completions, 1);
    expect(find.byType(FxNoticeAction), findsNothing);
    expect(find.textContaining('列表状态尚未确认'), findsWidgets);
    // The cached row still shows pending; a second tap must not toggle it.
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('tasks.row.903')),
      matching: find.byType(FxInkWell),
    ).last);
    await tester.pumpAndSettle();
    expect(data.completions, 1);
    expect(find.textContaining('请先重试刷新再操作'), findsWidgets);
    expect(data.undoCalls, 0);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X03 筛选切换回到顶部并关闭上一个已展开的滑动行',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tasks = List<Task>.generate(36, (index) => Task(
      id: 1000 + index,
      listId: 1,
      title: '筛选任务 $index',
      priority: 'none',
      isCompleted: false,
      createdAt: DateTime(2026, 11, 8),
    ));
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        dataLoader: () async => <dynamic>[
          tasks, tasks, <Task>[], <TodoList>[],
        ],
      )),
    ));
    await tester.pumpAndSettle();
    final firstSwipe = tester.widget<TaskSwipeRow>(
      find.byKey(const ValueKey('tasks.swipe.1000')),
    );
    firstSwipe.onOpenChanged(true);
    await tester.pump();
    expect(tester.widget<TaskSwipeRow>(
      find.byKey(const ValueKey('tasks.swipe.1000')),
    ).open, isTrue);

    final view = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey('tasks.mobile.list')),
    );
    final controller = view.controller!;
    controller.jumpTo(90);
    await tester.pump();
    expect(controller.offset, greaterThan(0));

    tester.widget<FxInkWell>(
      find.byKey(const ValueKey('tasks.mobile.filter.1')),
    ).onTap!();
    await tester.pump();
    expect(controller.offset, 0);
    expect(tester.widget<TaskSwipeRow>(
      find.byKey(const ValueKey('tasks.swipe.1000')),
    ).open, isFalse);
    expect(find.text('所有任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P04 主任务先展示，不等待清单读取完成', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lists = Completer<List<TodoList>>();
    final now = DateTime.now();
    final task = Task(
      id: 91, listId: 1, title: '待处理的工作',
      priority: 'none', isCompleted: false, createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        taskDataLoader: () async => <dynamic>[
          <Task>[task], <Task>[task], <Task>[],
        ],
        listsLoader: () => lists.future,
      )),
    ));
    await tester.pumpAndSettle();
    expect(lists.isCompleted, isFalse);
    expect(find.text('待处理的工作'), findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);
    await tester.tap(find.text('待处理的工作'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);

    lists.complete([
      TodoList(
        id: 1, name: '收集箱', isInbox: true, color: '#8db5a0',
        createdAt: now,
      ),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P04 清单读取失败不清空任务，重试后恢复新建', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final task = Task(
      id: 92, listId: 1, title: '已有任务保留',
      priority: 'none', isCompleted: false, createdAt: now,
    );
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        taskDataLoader: () async => <dynamic>[
          <Task>[task], <Task>[task], <Task>[],
        ],
        listsLoader: () async {
          if (++reads == 1) throw StateError('清单暂时不可用');
          return [
            TodoList(
              id: 1, name: '收集箱', isInbox: true, color: '#8db5a0',
              createdAt: now,
            ),
          ];
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('已有任务保留'), findsOneWidget);
    expect(find.textContaining('清单读取失败，已有任务仍可浏览'), findsOneWidget);
    await tester.tap(find.text('已有任务保留'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);
    await tester.tap(find.text('重试清单'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('已有任务保留'), findsOneWidget);
    expect(find.textContaining('清单读取失败，已有任务仍可浏览'), findsNothing);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final create in [true, false]) {
    testWidgets('任务页${create ? '新建' : '查看详情'}打开同一任务编辑组件',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final task = Task(
        id: 42,
        listId: 7,
        title: '已有的任务',
        priority: 'none',
        isCompleted: false,
        createdAt: DateTime.now(),
      );
      final list = TodoList(
        id: 7, name: '收集箱', isInbox: true, color: '#8db5a0',
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(buildFxTestHost(
        home: Scaffold(
          body: TaskToolScreen(
            dataLoader: () async => <dynamic>[
              <Task>[task],
              <Task>[task],
              <Task>[],
              <TodoList>[list],
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (create) {
        await tester.tap(find.text('新建'));
      } else {
        await tester.tap(find.text('已有的任务'));
      }
      await tester.pumpAndSettle();
      final detail = find.byType(TaskDetailSheet);
      expect(detail, findsOneWidget);
      expect(tester.widget<TaskDetailSheet>(detail).isCreating, create);
      for (final field in ['list', 'due', 'priority', 'tags']) {
        expect(find.byKey(ValueKey('task.detail.property.$field')),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey('task.detail.primaryAction')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('Android 任务列表按原型呈现轻量新建、下划线筛选和紧凑行',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final pending = Task(
      id: 31, listId: 1, title: '认真阅读',
      priority: 'important', isCompleted: false, createdAt: now,
    );
    final completed = Task(
      id: 32, listId: 1, title: '整理清单',
      priority: 'none', isCompleted: true,
      completedAt: now, createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[pending],
            <Task>[pending, completed],
            <Task>[completed],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tasks.mobile.list')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.mobile.filters')), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('今日相关'), findsOneWidget);
    final pendingRow = find.byKey(const ValueKey('tasks.row.31'));
    expect(pendingRow, findsOneWidget);
    expect(tester.getSize(pendingRow).height,
        inInclusiveRange(44, 62));

    await tester.tap(find.byKey(const ValueKey('tasks.mobile.filter.1')));
    await tester.pumpAndSettle();
    expect(find.text('所有任务'), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.row.32')), findsOneWidget);
    final doneRow = find.byKey(const ValueKey('tasks.row.32'));
    expect(tester.getSize(doneRow).height,
        closeTo(tester.getSize(pendingRow).height, 1));
    // The approved mobile row has a round 18dp completed mark, not a
    // rounded-square checkbox. The outer control still owns a 44dp hit area.
    final circles = tester.widgetList<Container>(
      find.descendant(of: doneRow, matching: find.byType(Container)),
    ).where((widget) =>
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).shape == BoxShape.circle);
    expect(circles, isNotEmpty);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('今天筛选保留全部真实记录，但未完成任务在前', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    Task record(int id, {required bool done}) => Task(
      id: id,
      listId: 1,
      title: '排序任务 $id',
      priority: 'none',
      isCompleted: done,
      createdAt: now,
    );
    final completed = record(1, done: true);
    final firstPending = record(2, done: false);
    final secondPending = record(3, done: false);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[completed, firstPending, secondPending],
            <Task>[completed, firstPending, secondPending],
            <Task>[completed],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('今日相关'), findsOneWidget);
    expect(find.text('3 项'), findsOneWidget);
    final a = find.byKey(const ValueKey('tasks.row.2'));
    final b = find.byKey(const ValueKey('tasks.row.3'));
    final done = find.byKey(const ValueKey('tasks.row.1'));
    expect(a, findsOneWidget);
    expect(b, findsOneWidget);
    expect(done, findsOneWidget);
    expect(tester.getTopLeft(a).dy, lessThan(tester.getTopLeft(b).dy));
    expect(tester.getTopLeft(b).dy, lessThan(tester.getTopLeft(done).dy));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('全部任务混合状态下行高和间距一致，不露出滑动操作背景',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final pending = Task(
      id: 21,
      listId: 1,
      title: '待完成任务',
      priority: 'none',
      isCompleted: false,
      createdAt: now,
    );
    final completed = Task(
      id: 22,
      listId: 1,
      title: '已完成任务',
      priority: 'none',
      isCompleted: true,
      completedAt: now,
      createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[pending],
            <Task>[pending, completed],
            <Task>[completed],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    final pendingRow = find.byKey(const ValueKey('tasks.row.21'));
    final doneRow = find.byKey(const ValueKey('tasks.row.22'));
    expect(pendingRow, findsOneWidget);
    expect(doneRow, findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.swipe.21')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.swipe.22')), findsNothing);

    final pendingRect = tester.getRect(pendingRow);
    final doneRect = tester.getRect(doneRow);
    expect(pendingRect.height, greaterThanOrEqualTo(44));
    expect(doneRect.height, greaterThanOrEqualTo(44));
    expect(doneRect.height, closeTo(pendingRect.height, 1));
    expect(doneRect.top - pendingRect.bottom,
        closeTo(SlowlightSpacing.xs, 1));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('500 条 Android 任务按需构建，首屏不一次挂载所有滑动行',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final tasks = List<Task>.generate(
      500,
      (index) => Task(
        id: index + 1,
        listId: 1,
        title: '任务 ${index + 1}',
        priority: 'none',
        isCompleted: false,
        createdAt: now,
      ),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            tasks,
            tasks,
            <Task>[],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverList), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.mobile.shell.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.mobile.shell.500')), findsNothing);
    expect(find.byType(TaskSwipeRow).evaluate().length, lessThan(40));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 任务详情切换与关闭必须保护未保存草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    Task task(int id, String title) => Task(
      id: id, listId: 1, title: title, priority: 'none',
      isCompleted: false, createdAt: now,
    );
    final first = task(41, '第一项任务');
    final second = task(42, '第二项任务');
    final lists = <TodoList>[
      TodoList(id: 1, name: '收集箱', isInbox: true,
          color: '#8db5a0', createdAt: now),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[first, second],
            <Task>[first, second],
            <Task>[],
            lists,
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tasks.row.41')));
    await tester.pumpAndSettle();
    Finder titleField() => find.descendant(
      of: find.byType(TaskDetailSheet),
      matching: find.byType(EditableText),
    ).first;
    expect(tester.widget<TaskDetailSheet>(find.byType(TaskDetailSheet))
        .task.id, 41);
    await tester.enterText(titleField(), '第一项任务：尚未保存');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('tasks.row.42')));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TaskDetailSheet>(find.byType(TaskDetailSheet))
        .task.id, 41);
    expect(tester.widget<EditableText>(titleField()).controller.text,
        '第一项任务：尚未保存');

    await tester.tap(find.byKey(const ValueKey('tasks.row.42')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(tester.widget<TaskDetailSheet>(find.byType(TaskDetailSheet))
        .task.id, 42);
    expect(tester.widget<EditableText>(titleField()).controller.text,
        '第二项任务');

    await tester.enterText(titleField(), '第二项任务：草稿');
    await tester.pump();
    await tester.tap(fxTooltipFinder('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    await tester.tap(fxTooltipFinder('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X04 Windows 刷新中任务消失时草稿保留但禁止陈旧写入', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 8);
    final old = Task(id: 404, listId: 1, title: '原任务',
        priority: 'none', isCompleted: false, createdAt: now);
    final lists = [TodoList(id: 1, name: '收集箱',
        color: '#808080', isInbox: true, createdAt: now)];
    var sourceHasTask = true;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        dataLoader: () async => <dynamic>[
          <Task>[if (sourceHasTask) old],
          <Task>[if (sourceHasTask) old],
          <Task>[],
          lists,
        ],
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tasks.row.404')));
    await tester.pumpAndSettle();
    final detail = find.byType(TaskDetailSheet);
    final title = find.descendant(
        of: detail, matching: find.byType(EditableText)).first;
    await tester.enterText(title, '本机未保存的修改');
    await tester.pump();
    sourceHasTask = false;
    tester.widget<TaskDetailSheet>(detail).onChanged();
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(tester.widget<EditableText>(title).controller.text,
        '本机未保存的修改');
    expect(find.textContaining('草稿已保留'), findsOneWidget);
    expect(tester.widget<TaskDetailSheet>(detail).writeBlocked, isTrue);
    final save = find.ancestor(
      of: find.text('保存修改'),
      matching: find.byType(FxButton),
    ).last;
    expect(tester.widget<FxButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X04 Windows 无草稿时刷新同任务可重新加载最新字段', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 8);
    var name = '旧名称';
    final lists = [TodoList(id: 1, name: '收集箱',
        color: '#808080', isInbox: true, createdAt: now)];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        dataLoader: () async {
          final task = Task(id: 405, listId: 1, title: name,
            priority: 'none', isCompleted: false, createdAt: now);
          return <dynamic>[<Task>[task], <Task>[task], <Task>[], lists];
        },
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tasks.row.405')));
    await tester.pumpAndSettle();
    expect(tester.widget<TaskDetailSheet>(
      find.byType(TaskDetailSheet)).task.title, '旧名称');
    name = '远端更新后的名称';
    tester.widget<TaskDetailSheet>(
      find.byType(TaskDetailSheet)).onChanged();
    await tester.pumpAndSettle();
    final detail = find.byType(TaskDetailSheet);
    expect(tester.widget<TaskDetailSheet>(detail).task.title, name);
    expect(tester.widget<EditableText>(
      find.descendant(of: detail, matching: find.byType(EditableText)).first,
    ).controller.text, name);
    expect(tester.widget<TaskDetailSheet>(detail).writeBlocked, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X04 Windows 刷新发现任务字段变化不覆盖本机草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 8);
    var remoteTitle = '旧名称';
    final lists = [TodoList(id: 1, name: '收集箱',
      color: '#808080', isInbox: true, createdAt: now)];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        dataLoader: () async {
          final task = Task(id: 406, listId: 1, title: remoteTitle,
            priority: 'none', isCompleted: false, createdAt: now);
          return <dynamic>[<Task>[task], <Task>[task], <Task>[], lists];
        },
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tasks.row.406')));
    await tester.pumpAndSettle();
    final detail = find.byType(TaskDetailSheet);
    final title = find.descendant(of: detail,
      matching: find.byType(EditableText)).first;
    await tester.enterText(title, '尚未保存的本机草稿');
    await tester.pump();
    remoteTitle = '另一台设备的新名称';
    tester.widget<TaskDetailSheet>(detail).onChanged();
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(title).controller.text,
      '尚未保存的本机草稿');
    expect(tester.widget<TaskDetailSheet>(detail).writeBlocked, isTrue);
    expect(find.textContaining('草稿已保留'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 筛选切换先保护详情草稿，不直接卸载编辑器', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final task = Task(
      id: 81, listId: 1, title: '待处理过滤任务',
      priority: 'none', isCompleted: false, createdAt: now,
    );
    final lists = <TodoList>[
      TodoList(id: 1, name: '收集箱', isInbox: true,
          color: '#8db5a0', createdAt: now),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(dataLoader: () async => <dynamic>[
          <Task>[task], <Task>[task], <Task>[], lists,
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tasks.row.81')));
    await tester.pumpAndSettle();
    final editor = find.descendant(
      of: find.byType(TaskDetailSheet),
      matching: find.byType(EditableText),
    ).first;
    await tester.enterText(editor, '尚未保存的任务');
    await tester.pump();

    await tester.tap(find.text('已完成').first);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(tester.widget<EditableText>(editor).controller.text,
        '尚未保存的任务');

    await tester.tap(find.text('已完成').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);
    expect(find.text('还没有已完成任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 任务页按原型呈现分栏与轻量详情占位', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final task = Task(id: 221, listId: 1, title: '桌面任务',
        priority: 'none', isCompleted: false, createdAt: now);
    final list = TodoList(id: 1, name: '工作', isInbox: true,
        color: '#8db5a0', createdAt: now);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(dataLoader: () async => <dynamic>[
          <Task>[task], <Task>[task], <Task>[], <TodoList>[list],
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('tasks.row.221'));
    final hint = find.text('选择一项任务查看详情');
    expect(row, findsOneWidget);
    expect(hint, findsOneWidget);
    expect(find.text('列表用于浏览，日期、描述和提醒在这里调整。'),
        findsOneWidget);
    expect(find.text('提示：点击左侧任务即可在当前页面查看详情'),
        findsNothing);
    expect(find.byType(FxCard), findsNothing);
    expect(tester.getTopLeft(hint).dy,
        lessThan(tester.getTopLeft(row).dy + 125));

    await tester.tap(row);
    await tester.pumpAndSettle();
    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    expect(tester.widget<TaskDetailSheet>(detail).sidePanel, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 700dp 中等宽度也不全量构建 250 条任务',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final tasks = List<Task>.generate(
      250,
      (index) => Task(
        id: index + 1,
        listId: 1,
        title: '中等宽度任务 ${index + 1}',
        priority: 'none',
        isCompleted: false,
        createdAt: now,
      ),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            tasks, tasks, <Task>[], <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.row.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.row.250')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('任务页 360dp 保持紧凑卡片与可点击任务行', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final task = Task(
      id: 7,
      listId: 1,
      title: '日常阅读',
      priority: 'none',
      isCompleted: false,
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[task],
            <Task>[task],
            <Task>[],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final shell = find.byKey(const ValueKey('tasks.mobile.shell.7'));
    expect(shell, findsOneWidget);
    expect(
      tester.getSize(shell).width,
      closeTo(360 - SlowlightSpacing.xxxl * 2, 1),
    );
    final row = find.byKey(const ValueKey('tasks.swipe.7'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('P04 Windows 新建优先选收集箱，不用数据返回首个清单', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1100, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final nonInbox = TodoList(
      id: 17, name: '项目', color: '#445566', createdAt: now,
    );
    final inbox = TodoList(
      id: 28, name: '收集箱', color: '#778899', isInbox: true,
      createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        taskDataLoader: () async => <dynamic>[
          <Task>[], <Task>[], <Task>[],
        ],
        listsLoader: () async => [nonInbox, inbox],
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FxButton, '新建任务'));
    await tester.pumpAndSettle();
    final options = tester.widgetList<FxChoiceChip>(find.byType(FxChoiceChip))
        .where((choice) => choice.label.contains('收集箱')).toList();
    expect(options.length, 1);
    expect(options.single.selected, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P04 Android 任务行保留四象限优先级文字而非仅靠色条', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final high = Task(
      id: 501, listId: 1, title: '需要优先处理的事',
      priority: 'urgent_important',
      isCompleted: false, createdAt: now,
    );
    final low = Task(
      id: 502, listId: 1, title: '普通任务',
      priority: 'none',
      isCompleted: false, createdAt: now,
    );
    final inbox = TodoList(
      id: 1, name: '收集箱', isInbox: true,
      color: '#8db5a0', createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(
        dataLoader: () async => <dynamic>[
          [high, low], [high, low], <Task>[], [inbox],
        ],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('需要优先处理的事'), findsOneWidget);
    expect(find.textContaining('重要 · 紧急'), findsOneWidget);
    expect(find.text('普通任务'), findsOneWidget);
    expect(find.textContaining('不重要 · 不紧急'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
