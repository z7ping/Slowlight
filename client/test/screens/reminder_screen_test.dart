import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/reminder_screen.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/reminder_service.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../support/fx_test_host.dart';
import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('reminder_screen');
    SharedPreferences.setMockInitialValues({});
    await DataModeManager().setLocal();
    ReminderService().updateConfig(autoStartOnLaunch: false);
    await ReminderService().loadAll();
    expect(ReminderService().isLoaded, isTrue);
  });
  tearDownAll(() { ReminderService().dispose(); });
  group('ReminderScreen 稳定契约', () {
    testWidgets('P16 工作中延后只延长本轮，不触发休息或跳过',
        (tester) async {
      final service = ReminderService();
      service.stopAll();
      service.updateConfig(
        workMinutes: 25,
        microRestSeconds: 20,
        lockScreenMode: 'window',
        autoStartOnLaunch: false,
        allowPostponeMicro: true,
        microRestStrict: true,
      );
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      service.startWork();
      await tester.pump();
      final initial = service.remainingSeconds;
      expect(service.state, 'working');
      expect(find.text('跳过本轮'), findsNothing);
      await tester.tap(find.text('延后 5 分钟'));
      await tester.pump();
      expect(service.state, 'working');
      expect(service.remainingSeconds, initial + 300);
      expect(service.totalSeconds, 25 * 60 + 300);
      expect(service.microRestCount, 0);
      service.stopAll();
      await disposeFxTestHost(tester);
    });

    testWidgets('P16 不允许延后时，不能强制启动严格休息',
        (tester) async {
      final service = ReminderService();
      service.stopAll();
      service.updateConfig(
        workMinutes: 25,
        lockScreenMode: 'window',
        allowPostponeMicro: false,
        microRestStrict: true,
        autoStartOnLaunch: false,
      );
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      service.startWork();
      await tester.pump();
      final initial = service.remainingSeconds;
      expect(service.canPostponeUpcomingRest, isFalse);
      expect(service.postponeUpcomingRest(), isFalse);
      expect(service.remainingSeconds, initial);
      expect(service.state, 'working');
      service.stopAll();
      service.updateConfig(allowPostponeMicro: true, microRestStrict: false);
      await disposeFxTestHost(tester);
    });

    testWidgets('P16 系统挂起不把未完成小憩记为完成或跳过', (tester) async {
      final service = ReminderService();
      service.stopAll();
      service.updateConfig(
        microRestSeconds: 20,
        lockScreenMode: 'window',
        autoLoop: false,
        autoStartOnLaunch: false,
      );
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      final beforeCycle = service.cycleCount;
      final beforeMicro = service.microRestCount;
      service.startMicroRest();
      await tester.pump();
      try {
        final db = await LocalDb().database;
        await tester.runAsync(() async {
          for (var i = 0; i < 50; i++) {
            final active = await db.query('reminder_sessions',
                where: 'type = ? AND ended_at IS NULL',
                whereArgs: ['rest']);
            if (active.isNotEmpty) return;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          throw StateError('休息开始记录未写入数据库');
        });

        await tester.runAsync(() => service.debugSimulateClockInterruption(
            DateTime.now().subtract(const Duration(minutes: 3))));
        await tester.pump();
        expect(service.state, 'idle');
        expect(service.microRestCount, beforeMicro);
        expect(service.cycleCount, beforeCycle);
        final open = await db.query('reminder_sessions',
            where: 'type = ? AND ended_at IS NULL',
            whereArgs: ['rest']);
        expect(open, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        service.stopAll();
        service.updateConfig(autoLoop: true);
        await disposeFxTestHost(tester);
      }
    });

    testWidgets('P16 挂起后用户手动停止，不得被迟到自动恢复重启', (tester) async {
      final service = ReminderService();
      service.stopAll();
      service.updateConfig(
        workMinutes: 25,
        lockScreenMode: 'window',
        autoLoop: true,
        autoStartOnLaunch: false,
      );
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      service.startWork();
      await tester.pump();
      try {
        final closing = service.debugSimulateClockInterruption(
          DateTime.now().subtract(const Duration(minutes: 2)),
        );
        service.stopAll();
        await tester.runAsync(() => closing);
        await tester.pump();
        expect(service.state, 'idle');
        expect(service.remainingSeconds, 0);
        expect(tester.takeException(), isNull);
      } finally {
        service.stopAll();
        await disposeFxTestHost(tester);
      }
    });

    testWidgets('开始工作后服务进入 working 状态', (tester) async {
      final service = ReminderService();
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      await tester.pump();

      await tester.tap(find.text('开始工作'));
      await tester.pump();

      expect(service.state, 'working');

      service.stopAll();
      await tester.pump();
      expect(service.state, 'idle');
      await disposeFxTestHost(tester);
    });

    testWidgets('两次小憩后先完成下一轮工作再进入长休息', (tester) async {
      final service = ReminderService();
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      service.stopAll();
      service.updateConfig(
        workMinutes: 0, // 仅用于测试：下一次计时器触发即结束工作
        microRestSeconds: 20,
        longRestMinutes: 5,
        microRestsBeforeLong: 2,
        lockScreenMode: 'window',
        autoLoop: true,
      );

      Future<void> waitForWork() async {
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (service.state != 'working' &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pump();
        expect(service.state, 'working');
      }

      try {
        service.startWork();
        await tester.pump(const Duration(seconds: 1));
        expect(service.state, 'micro_rest');

        service.endRest();
        await waitForWork();
        expect(service.microRestCount, 1);

        await tester.pump(const Duration(seconds: 1));
        expect(service.state, 'micro_rest');

        service.endRest();
        await waitForWork();
        expect(service.microRestCount, 2);

        await tester.pump(const Duration(seconds: 1));
        expect(service.state, 'long_rest');
      } finally {
        service.stopAll();
        service.updateConfig(
          workMinutes: 25,
          microRestSeconds: 20,
          longRestMinutes: 5,
          microRestsBeforeLong: 2,
          lockScreenMode: 'fullscreen',
          autoLoop: true,
        );
        await disposeFxTestHost(tester);
      }
    });

    for (final size in [
      const Size(400, 800),
      const Size(1200, 800),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} 不产生布局异常',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
        await tester.pump();

        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }

    testWidgets('快速销毁时异步状态不会导致异常', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      await tester.pump();
      await disposeFxTestHost(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
