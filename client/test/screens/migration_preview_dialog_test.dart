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

    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    expect(find.textContaining('预览阶段不会写入或删除数据'), findsOneWidget);
    expect(find.textContaining('本地数据始终保留'), findsOneWidget);
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

    expect(find.byType(MigrationPreviewDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
