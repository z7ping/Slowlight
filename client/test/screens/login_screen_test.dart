import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/ui/theme_manager.dart';

void main() {
  Widget buildApp() => ShadTheme(
        data: ThemeManager.shadLight,
        child: MaterialApp(
          theme: ThemeManager.lightTheme,
          home: const LoginScreen(),
        ),
      );

  group('LoginScreen 稳定契约', () {
    testWidgets('空凭据提交会被本地校验拦截', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('登录'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('切换注册模式后提供注册所需输入能力', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(2));
      await tester.tap(find.text('注册'));
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('注册缺少邮箱时不会进入远端提交', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('注册'));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'testuser');
      await tester.enterText(fields.at(2), 'password123');
      await tester.tap(find.text('注册'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
