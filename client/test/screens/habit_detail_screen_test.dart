import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/habit_detail_screen.dart';
import 'package:slowlight/models/habit.dart';

void main() {
  group('HabitDetailScreen', () {
    final testHabit = Habit(
      id: 1,
      userId: 1,
      name: '早起',
      icon: '🌅',
      color: '#52c41a',
      frequency: 'daily',
      targetDays: 0,
      streakCount: 5,
      createdAt: DateTime(2026),
    );

    group('初始状态', () {
      testWidgets('渲染不崩溃', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump();
        expect(find.byType(HabitDetailScreen), findsOneWidget);
      });

      testWidgets('显示 AppBar 标题（图标+名称）', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump();
        expect(find.text('🌅 早起'), findsOneWidget);
      });

      testWidgets('显示返回按钮', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump();
        expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      });

      testWidgets('加载完成后隐藏加载指示器', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets('Scaffold 存在', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump();
        expect(find.byType(Scaffold), findsOneWidget);
      });
    });

    group('API 失败后', () {
      testWidgets('不崩溃', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(HabitDetailScreen), findsOneWidget);
      });

      testWidgets('AppBar 仍在', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('🌅 早起'), findsOneWidget);
      });
    });

    group('不同习惯数据', () {
      testWidgets('长名称习惯不崩溃', (tester) async {
        final longNameHabit = Habit(
          id: 2,
          userId: 1,
          name: '每天阅读至少30分钟的书籍',
          icon: '📖',
          color: '#1890ff',
          frequency: 'daily',
          targetDays: 30,
          streakCount: 10,
          createdAt: DateTime(2026),
        );

        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: longNameHabit),
        ));
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('📖 每天阅读至少30分钟的书籍'), findsOneWidget);
      });

      testWidgets('streakCount=0 的习惯不崩溃', (tester) async {
        final newHabit = Habit(
          id: 3,
          userId: 1,
          name: '运动',
          icon: '💪',
          color: '#ff6600',
          frequency: 'daily',
          targetDays: 0,
          streakCount: 0,
          createdAt: DateTime(2026),
        );

        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: newHabit),
        ));
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(HabitDetailScreen), findsOneWidget);
      });
    });

    group('导航', () {
      testWidgets('返回按钮可点击不崩溃', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: HabitDetailScreen(habit: testHabit),
        ));
        await tester.pump();

        await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
        await tester.pump();
      });
    });
  });
}
