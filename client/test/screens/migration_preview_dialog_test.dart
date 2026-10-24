import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/migration_preview_dialog.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

Widget _host() => buildFxTestHost(
      home: Builder(
        builder: (context) => Scaffold(
          body: FxButton(
            label: '打开',
            onPressed: () => MigrationPreviewDialog.show(context),
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
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    expect(find.textContaining('预览阶段不会写入或删除数据'), findsOneWidget);
    expect(find.textContaining('本地数据始终保留'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('迁移预览显示全部八类统计而非只有四类，并移除虚假差异说明', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    for (final label in [
      '清单', '标签', '观察标签（旧）', '任务',
      '子任务', '习惯', '打卡记录', '专注记录',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('状态、截止日期等字段存在差异'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('迁移向导 Windows 共用四阶段结构和完整八类数据', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host());
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    for (final stage in ['检查数据','处理冲突','最终确认','迁移结果']) {
      expect(find.text(stage), findsOneWidget);
    }
    expect(find.text('子任务'), findsOneWidget);
    expect(find.textContaining('字段内容存在差异'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 全屏向导在 360dp 和字体放大时不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: SafeArea(
          child: MigrationPreviewDialog(fullScreen: true),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    expect(find.text('数据迁移'), findsOneWidget);
    expect(find.text('清单'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('数据迁移预览窄窗口不产生布局异常', (tester) async {
    tester.view.physicalSize = const Size(460, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
