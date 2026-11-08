import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/pomodoro_screen.dart';
import 'package:slowlight/repositories/session_repository.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

class _InactiveSessionRepository extends SessionRepository {
  @override
  Future<Map<String, dynamic>> getActiveSession() async => {'active': false};

  @override
  Future<Map<String, dynamic>> getTodaySessionStats() async => {
        'total_work_seconds': 0,
        'work_count': 0,
      };
}

class _ControlledSessionRepository extends SessionRepository {
  final Completer<Map<String, dynamic>> initial = Completer();
  var activeReads = 0;

  @override
  Future<Map<String, dynamic>> getActiveSession() {
    activeReads++;
    if (activeReads == 1) return initial.future;
    return Future.value({'active': false});
  }

  @override
  Future<Map<String, dynamic>> getTodaySessionStats() async => {
        'total_work_seconds': 0,
        'work_count': 0,
      };
}

void main() {
  testWidgets('P07 还没核对当前活跃会话时不允许开始或更改设置', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sessions = _ControlledSessionRepository();

    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: sessions),
    ));
    await tester.pump();
    final start = tester.widget<FxButton>(
      find.widgetWithText(FxButton, '开始专注'),
    );
    expect(start.onPressed, isNull);
    expect(fxTooltipFinder('正在核对本轮专注'), findsOneWidget);

    sessions.initial.complete({'active': false});
    await tester.pumpAndSettle();
    expect(tester.widget<FxButton>(
      find.widgetWithText(FxButton, '开始专注'),
    ).onPressed, isNotNull);
    expect(sessions.activeReads, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P07 活跃会话状态未知时只允许重新核对而非开启新会话',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sessions = _ControlledSessionRepository();

    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: sessions),
    ));
    sessions.initial.completeError(StateError('server offline'));
    await tester.pumpAndSettle();

    expect(find.text('当前会话状态待核对'), findsOneWidget);
    expect(find.text('重新核对当前会话'), findsOneWidget);
    expect(find.widgetWithText(FxButton, '开始专注'), findsNothing);
    expect(fxTooltipFinder('请先核对当前专注会话'), findsOneWidget);

    await tester.tap(find.text('重新核对当前会话'));
    await tester.pumpAndSettle();
    expect(sessions.activeReads, 2);
    expect(find.widgetWithText(FxButton, '开始专注'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X10 专注设置保存后重新进入页面仍保留，取消不覆盖偏好',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    addTearDown(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
    await tester.pumpWidget(buildFxTestHost(home: PomodoroScreen(sessionRepository: _InactiveSessionRepository())));
    await tester.pumpAndSettle();

    await tester.tap(fxTooltipFinder('专注设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('45'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('slowlight_pomodoro_settings_v1');
    expect(raw, isNotNull);
    expect((jsonDecode(raw!) as Map)['workMinutes'], 45);

    await tester.tap(fxTooltipFinder('专注设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((jsonDecode(
      prefs.getString('slowlight_pomodoro_settings_v1')!,
    ) as Map)['workMinutes'], 45);

    // A new screen instance must read stored preferences, not in-memory state.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildFxTestHost(home: PomodoroScreen(sessionRepository: _InactiveSessionRepository())));
    await tester.pumpAndSettle();
    expect(find.text('45:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('14 Android 360dp/200% 字体的刻度盘自适应且文字不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: PomodoroScreen(sessionRepository: _InactiveSessionRepository()),
    ));
    await tester.pump();

    final dial = tester.widget<SizedBox>(
      find.byKey(const ValueKey('pomodoro-dial')),
    );
    expect(dial.width, lessThanOrEqualTo(312));
    expect(dial.width, greaterThan(220));
    expect(dial.width, dial.height);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('专注设置在 Android 360dp 与双倍字体下可以滚动', (tester) async {
    tester.view.physicalSize = const Size(360, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: PomodoroScreen(sessionRepository: _InactiveSessionRepository()),
    ));
    await tester.pump();
    await tester.tap(fxTooltipFinder('专注设置'));
    await tester.pumpAndSettle();
    expect(find.text('专注时长'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('专注设置关闭后不会残留遮罩', (tester) async {
    await tester.pumpWidget(buildFxTestHost(home: PomodoroScreen(sessionRepository: _InactiveSessionRepository())));
    await tester.pump();
    final baselineBarriers = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(fxTooltipFinder('专注设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ModalBarrier).evaluate().length,
      baselineBarriers,
    );
    await disposeFxTestHost(tester);
  });
}
