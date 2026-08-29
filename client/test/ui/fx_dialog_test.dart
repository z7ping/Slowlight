import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';

void main() {
  Widget buildHost() {
    return ShadTheme(
      data: ThemeManager.shadLight,
      child: MaterialApp(
        theme: ThemeManager.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => FxDialog.confirm(
                context: context,
                title: '删除任务',
                content: '确定删除吗？',
                confirmText: '删除',
                destructive: true,
              ),
              child: const Text('打开弹窗'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('FxDialog 使用统一遮罩并允许点击外部取消', (tester) async {
    await tester.pumpWidget(buildHost());
    final barrierBaseline = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();

    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline + 1));
    expect(barriers.any((barrier) => barrier.color == FxDialog.barrierColor),
        isTrue);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('删除任务'), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline));
  });
}
