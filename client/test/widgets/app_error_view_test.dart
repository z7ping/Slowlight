import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/app_error_view.dart';

void main() {
  testWidgets('启动失败时暴露本地日志位置而不是持续加载', (tester) async {
    const logPath = r'C:\Users\tester\Slowlight\logs\slowlight-error.log';

    await tester.pumpWidget(
      const MaterialApp(home: AppErrorView(logPath: logPath)),
    );

    expect(find.text(logPath), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
