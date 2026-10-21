import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Android 通知避让系统导航栏，长错误通过详情完整查看', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 32);
    addTearDown(tester.view.reset);

    final details = List.filled(
      60,
      'ClientException with SocketException: Connection refused',
    ).join('\n');

    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FxButton(
                label: '触发失败',
                onPressed: () => FxNotice.errorWithDetails(
                  context,
                  '登录失败',
                  details,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发失败'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('登录失败'), findsOneWidget);
    expect(find.text(details), findsNothing);
    final toast = find.byType(ShadToast).last;
    expect(tester.getRect(toast).bottom, lessThanOrEqualTo(768));

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    expect(find.text(details), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text(details), findsNothing);

    await disposeFxTestHost(tester);
  });
}
