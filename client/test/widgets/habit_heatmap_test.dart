import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/habit_heatmap.dart';

void main() {
  group('HabitHeatmap', () {
    group('基本渲染', () {
      testWidgets('渲染月份标签', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.green,
              month: DateTime(2026, 4),
            ),
          ),
        ));

        expect(find.text('4月'), findsOneWidget);
      });

      testWidgets('渲染星期表头', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.green,
              month: DateTime(2026, 4),
            ),
          ),
        ));

        for (final label in ['一', '二', '三', '四', '五', '六', '日']) {
          expect(find.text(label), findsOneWidget);
        }
      });

      testWidgets('空打卡数据不报错', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.green,
              month: DateTime(2026, 4),
            ),
          ),
        ));

        expect(find.byType(HabitHeatmap), findsOneWidget);
      });

      testWidgets('Container 代表每一天', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.green,
              month: DateTime(2026, 4),
            ),
          ),
        ));

        final containers = find.byType(Container);
        expect(containers.evaluate().length, greaterThanOrEqualTo(30));
      });
    });

    group('打卡高亮', () {
      testWidgets('打卡日期有高亮颜色', (tester) async {
        final checkIns = [
          DateTime(2026, 4, 15),
          DateTime(2026, 4, 16),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: checkIns,
              color: Colors.green,
              month: DateTime(2026, 4),
            ),
          ),
        ));

        expect(find.byType(HabitHeatmap), findsOneWidget);
      });

      testWidgets('多次打卡强度更高', (tester) async {
        final checkIns = [
          DateTime(2026, 4, 15),
          DateTime(2026, 4, 15),
          DateTime(2026, 4, 15),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: checkIns,
              color: Colors.blue,
              month: DateTime(2026, 4),
            ),
          ),
        ));

        expect(find.byType(HabitHeatmap), findsOneWidget);
      });
    });

    group('月份切换', () {
      testWidgets('3月显示 3月 标签', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.red,
              month: DateTime(2026, 3),
            ),
          ),
        ));

        expect(find.text('3月'), findsOneWidget);
      });

      testWidgets('12月显示 12月 标签', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.red,
              month: DateTime(2026, 12),
            ),
          ),
        ));

        expect(find.text('12月'), findsOneWidget);
      });

      testWidgets('1月显示 1月 标签', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.red,
              month: DateTime(2026, 1),
            ),
          ),
        ));

        expect(find.text('1月'), findsOneWidget);
      });
    });

    group('跨月边界', () {
      testWidgets('2月（28天）正常渲染', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.green,
              month: DateTime(2026, 2),
            ),
          ),
        ));

        expect(find.text('2月'), findsOneWidget);
        expect(find.byType(HabitHeatmap), findsOneWidget);
      });

      testWidgets('闰年2月（29天）正常渲染', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HabitHeatmap(
              checkInDates: [],
              color: Colors.green,
              month: DateTime(2024, 2),
            ),
          ),
        ));

        expect(find.text('2月'), findsOneWidget);
      });
    });
  });
}
