import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/screens/habit_detail_screen.dart';
import 'package:slowlight/widgets/habit_checkin_dialog.dart';
import 'package:slowlight/ui/app_theme.dart';

import '../support/fx_test_host.dart';

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

  test('08 补卡日期来自 date 而不是记录的创建时间', () {
    final date = habitLogCalendarDay({
      'date': '2026-10-05',
      'created_at': '2026-10-16T08:14:00',
    });
    expect(date, DateTime(2026, 10, 5));
  });

  testWidgets('08 历史详情使用主题背景并且读取失败可重试', (tester) async {
    var attempts = 0;
    Future<Map<String, dynamic>> load(int habitId, String month) async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return {
        'logs': <Map<String, dynamic>>[
          {
            'id': 1,
            'date': '2026-10-05',
            'created_at': '2026-10-16T08:14:00',
            'duration_min': 25,
            'note': '补卡',
          },
        ],
      };
    }

    await tester.pumpWidget(buildFxTestHost(
      theme: AppTheme.darkTheme(),
      home: HabitDetailScreen(
        habit: habit(id: 3, name: '读书', streakCount: 1),
        logsLoader: load,
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, isNull);
    expect(find.text('打卡记录暂时不可用'), findsOneWidget);

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('打卡记录暂时不可用'), findsNothing);
    expect(find.textContaining('2026-10-05'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 习惯打卡主按钮填满表单宽度', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitCheckinDialog(
        habit: habit(id: 11, name: '读书', streakCount: 0),
      )),
    ));
    await tester.pump();
    final action = find.byKey(const ValueKey('habit-checkin-primary-action'));
    expect(action, findsOneWidget);
    expect(tester.getSize(action).width, greaterThan(290));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  group('HabitDetailScreen 稳定性', () {
    testWidgets('数据加载失败时页面仍保持可用', (tester) async {
      await tester.pumpWidget(
        buildFxTestHost(
          theme: AppTheme.lightTheme(),
          home: HabitDetailScreen(
            habit: habit(id: 1, name: '早起', streakCount: 5),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(HabitDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('长名称和零连续天数不产生布局异常', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildFxTestHost(
          theme: AppTheme.lightTheme(),
          home: HabitDetailScreen(
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
      await disposeFxTestHost(tester);
    });
  });
}
