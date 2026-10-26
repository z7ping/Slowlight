import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/calendar_record.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/calendar_screen.dart';
import 'package:slowlight/screens/task_tool_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('任务首次接口失败不被误判为无任务，重试后真实空态出现', (tester) async {
    var calls = 0;
    tester.view.physicalSize = const Size(1000, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataLoader: () async {
        if (calls++ == 0) throw StateError('模拟读取失败');
        return <dynamic>[
          <Task>[], <Task>[], <Task>[], <TodoList>[],
        ];
      })),
    ));
    await tester.pumpAndSettle();
    expect(find.text('任务读取失败'), findsOneWidget);
    expect(find.text('这里暂时没有任务'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('任务读取失败'), findsNothing);
    expect(find.text('这里暂时没有任务'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('日历整月失败不会生成空月份，重新加载成功后恢复月格', (tester) async {
    final month = DateTime(2026, 8, 1);
    var calls = 0;
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: month,
        initialSelectedDate: DateTime(2026, 8, 20),
        monthLoader: (requested) async {
          if (calls++ == 0) throw Exception('接口超时');
          return CalendarMonthData(month: requested, records: const []);
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('当前月份读取失败'), findsOneWidget);
    expect(find.text('未能加载这一个月的记录；请重试，不代表没有安排。'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('当前月份读取失败'), findsNothing);
    expect(find.text('2026 年 8 月'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('跨月失败不展示上个月成功读取的任务', (tester) async {
    final month = DateTime(2026, 8, 1);
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: CalendarScreen(
        initialMonth: month,
        initialSelectedDate: DateTime(2026, 8, 20),
        monthLoader: (requested) async {
          if (requested.month == 9) throw Exception('9月不可用');
          return CalendarMonthData(
            month: requested,
            records: [
              CalendarRecord(
                id: 'aug-task', type: CalendarRecordType.task,
                kind: CalendarRecordKind.plan,
                date: DateTime(2026, 8, 20), title: '八月的任务',
              ),
            ],
          );
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('八月的任务'), findsWidgets);
    await tester.tap(fxTooltipFinder('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('当前月份读取失败'), findsOneWidget);
    expect(find.text('八月的任务'), findsNothing);
    await disposeFxTestHost(tester);
  });
}
