import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/app_error_view.dart';

void main() {
  testWidgets('shows a restart message and log location instead of loading text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppErrorView(
          logPath: r'C:\Users\tester\Slowlight\logs\slowlight-error.log',
        ),
      ),
    );

    expect(find.text('界面加载失败'), findsOneWidget);
    expect(find.textContaining('请重启所行映我'), findsOneWidget);
    expect(find.textContaining('slowlight-error.log'), findsOneWidget);
    expect(find.text('加载中...'), findsNothing);
  });
}
