import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';
import 'package:slowlight/screens/home_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/data_service.dart';

import '../helpers/isolated_test_db.dart';
import '../support/fx_test_host.dart';

class _CheckinHabitRepository extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [
        Habit(
          id: 1,
          userId: 1,
          name: '每日阅读',
          showCheckinDialog: true,
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
}

void main() {
  final tokens = jsonDecode(
    File('test/fixtures/design/android_bottom_sheet.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final radius = (tokens['UI-16']['topCornerRadiusDp'] as num).toDouble();
  final dragRegion = (tokens['UI-17']['dragStartRegionDp'] as num).toDouble();

  Future<void> advanceSheetAnimation(WidgetTester tester) async {
    // The habit card keeps its progress spinner active until the sheet closes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  setUpAll(() async {
    await useIsolatedTestDb('android_sheet_entry_contract');
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
    FlutterSecureStorage.setMockInitialValues({});
    await DataModeManager().setLocal();
    if ((await DataService().getLists()).isEmpty) {
      await DataService().createList(name: '收集箱', isInbox: true);
    }
  });

  final entries = [
    (
      name: '今天 / 任务新建',
      screen: const HomeScreen(),
      trigger: fxTooltipFinder('快速添加任务（按住可拖动）'),
    ),
    (
      name: '习惯 / 记录今天',
      screen: Scaffold(
        body: HabitToolScreen(
          repository: _CheckinHabitRepository(),
          todayLogCountLoader: () async => 0,
        ),
      ),
      trigger: find.byKey(const ValueKey('habits.today.1')),
    ),
    (
      name: '今天 / 记录观察',
      screen: const HomeScreen(),
      trigger: fxTooltipFinder('记录观察'),
    ),
  ];

  for (final entry in entries) {
    testWidgets('Android ${entry.name} UI-16/17 实际入口', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(buildFxTestHost(home: entry.screen));
        await tester.pumpAndSettle();
        await tester.tap(entry.trigger);
        await advanceSheetAnimation(tester);

        final grip = find.byKey(const ValueKey('fx.sheet.dragHandle'));
        expect(grip, findsOneWidget);
        final paintedSurface = find
            .descendant(
              of: fxDialogSurfaceFinder(),
              matching: find.byType(DecoratedBox),
            )
            .first;
        final actual = tester.widget<DecoratedBox>(paintedSurface).decoration
            as BoxDecoration;
        final corners = actual.borderRadius?.resolve(TextDirection.ltr);
        expect(
          [corners?.topLeft, corners?.topRight],
          [Radius.circular(radius), Radius.circular(radius)],
          reason: '${entry.name} UI-16 顶部双圆角，期望 ${radius}dp',
        );

        Future<double> displacement(double offset) async {
          final bounds = tester.getRect(grip);
          final pointer = await tester.startGesture(
            Offset(bounds.center.dx, bounds.top + offset),
          );
          await pointer.moveBy(const Offset(0, 20));
          await tester.pump();
          final moved = tester.getTopLeft(grip).dy - bounds.top;
          await pointer.cancel();
          await advanceSheetAnimation(tester);
          return moved;
        }

        final inside = await displacement(dragRegion - .5);
        final outside = await displacement(dragRegion + .5);
        expect(
          [inside, outside],
          [closeTo(20, .01), closeTo(0, .01)],
          reason: '${entry.name} UI-17 拖动起始区期望 ${dragRegion}dp，'
              '距手柄顶部 ${dragRegion - .5}dp 内应移动，'
              '${dragRegion + .5}dp 外应保持原位',
        );
        expect(grip, findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeFxTestHost(tester);
      }
    });
  }
}
