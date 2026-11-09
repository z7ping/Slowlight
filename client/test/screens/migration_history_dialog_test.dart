import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/migration_history_dialog.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/fx_test_host.dart';

void main() {
  test('S12 缺失或未知迁移状态不能冒充成功回执', () {
    expect(migrationHistoryStatusLabel(null), '状态待核对');
    expect(migrationHistoryStatusLabel(''), '状态待核对');
    expect(migrationHistoryStatusLabel('unrecognized'), '状态待核对');
    expect(migrationHistoryStatusLabel('running'), '结果未确认');
    expect(migrationHistoryStatusLabel('failed'), '待核对');
    expect(migrationHistoryStatusLabel('succeeded'), '成功');
  });

  testWidgets('迁移历史弹窗可以从根导航正常打开和关闭', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Builder(
          builder: (context) => Scaffold(
            body: FxButton(
              label: '打开历史',
              onPressed: () => MigrationHistoryDialog.show(context),
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
    // The explicit footer button is the sole visible exit.
    expect(tester.widget<ShadDialog>(find.byType(ShadDialog)).closeIcon,
        isA<SizedBox>());

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(MigrationHistoryDialog), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline));
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 迁移历史使用独立二级页而非大型弹窗', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        home: Builder(
          builder: (context) => Scaffold(
            body: FxButton(
              label: '打开历史',
              onPressed: () => MigrationHistoryDialog.show(context),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开历史'));
    await tester.pumpAndSettle();
    expect(find.byType(MigrationHistoryDialog), findsOneWidget);
    expect(find.byType(ShadDialog), findsNothing);
    expect(find.byType(FxPageHeader), findsOneWidget);
    expect(find.text('历史来源'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(MigrationHistoryDialog), findsNothing);
    await disposeFxTestHost(tester);
  });

}
