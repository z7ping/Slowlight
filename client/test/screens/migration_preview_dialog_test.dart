import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/screens/migration_preview_dialog.dart';
import 'package:slowlight/ui/theme_manager.dart';

void main() {
  testWidgets('数据迁移预览保留安全边界与核心流程', (tester) async {
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

    // 只约束产品级安全边界与流程结构，不再绑定旧版布局或整句文案。
    expect(find.text('迁移本地数据到云端'), findsOneWidget);
    expect(find.textContaining('预览阶段不会写入或删除数据'), findsOneWidget);
    expect(find.textContaining('本地数据始终保留'), findsOneWidget);
    expect(find.text('迁移进度'), findsOneWidget);
    expect(find.text('迁移数据'), findsOneWidget);
    expect(find.text('冲突处理'), findsOneWidget);
    expect(find.text('扫描数据'), findsOneWidget);
    expect(find.text('确认迁移'), findsOneWidget);
    expect(find.text('登录云端并预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('数据迁移预览窄窗口可用且不溢出', (tester) async {
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

    // 窄屏只验证关键入口和布局稳定性，不锁定具体排版实现。
    expect(find.text('迁移本地数据到云端'), findsOneWidget);
    expect(find.text('扫描数据'), findsOneWidget);
    expect(find.text('冲突处理'), findsOneWidget);
    expect(find.text('登录云端并预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });
}
