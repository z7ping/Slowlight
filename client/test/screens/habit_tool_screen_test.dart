import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';

import '../support/fx_test_host.dart';

class _EmptyHabitRepo extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [];
}

void main() {
  testWidgets('09 Android 360dp 普通字体的习惯数与添加操作同排', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _EmptyHabitRepo())),
    ));
    await tester.pumpAndSettle();

    final summary = tester.getRect(find.text('0 个习惯'));
    final action = tester.getRect(find.text('添加习惯'));
    expect((summary.center.dy - action.center.dy).abs(), lessThan(24));
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
}
