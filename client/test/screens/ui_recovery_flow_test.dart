import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/habit_log.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';
import 'package:slowlight/screens/today_review_screen.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/dashboard/dashboard_body.dart';
import 'package:slowlight/widgets/habit_checkin_dialog.dart';
import 'package:slowlight/widgets/habit_checkin_flow.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';

import '../support/fx_test_host.dart';

Habit sample({int id = 1, String name = '喝水', bool count = false}) => Habit(
      id: id,
      userId: 1,
      name: name,
      recordType: count ? 'count' : 'check',
      recordTimeLabel: count ? '实际时间' : '',
      allowMultiplePerDay: true,
      checkedToday: true,
      createdAt: DateTime(2020),
    );

class _History extends HabitRepository {
  bool fail = true;
  String? requestedMonth = '未查询';
  @override
  Future<List<Habit>> getAll() async => [sample()];
  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async {
    requestedMonth = month;
    if (fail) throw StateError('读取失败');
    return List.generate(
        5,
        (i) => HabitLog(
            id: i + 1,
            habitId: habitId,
            date: '2020-01-0${i + 1}',
            period: '',
            durationMin: 0,
            note: '历史记录 $i',
            createdAt: DateTime(2020, 1, i + 1)));
  }
}

class _PartialHabits extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [sample(), sample(id: 2, name: '读取失败')];
  @override
  Future<List<HabitLog>> logs(int habitId, {String? month}) async {
    if (habitId == 2) throw StateError('日志不可读');
    final now = DateTime.now();
    return [
      HabitLog(
          id: 1,
          habitId: 1,
          date:
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          period: '',
          durationMin: 0,
          note: '已读取的事实',
          createdAt: now)
    ];
  }
}

class _Reflections extends ReflectionRepository {
  @override
  Future<List<ReflectionEntry>> recent({int limit = 20}) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fontPath = String.fromEnvironment('SLOWLIGHT_UI_FONT');
  const fontFamily = fontPath == '' ? null : 'SlowlightEvidence';
  setUpAll(() async {
    if (fontPath == '') return;
    final loader = FontLoader(fontFamily!);
    loader.addFont(File(fontPath).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('SLOWLIGHT_UI_EVIDENCE')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('ui-recovery-capture')));
    await tester.runAsync(() async {
      final snapshot = await boundary.toImage(pixelRatio: 1);
      final data = await snapshot.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-recovery-evidence/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      snapshot.dispose();
    });
  }

  Future<void> mount(WidgetTester tester, Widget child,
      {TargetPlatform platform = TargetPlatform.windows,
      double scale = 1,
      bool dark = false}) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = platform == TargetPlatform.android
        ? const Size(360, 800)
        : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      theme: dark ? AppTheme.darkTheme(fontFamily: fontFamily) : AppTheme.lightTheme(fontFamily: fontFamily),
      shadTheme: dark ? shadDarkTheme(fontFamily) : shadLightTheme(fontFamily),
      builder: (context, child) => RepaintBoundary(
          key: const ValueKey('ui-recovery-capture'),
          child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!)),
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      testWidgets('计数与实际时间提交失败保留输入，重试沿用同一标识：$platform 暗色=$dark',
          (tester) async {
        final calls = <Map<String, dynamic>>[];
        await mount(
            tester,
            Builder(
                builder: (context) => FxButton(
                      label: '开始记录',
                      onPressed: () => recordHabit(context,
                          habit: sample(count: true), submit: (value) async {
                        calls.add(value);
                        if (calls.length == 1) throw StateError('响应中断');
                      }),
                    )),
            platform: platform,
            dark: dark,
            scale: platform == TargetPlatform.android ? 1.3 : 1.25);
        await tester.tap(find.text('开始记录'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(FxInput).first, '2');
        await tester.enterText(find.byType(FxInput).last, '保留这次输入');
        await tester.ensureVisible(find.text('确认打卡'));
        await tester.tap(find.text('确认打卡'));
        await tester.pumpAndSettle();
        expect(find.text('保留这次输入'), findsOneWidget);
        expect(find.textContaining('保存结果未确认'), findsOneWidget);
        await capture(
            tester, '${platform.name}-${dark ? 'dark' : 'light'}-count-failed');
        await tester.ensureVisible(find.text('重试保存'));
        await tester.tap(find.text('重试保存'));
        await tester.pumpAndSettle();
        expect(calls.length, 2);
        expect(calls[0], calls[1]);
        expect(calls.last['count_value'], 2);
        expect(calls.last['occurred_at'], isNotNull);
        expect(calls.last['client_key'], isNotEmpty);
        expect(find.byType(HabitCheckinDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

  testWidgets('习惯创建保存时阻止退出和重复提交，失败后保留表单', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await mount(
        tester,
        Builder(
            builder: (context) => FxButton(
                  label: '编辑',
                  onPressed: () =>
                      HabitEditorDialog.show(context, onSubmit: (_) {
                    calls++;
                    return pending.future;
                  }),
                )));
    await tester.tap(find.text('编辑'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(FxInput).first, '不能丢的习惯');
    await tester.tap(find.text('创建习惯'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('保存中…'), findsOneWidget);
    final scopes = tester.widgetList<PopScope>(find.byType(PopScope));
    expect(scopes.any((scope) => !scope.canPop), isTrue);
    pending.completeError(StateError('保存响应未知'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('不能丢的习惯'), findsOneWidget);
    expect(find.textContaining('保存结果未确认'), findsOneWidget);
    expect(find.text('已核对，允许重新保存'), findsOneWidget);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('明细读取失败不冒充空，重试后可以查看前三条以外的历史', (tester) async {
    final repository = _History();
    await mount(tester, HabitToolScreen(repository: repository));
    await tester.tap(find.byKey(const ValueKey('habits.details.1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前数量未知'), findsOneWidget);
    expect(find.text('还没有记录。'), findsNothing);
    repository.fail = false;
    await tester.ensureVisible(find.text('重试加载记录'));
    await tester.tap(find.text('重试加载记录'));
    await tester.pumpAndSettle();
    expect(repository.requestedMonth, isNull);
    expect(find.text('历史记录 4'), findsNothing);
    await tester.ensureVisible(find.text('查看全部 5 条记录'));
    await tester.tap(find.text('查看全部 5 条记录'));
    await tester.pumpAndSettle();
    expect(find.text('历史记录 4'), findsOneWidget);
    await capture(tester, 'windows-history-expanded');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('回顾保留成功习惯事实并标出读取失败的明细', (tester) async {
    await mount(
        tester,
        TodayReviewScreen(
          reflectionRepository: _Reflections(),
          habitRepository: _PartialHabits(),
          reviewLoader: () async =>
              {'facts': {}, 'questions': [], 'patterns': {}},
        ));
    expect(find.textContaining('习惯「读取失败」明细'), findsOneWidget);
    expect(find.text('今天还没有留下行为记录'), findsNothing);
    expect(find.textContaining('已读取的事实'), findsOneWidget);
    await capture(tester, 'windows-review-partial');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('任务加载失败不遮蔽健康习惯，不显示空任务引导', (tester) async {
    await mount(
        tester,
        DashboardBody(
          tasks: const [],
          habits: [sample()],
          tasksError: true,
          dimensionLoader: () async => {'dimensions': []},
          reviewLoader: () async => {'questions': [], 'facts': {}},
          timelineLoader: () async => [],
        ));
    expect(find.text('任务暂时无法加载，当前数量未知。'), findsOneWidget);
    expect(find.text('今天暂时没有任务'), findsNothing);
    expect(find.text('喝水'), findsOneWidget);
    await capture(tester, 'windows-dashboard-partial');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
