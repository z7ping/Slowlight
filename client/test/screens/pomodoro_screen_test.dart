import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/pomodoro_screen.dart';
import 'package:slowlight/repositories/session_repository.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

class _ExpiredWorkSessionRepository extends SessionRepository {
  final DateTime startedAt =
      DateTime.now().toUtc().subtract(const Duration(minutes: 26));
  bool naturalEndReceived = false;
  bool startedBreak = false;

  Map<String, dynamic> get expiredWork => {
        'id': 311,
        'session_type': 'work',
        'target_minutes': 25,
        'started_at': startedAt.toIso8601String(),
        'paused_at': null,
        'paused_duration_seconds': 0,
        'revision': 0,
      };

  @override
  Future<Map<String, dynamic>> getActiveSession() async => {
        'active': true,
        'session': expiredWork,
        'completed_work_rounds': 0,
      };

  @override
  Future<Map<String, dynamic>> getTodaySessionStats() async => {
        'total_work_seconds': 0,
        'work_count': 0,
      };

  @override
  Future<Map<String, dynamic>> pauseSession(int sessionId, int revision) async {
    if (sessionId != 311 || revision != 0) {
      throw StateError('pause target changed');
    }
    return {
      'session': {
        ...expiredWork,
        'revision': 1,
        'paused_at': DateTime.now().toUtc().toIso8601String(),
      }
    };
  }

  @override
  Future<Map<String, dynamic>> endSession({
    int? systemTagId,
    int? sessionId,
    int? expectedRevision,
    bool naturallyCompleted = false,
  }) async {
    if (sessionId != 311 || expectedRevision != 1 || !naturallyCompleted) {
      throw StateError('unverified natural end request');
    }
    naturalEndReceived = true;
    return {
      'session': {'id': 311},
      'completed_work_rounds': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> startSession(
    String sessionType, {
    int? taskId,
    int? targetMinutes,
    String device = 'desktop',
    bool requireInactive = false,
  }) async {
    if (sessionType != 'break' || targetMinutes != 5 || !requireInactive) {
      throw StateError('next round must be an inactive-only short break');
    }
    startedBreak = true;
    return {
      'session': {
        'id': 312,
        'session_type': 'break',
        'target_minutes': 5,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'paused_at': null,
        'paused_duration_seconds': 0,
        'revision': 0,
      }
    };
  }
}

class _UnavailableStatsSessionRepository extends SessionRepository {
  @override
  Future<Map<String, dynamic>> getActiveSession() async => {
        'active': false,
        'completed_work_rounds': 3,
      };

  @override
  Future<Map<String, dynamic>> getTodaySessionStats() async {
    throw StateError('统计读取失败');
  }
}

class _VerifiedCycleRepository extends SessionRepository {
  @override
  Future<Map<String, dynamic>> getActiveSession() async => {
        'active': false,
        'completed_work_rounds': 3,
      };

  @override
  Future<Map<String, dynamic>> getTodaySessionStats() async => {
        'total_work_seconds': 0,
        'work_count': 0,
      };
}

class _GuardedStartRepository extends SessionRepository {
  bool? receivedRequireInactive;

  @override
  Future<Map<String, dynamic>> getActiveSession() async => {
        'active': false,
        'completed_work_rounds': 0,
      };

  @override
  Future<Map<String, dynamic>> getTodaySessionStats() async => {
        'total_work_seconds': 0,
        'work_count': 0,
      };

  @override
  Future<Map<String, dynamic>> startSession(
    String sessionType, {
    int? taskId,
    int? targetMinutes,
    String device = 'desktop',
    bool requireInactive = false,
  }) async {
    receivedRequireInactive = requireInactive;
    return {
      'session': {
        'id': 101,
        'session_type': sessionType,
        'target_minutes': targetMinutes ?? 25,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'paused_at': null,
        'paused_duration_seconds': 0,
        'revision': 0,
      }
    };
  }
}

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

class _RemoteEndedLinkedSessionRepository extends SessionRepository {
  int reads = 0;

  @override
  Future<Map<String, dynamic>> getActiveSession() async {
    reads++;
    if (reads > 1) return {'active': false};
    return {
      'active': true,
      'session': {
        'id': 761,
        'session_type': 'work',
        'task_id': 919,
        'target_minutes': 25,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'paused_at': DateTime.now().toUtc().toIso8601String(),
        'paused_duration_seconds': 0,
        'revision': 1,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getTodaySessionStats() async => {
        'total_work_seconds': 0,
        'work_count': 0,
      };
}

void main() {
  testWidgets('X10 另一设备结束原会话后不再携带旧任务关联', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = _RemoteEndedLinkedSessionRepository();
    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: repo),
    ));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.reads, greaterThanOrEqualTo(2));
    await tester.tap(fxTooltipFinder('专注设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<FxSelect<int>>(find.byType(FxSelect<int>)).value, 0);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P07 自动下一轮不被标签弹窗阻断且经过服务端确认', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = _ExpiredWorkSessionRepository();

    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: repository),
    ));
    await tester.pumpAndSettle();
    // App re-entered after the persisted target expired; auto mode settles
    // the old round and starts its short break without extra user action.
    expect(repository.naturalEndReceived, isTrue);
    expect(repository.startedBreak, isTrue);
    expect(find.text('开始休息'), findsNothing);
    expect(find.textContaining('本周期 1/4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P07 关闭自动下一轮后过期会话等待明确保存', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'slowlight_pomodoro_settings_v1': jsonEncode({
        'workMinutes': 25,
        'autoStartNext': false,
        'soundEnabled': false,
      }),
    });
    final repository = _ExpiredWorkSessionRepository();

    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: repository),
    ));
    await tester.pumpAndSettle();
    expect(repository.naturalEndReceived, isFalse);
    expect(repository.startedBreak, isFalse);
    expect(find.text('完成并保存本轮'), findsOneWidget);
    expect(find.text('本轮到时 · 待保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P07 今日统计失败不伪报零，保留可确认的自然轮次', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(
        sessionRepository: _UnavailableStatsSessionRepository(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('今日专注统计暂不可用'), findsOneWidget);
    expect(find.textContaining('本周期 3/4'), findsOneWidget);
    expect(find.textContaining('今日第 0 轮'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P07 只展示来源确认的连续轮次，退出页面后可恢复', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = _VerifiedCycleRepository();

    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('本周期 3/4'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('本周期 3/4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P07 新轮请求携带禁止覆盖其他设备活动会话的条件', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = _GuardedStartRepository();

    await tester.pumpWidget(buildFxTestHost(
      home: PomodoroScreen(sessionRepository: repository),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始专注'));
    await tester.pump();
    expect(repository.receivedRequireInactive, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

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
