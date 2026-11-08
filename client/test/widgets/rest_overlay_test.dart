import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/services/reminder_service.dart';
import 'package:slowlight/widgets/rest_overlay.dart';

import '../support/fx_test_host.dart';
import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('rest_overlay_clock');
  });

  testWidgets('严格小憩遮罩恢复高保真结构且隐藏跳过入口', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: const RestOverlay(
          isMicroRest: true,
          restSeconds: 20,
          strict: true,
          allowPostpone: false,
        ),
      ),
    );

    expect(find.text('MICRO BREAK'), findsOneWidget);
    expect(find.byType(FxProgressRing), findsOneWidget);
    expect(find.text('严格模式 · 不可跳过'), findsOneWidget);
    expect(find.text('跳过'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeFxTestHost(tester);
  });

  testWidgets('非严格长休息保留弱化跳过与延后入口', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: const RestOverlay(
          isMicroRest: false,
          restSeconds: 300,
          strict: false,
          allowPostpone: true,
        ),
      ),
    );

    expect(find.text('LONG BREAK'), findsOneWidget);
    expect(find.text('延后 5 分钟'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('严格模式 · 不可跳过'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeFxTestHost(tester);
  });
  testWidgets('X13 严格模式仍可按独立配置延后，但绝不能跳过', (tester) async {
    final service = ReminderService();
    service.stopAll();
    service.updateConfig(
      lockScreenMode: 'window',
      microRestSeconds: 20,
      autoLoop: false,
      microRestStrict: true,
      allowPostponeMicro: true,
    );
    service.startMicroRest();
    await tester.pumpWidget(buildFxTestHost(
      home: const RestOverlay(
        isMicroRest: true,
        restSeconds: 20,
        strict: true,
        allowPostpone: true,
      ),
    ));
    try {
      await tester.pump();
      expect(find.text('严格模式 · 不可跳过'), findsOneWidget);
      expect(find.text('延后 5 分钟'), findsOneWidget);
      expect(find.text('跳过'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeFxTestHost(tester);
      service.stopAll();
      service.updateConfig(
        autoLoop: true,
        microRestStrict: false,
        allowPostponeMicro: true,
      );
    }
  });

  testWidgets('X13 配置禁止延后时保留非严格的跳过入口', (tester) async {
    final service = ReminderService();
    service.stopAll();
    service.updateConfig(
      lockScreenMode: 'window',
      microRestSeconds: 20,
      autoLoop: false,
      microRestStrict: false,
      allowPostponeMicro: false,
    );
    service.startMicroRest();
    await tester.pumpWidget(buildFxTestHost(
      home: const RestOverlay(
        isMicroRest: true,
        restSeconds: 20,
        strict: false,
        allowPostpone: false,
      ),
    ));
    try {
      await tester.pump();
      expect(find.text('延后 5 分钟'), findsNothing);
      expect(find.text('跳过'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeFxTestHost(tester);
      service.stopAll();
      service.updateConfig(autoLoop: true, allowPostponeMicro: true);
    }
  });

  testWidgets('P16 遮罩严格跟随服务计时：服务暂停后不能自行归零或完成休息',
      (tester) async {
    final service = ReminderService();
    service.stopAll();
    service.updateConfig(
      lockScreenMode: 'window',
      microRestSeconds: 20,
      autoLoop: false,
      microRestStrict: false,
      allowPostponeMicro: true,
    );
    service.startMicroRest();
    await tester.pumpWidget(buildFxTestHost(
      home: const RestOverlay(
        isMicroRest: true,
        restSeconds: 20,
        strict: false,
        allowPostpone: true,
      ),
    ));
    try {
      await tester.pump();
      expect(service.state, 'micro_rest');
      final initial = service.remainingSeconds;
      expect(find.text('00:20'), findsOneWidget);
      service.pause();
      await tester.pump(const Duration(seconds: 3));
      expect(service.remainingSeconds, initial);
      expect(find.text('00:20'), findsOneWidget);
      expect(service.state, 'micro_rest');
      service.resume();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:19'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeFxTestHost(tester);
      service.stopAll();
      service.updateConfig(autoLoop: true, microRestStrict: false);
    }
  });

}
