import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  group('LoginScreen 密码优先与其他登录方式', () {
    testWidgets('默认展示账号密码，GitHub 是次级入口，注册暂时隐藏', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      expect(find.byKey(const ValueKey('login.page_welcome')), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(2));
      expect(find.byKey(const ValueKey('login.primary_action')), findsOneWidget);
      expect(find.byKey(const ValueKey('login.provider.github')), findsOneWidget);
      expect(find.byKey(const ValueKey('login.more_providers')), findsNothing);
      expect(find.byKey(const ValueKey('login.local_action')), findsOneWidget);
      expect(find.text('创建账号'), findsNothing);
      expect(find.byKey(const ValueKey('login.page_register')), findsNothing);
      expect(find.byKey(const ValueKey('login.password_action')), findsNothing);
      expect(
        find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/github_mark.png'),
        findsOneWidget,
      );
      await disposeFxTestHost(tester);
    });

    testWidgets('空凭据禁止登录，原位保留表单', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('login.primary_action')));
      await tester.pump();

      expect(find.text('请填写完整信息'), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(2));
      expect(find.byKey(const ValueKey('login.page_welcome')), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('密码眼睛位于 FxInput 内并可切换显隐', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      final password = find.byWidgetPredicate(
        (widget) => widget is FxInput && widget.label == '密码',
      );
      expect(password, findsOneWidget);
      expect(tester.widget<FxInput>(password).obscureText, isTrue);

      await tester.tap(find.byWidgetPredicate(
        (widget) => widget is FxIconButton && widget.tooltip == '显示密码',
      ));
      await tester.pump();
      expect(tester.widget<FxInput>(password).obscureText, isFalse);

      await tester.tap(find.byWidgetPredicate(
        (widget) => widget is FxIconButton && widget.tooltip == '隐藏密码',
      ));
      await tester.pump();
      expect(tester.widget<FxInput>(password).obscureText, isTrue);
      await disposeFxTestHost(tester);
    });

    testWidgets('本地入口先确认，取消不触发数据模式切换', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('login.local_action')));
      await tester.tap(find.byKey(const ValueKey('login.local_action')));
      await tester.pumpAndSettle();

      expect(find.text('使用本地模式？'), findsOneWidget);
      expect(find.textContaining('不会自动上传或合并到云端'), findsOneWidget);
      expect(find.text('继续本地使用'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('login.page_welcome')), findsOneWidget);
      expect(find.text('使用本地模式？'), findsNothing);
      expect(find.byType(FxInput), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('迁移身份验证仍展示密码/GitHub，绝不提供本地模式切换', (tester) async {
      await tester.pumpWidget(buildFxTestHost(
        home: const LoginScreen(preserveDataMode: true),
      ));
      await tester.pump();

      expect(find.text('验证云端身份'), findsOneWidget);
      expect(find.textContaining('仍使用本地数据'), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(2));
      expect(find.byKey(const ValueKey('login.provider.github')), findsOneWidget);
      expect(find.byKey(const ValueKey('login.local_action')), findsNothing);
      expect(find.text('创建账号'), findsNothing);
      await disposeFxTestHost(tester);
    });

    testWidgets('独立 GitHub 状态页不会和首页表单混杂', (tester) async {
      // OAuth is browser-driven: do not mock a successful identity here.
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('login.page_github')), findsNothing);
      expect(find.byKey(const ValueKey('login.github_check')), findsNothing);
      await disposeFxTestHost(tester);
    });
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('$platform / text scale $scale: 表单高度/布局保持完整',
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
        final inputs = find.byType(FxInput);
        expect(inputs, findsNWidgets(2));
        final usernameHeight = tester.getSize(inputs.at(0)).height;
        final passwordHeight = tester.getSize(inputs.at(1)).height;
        expect(passwordHeight, closeTo(usernameHeight, 0.1));
        expect(usernameHeight, greaterThanOrEqualTo(
            platform == TargetPlatform.android ? 44 : 36));
        expect(
          tester.getSize(find.byKey(const ValueKey('login.primary_action'))).width,
          closeTo(tester.getSize(inputs.first).width, 1),
        );
        await tester.ensureVisible(find.byKey(const ValueKey('login.local_action')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }
}
