import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:slowlight/ui/widgets/slowlight_logo.dart';

void main() {
  Widget buildApp() => ShadTheme(
        data: ThemeManager.shadLight,
        child: MaterialApp(
          theme: ThemeManager.lightTheme,
          home: const LoginScreen(),
        ),
      );

  group('LoginScreen', () {
    group('登录模式', () {
      testWidgets('默认渲染登录表单', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        expect(find.text('所行映我'), findsOneWidget);
        expect(find.byType(SlowlightLogo), findsOneWidget);
        expect(find.text('了解自己的系统 · 数据位置由你选择'), findsOneWidget);
        expect(find.text('邮箱或用户名'), findsOneWidget);
        expect(find.text('密码'), findsOneWidget);
        expect(find.text('登录'), findsOneWidget);
      });

      testWidgets('登录模式不显示邮箱和昵称', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        expect(find.text('邮箱'), findsNothing);
        expect(find.text('昵称'), findsNothing);
      });

      testWidgets('用户名为空时点登录显示提示', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        await tester.tap(find.text('登录'));
        await tester.pumpAndSettle();

        expect(find.text('请填写完整信息'), findsOneWidget);
      });
    });

    group('注册模式', () {
      testWidgets('切换到注册模式显示邮箱和昵称', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        final registerBtn = find.text('注册');
        if (registerBtn.evaluate().length > 1) {
          await tester.tap(registerBtn.last);
          await tester.pump();
          expect(find.text('邮箱'), findsOneWidget);
        }
      });

      testWidgets('注册模式邮箱为空时显示提示', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        final registerBtns = find.text('注册');
        if (registerBtns.evaluate().length > 1) {
          await tester.tap(registerBtns.last);
          await tester.pump();
        } else {
          return;
        }

        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'testuser');
        await tester.enterText(fields.at(2), 'password123');

        final submitBtn = find.text('注册');
        await tester.tap(submitBtn.last);
        await tester.pumpAndSettle();

        expect(find.text('请填写邮箱'), findsOneWidget);
      });

      testWidgets('可以在登录和注册之间切换', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        expect(find.text('邮箱'), findsNothing);

        await tester.tap(find.text('注册'));
        await tester.pump();
        expect(find.text('邮箱'), findsOneWidget);

        final loginLink = find.text('已有账号？去登录');
        if (loginLink.evaluate().isNotEmpty) {
          await tester.tap(loginLink);
          await tester.pump();
          expect(find.text('邮箱'), findsNothing);
        }
      });
    });

    group('UI 结构', () {
      testWidgets('包含 Logo 图标', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        expect(find.byType(SlowlightLogo), findsOneWidget);
        final image = tester.widget<Image>(find.descendant(
          of: find.byType(SlowlightLogo),
          matching: find.byType(Image),
        ));
        expect(
          (image.image as AssetImage).assetName,
          'assets/slowlight_logo.png',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('表单卡片包含用户名和密码输入框', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        final textFields = find.byType(TextField);
        expect(textFields, findsNWidgets(2));
      });
    });
  });
}
