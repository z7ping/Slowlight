import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/screens/migration_preview_dialog.dart';
import 'package:slowlight/ui/theme_manager.dart';

Widget _host() => ShadTheme(
      data: ThemeManager.shadLight,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => MigrationPreviewDialog.show(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('数据迁移预览保留不可破坏的安全语义', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.tap(find.text('打开'));
    await tester.pump();

    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    expect(find.textContaining('预览阶段不会写入或删除数据'), findsOneWidget);
    expect(find.textContaining('本地数据始终保留'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 推进弹窗入场动画，避免 flutter_animate 的零延时 Timer 残留到测试结束。
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('数据迁移预览窄窗口不产生布局异常', (tester) async {
    tester.view.physicalSize = const Size(460, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.tap(find.text('打开'));
    await tester.pump();

    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 1));
  });
}
