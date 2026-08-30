import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/screens/habit_detail_screen.dart';
import 'package:slowlight/ui/app_theme.dart';

Widget _testApp(Widget child) {
  return ShadTheme(
    data: shadLightTheme(null),
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: child,
    ),
  );
}

void main() {
  Habit habit({
    required int id,
    required String name,
    required int streakCount,
  }) {
    return Habit(
      id: id,
      userId: 1,
      name: name,
      icon: '📖',
      color: '#1890ff',
      frequency: 'daily',
      targetDays: 30,
      streakCount: streakCount,
      createdAt: DateTime(2026),
    );
  }

  group('HabitDetailScreen 稳定性', () {
    testWidgets('数据加载失败时页面仍保持可用', (tester) async {
      await tester.pumpWidget(
        _testApp(
          HabitDetailScreen(
            habit: habit(id: 1, name: '早起', streakCount: 5),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(HabitDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('长名称和零连续天数不产生布局异常', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _testApp(
          HabitDetailScreen(
            habit: habit(
              id: 2,
              name: '每天阅读至少30分钟的书籍并记录当天最重要的一个想法',
              streakCount: 0,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
    });
  });
}
