import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/quadrant_screen.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

Task _task(int id, String title, String priority) => Task(
      id: id,
      listId: 1,
      title: title,
      priority: priority,
      isCompleted: false,
      createdAt: DateTime(2026, 10, 16),
    );

Future<QuadrantData> _loadTasks(List<Task> tasks) async => (
      tasks: tasks,
      lists: [
        TodoList(
          id: 1,
          name: '工作',
          color: '#1890ff',
          createdAt: DateTime(2026, 10, 16),
        ),
      ],
    );

void main() {
  testWidgets('P06 四象限刷新挂起时保留现有网格与任务', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final waiting = Completer<QuadrantData>();
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: QuadrantScreen(
        dataLoader: () => ++reads == 1
            ? _loadTasks([_task(41, '已有象限任务', 'important')])
            : waiting.future,
      )),
    ));
    await tester.pumpAndSettle();

    final refreshing = tester.widget<FxRefresh>(
      find.byType(FxRefresh),
    ).onRefresh();
    await tester.pump();
    expect(reads, 2);
    expect(find.text('已有象限任务'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);

    waiting.completeError(StateError('临时离线'));
    await refreshing;
    await tester.pumpAndSettle();
    expect(find.text('已有象限任务'), findsOneWidget);
    expect(find.byKey(const ValueKey('quadrant-load-error')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P06 旧刷新迟到不覆盖较新的四象限任务', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final oldResult = Completer<QuadrantData>();
    final latestResult = Completer<QuadrantData>();
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: QuadrantScreen(
        dataLoader: () {
          switch (++reads) {
            case 1:
              return _loadTasks([_task(51, '初始任务', 'urgent')]);
            case 2:
              return oldResult.future;
            default:
              return latestResult.future;
          }
        },
      )),
    ));
    await tester.pumpAndSettle();
    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    final stale = refresh.onRefresh();
    final latest = refresh.onRefresh();
    await tester.pump();

    latestResult.complete(await _loadTasks([_task(52, '最新任务', 'important')]));
    await latest;
    await tester.pump();
    expect(find.text('最新任务'), findsOneWidget);
    oldResult.complete(await _loadTasks([_task(53, '过期任务', 'none')]));
    await stale;
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(find.text('最新任务'), findsOneWidget);
    expect(find.text('过期任务'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 四象限优先级传入统一任务创建 Sheet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(dataLoader: () => _loadTasks([])),
      ),
    ));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('quadrant-add-urgent_important'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    final draft = tester.widget<TaskDetailSheet>(detail).task;
    expect(draft.priority, 'urgent_important');
    expect(draft.dueDate, isNull);
    expect(find.text('新建任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 360dp 沿用 2×2 四象限且 none 是不重要不紧急', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(
          dataLoader: () => _loadTasks([_task(7, '传智面试录课', 'none')]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    expect(find.text('不重要 · 不紧急'), findsOneWidget);
    expect(find.text('未设优先级'), findsNothing);
    expect(find.text('传智面试录课'), findsOneWidget);
    expect(fxTooltipFinder('移动到其他象限'), findsNothing);
    await tester.longPress(find.text('传智面试录课'));
    await tester.pumpAndSettle();
    expect(find.text('「传智面试录课」移动到…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 移动象限只预填编辑器，保存前不更改源任务', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final task = _task(10, '需要确认的事项', 'urgent_important');
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(dataLoader: () => _loadTasks([task])),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('需要确认的事项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重要 · 不紧急').last);
    await tester.pumpAndSettle();

    final editorFinder = find.byType(TaskDetailSheet);
    expect(editorFinder, findsOneWidget);
    final editor = tester.widget<TaskDetailSheet>(editorFinder);
    expect(editor.initialPriority, 'important');
    expect(editor.task.priority, 'urgent_important');
    expect(task.priority, 'urgent_important');
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 四象限填满可用高度且空格只有一个添加入口', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(dataLoader: () => _loadTasks([])),
      ),
    ));
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    const cellWidth = (360.0 - 12 * 2 - 12) / 2;
    expect(cellWidth / delegate.childAspectRatio, greaterThan(400));
    expect(find.byKey(const ValueKey('quadrant-add-urgent_important')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('quadrant-add-important')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('quadrant-add-urgent')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('quadrant-add-none')),
        findsOneWidget);
    expect(fxTooltipFinder('在重要 · 紧急添加任务'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 多于两条可查看全部，第三条没有丢失', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(
          dataLoader: () => _loadTasks([
            _task(1, '第一条', 'urgent_important'),
            _task(2, '第二条', 'urgent_important'),
            _task(3, '第三条', 'urgent_important'),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('查看全部'), findsOneWidget);
    expect(find.text('第三条'), findsNothing);
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('第三条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 大字体窄屏退化为单列完整象限', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.35),
          ),
          child: QuadrantScreen(dataLoader: () => _loadTasks([])),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P06 Windows 右键移动仅预填原任务，不直接提交', (tester) async {
    SharedPreferences.setMockInitialValues({
      'quadrant_move_hint_desktop_v1': true,
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final task = _task(86, '右键选中的任务', 'urgent_important');
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(dataLoader: () => _loadTasks([task])),
      ),
    ));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('右键选中的任务')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('「右键选中的任务」移动到…'), findsOneWidget);
    await tester.tap(find.text('重要 · 不紧急').last);
    await tester.pumpAndSettle();

    final editor = tester.widget<TaskDetailSheet>(
      find.byType(TaskDetailSheet),
    );
    expect(editor.initialPriority, 'important');
    expect(editor.task.priority, 'urgent_important');
    expect(task.priority, 'urgent_important');
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P06 菜单键与 Shift+F10 在任务焦点上复用同一移动选择',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'quadrant_move_hint_mobile_v1': true,
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final task = _task(87, '键盘焦点任务', 'urgent_important');
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(dataLoader: () => _loadTasks([task])),
      ),
    ));
    await tester.pumpAndSettle();

    Focus.of(tester.element(find.text('键盘焦点任务'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('「键盘焦点任务」移动到…'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);
    expect(task.priority, 'urgent_important');

    Focus.of(tester.element(find.text('键盘焦点任务'))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('「键盘焦点任务」移动到…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P06 移动引导仅在首次有任务时写入本机标记', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(dataLoader: () => _loadTasks([])),
      ),
    ));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('quadrant_move_hint_mobile_v1'), isNull);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(
          key: const ValueKey('populated-quadrants'),
          dataLoader: () => _loadTasks([
            _task(88, '首次可移动的任务', 'urgent'),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(preferences.getBool('quadrant_move_hint_mobile_v1'), isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('四象限读取失败时显示可重试错误，而不是四个空象限', (tester) async {
    var attempts = 0;
    Future<QuadrantData> load() async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return _loadTasks([]);
    }

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: QuadrantScreen(dataLoader: load)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quadrant-load-error')), findsOneWidget);
    expect(find.text('暂时无法加载四象限'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('quadrant-load-error')), findsNothing);
    expect(find.text('不重要 · 不紧急'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
