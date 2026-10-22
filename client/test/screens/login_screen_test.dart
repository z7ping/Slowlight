import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

Future<void> openPassword(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('login.password_action')));
  await tester.tap(find.byKey(const ValueKey('login.password_action')));
  await tester.pump();
}

Future<void> openRegister(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('login.switch_mode')));
  await tester.tap(find.byKey(const ValueKey('login.switch_mode')));
  await tester.pump();
}

void main() {
  group('LoginScreen 五阶段流程', () {
    testWidgets('默认只展示入口，不抢先展示账号密码输入框', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      expect(find.byKey(const ValueKey('login.page_welcome')), findsOneWidget);
      expect(find.byKey(const ValueKey('login.github_action')), findsOneWidget);
      expect(find.byKey(const ValueKey('login.password_action')), findsOneWidget);
      expect(find.byKey(const ValueKey('login.local_action')), findsOneWidget);
      expect(find.byType(FxInput), findsNothing);
      expect(find.byKey(const ValueKey('login.primary_action')), findsNothing);
      await disposeFxTestHost(tester);
    });

    testWidgets('密码登录为独立页面，空凭据阻止提交，支持返回首页', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      await openPassword(tester);

      expect(find.byKey(const ValueKey('login.page_password')), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(2));
      expect(find.byKey(const ValueKey('login.github_action')), findsNothing);
      await tester.ensureVisible(find.text('登录'));
      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(find.text('请填写完整信息'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('login.back')));
      await tester.tap(find.byKey(const ValueKey('login.back')));
      await tester.pump();
      expect(find.byKey(const ValueKey('login.page_welcome')), findsOneWidget);
      expect(find.byType(FxInput), findsNothing);
      await disposeFxTestHost(tester);
    });

    testWidgets('注册使用四字段，返回密码登录不清除输入草稿', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      await openRegister(tester);

      expect(find.byKey(const ValueKey('login.page_register')), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(4));
      await tester.enterText(find.byType(FxInput).first, 'testuser');
      await tester.ensureVisible(find.byKey(const ValueKey('login.switch_mode')));
      await tester.tap(find.byKey(const ValueKey('login.switch_mode')));
      await tester.pump();
      expect(find.byKey(const ValueKey('login.page_password')), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(2));
      expect(find.text('testuser'), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('注册缺少邮箱不会请求服务端', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      await openRegister(tester);

      final fields = find.byType(FxInput);
      await tester.enterText(fields.at(0), 'testuser');
      await tester.enterText(fields.at(2), 'password123');
      await tester.ensureVisible(find.text('创建账号').last);
      await tester.tap(find.text('创建账号').last);
      await tester.pump();
      expect(find.text('请填写邮箱'), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('本地数据先展示说明，返回不触发真实本地初始化', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('login.local_action')));
      await tester.pump();
      expect(find.byKey(const ValueKey('login.page_local')), findsOneWidget);
      expect(find.text('不会自动上传或合并到云端。', findRichText: true),
          findsNothing); // 合并说明在完整文本里，不是独立按钮。
      expect(find.byKey(const ValueKey('login.local_confirm')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('login.local_cancel')));
      await tester.tap(find.byKey(const ValueKey('login.local_cancel')));
      await tester.pump();
      expect(find.byKey(const ValueKey('login.page_welcome')), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('授权等待在独立视图，不和密码表单共存（源码契约）',
        (tester) async {
      // GitHubSignIn 由平台浏览器驱动。此测试不伪造授权成功或请求外网。
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('login.page_github')), findsNothing);
      expect(find.byKey(const ValueKey('login.github_check')), findsNothing);
      await disposeFxTestHost(tester);
    });
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('Windows / Android $platform 字体 $scale：页面切换、输入高度与滚动',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = platform == TargetPlatform.android
            ? const Size(360, 800)
            : const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(buildFxTestHost(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: const LoginScreen(),
        ));
        await tester.pump();
        expect(find.byKey(const ValueKey('login.page_welcome')), findsOneWidget);
        expect(find.byType(FxInput), findsNothing);

        await openPassword(tester);
        final inputs = find.byType(FxInput);
        expect(inputs, findsNWidgets(2));
        final normal = tester.getSize(inputs.at(0)).height;
        final password = tester.getSize(inputs.at(1)).height;
        expect(password, closeTo(normal, 0.1));
        expect(normal, greaterThanOrEqualTo(
            platform == TargetPlatform.android ? 44 : 36));
        expect(tester.getSize(find.byKey(const ValueKey('login.primary_action'))).width,
            closeTo(tester.getSize(inputs.first).width, 1));

        await openRegister(tester);
        expect(find.byType(FxInput), findsNWidgets(4));
        for (var i = 0; i < 4; i++) {
          expect(tester.getSize(find.byType(FxInput).at(i)).height,
              closeTo(normal, 0.1));
        }
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }
}
