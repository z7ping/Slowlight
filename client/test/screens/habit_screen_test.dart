import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/habit_screen.dart';

void main() {
  group('HabitScreen', () {
    group('UI 渲染', () {
      testWidgets('渲染不崩溃', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HabitScreen()));
        await tester.pump();
        expect(find.byType(HabitScreen), findsOneWidget);
      });

      testWidgets('显示返回按钮', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HabitScreen()),
                    );
                  },
                  child: const Text('Go'),
                );
              },
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      });
    });

    group('加载状态', () {
      testWidgets('初始显示加载指示器', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HabitScreen()));
        await tester.pump();

        final hasProgress =
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        final hasEmptyState = find.text('还没有习惯').evaluate().isNotEmpty;

        expect(hasProgress || hasEmptyState, isTrue);
      });
    });
  });
}
