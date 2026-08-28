import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/screens/migration_preview_dialog.dart';
import 'package:slowlight/ui/theme_manager.dart';

void main() {
  testWidgets('数据迁移原型展示安全说明、冲突决策与继续入口', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadTheme(
        data: ThemeManager.shadLight,
        child: MaterialApp(home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => MigrationPreviewDialog.show(context),
                child: const Text('打开'),
              ),
            ),
          );
        })),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();

    expect(find.text('迁移本地数据到云端'), findsOneWidget);
    expect(find.text('迁移不会删除本地数据，可在完成后查看报告'), findsOneWidget);
    expect(find.text('处理冲突 · 请先登录云端'), findsOneWidget);
    expect(find.text('登录云端后即可比较两端数据'), findsOneWidget);
    expect(find.text('切换到云端并预览'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('数据迁移预览在窄窗口切换为紧凑布局', (tester) async {
    tester.view.physicalSize = const Size(460, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadTheme(
        data: ThemeManager.shadLight,
        child: MaterialApp(home: Builder(builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => MigrationPreviewDialog.show(context),
              child: const Text('打开窄屏预览'),
            ),
          );
        })),
      ),
    );

    await tester.tap(find.text('打开窄屏预览'));
    await tester.pump();

    expect(find.text('迁移本地数据到云端'), findsOneWidget);
    expect(find.text('扫描数据'), findsOneWidget);
    expect(find.text('切换到云端并预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });
}
