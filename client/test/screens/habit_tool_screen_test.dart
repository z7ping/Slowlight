import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/habit_log.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';
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

void main() {
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
    expect(find.text('0 个习惯'), findsOneWidget);
    expect(find.text('今日已记录 0/0'), findsOneWidget);
    expect(find.text('添加习惯'), findsOneWidget);
    expect(find.text('创建第一个习惯'), findsOneWidget);
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
