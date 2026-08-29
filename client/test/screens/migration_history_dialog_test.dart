import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/screens/migration_history_dialog.dart';
import 'package:slowlight/ui/theme_manager.dart';

void main() {
  testWidgets('迁移历史弹窗可以从根导航正常打开和关闭', (tester) async {
    await tester.pumpWidget(
      ShadTheme(
        data: ThemeManager.shadLight,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => MigrationHistoryDialog.show(context),
                child: const Text('打开历史'),
              ),
            ),
          ),
        ),
      ),
    );

    final barrierBaseline = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(find.text('打开历史'));
    await tester.pump();

    expect(find.byType(MigrationHistoryDialog), findsOneWidget);
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline + 1));

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(MigrationHistoryDialog), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline));
  });
}
