import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  group('LoginScreen 稳定契约', () {
    testWidgets('空凭据提交会被本地校验拦截', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('login.primary_action')), findsOneWidget);

      await tester.tap(find.text('登录'));
      await tester.pump();

      expect(find.text('请填写完整信息'), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('切换注册模式后提供注册所需输入能力', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      expect(find.byKey(const ValueKey('login.github_action')), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(2));
      await tester.tap(find.text('注册'));
      await tester.pump();

      expect(find.byKey(const ValueKey('login.github_action')), findsOneWidget);
      expect(find.byType(FxInput), findsNWidgets(4));
      await disposeFxTestHost(tester);
    });

    testWidgets('登录和注册模式的单行字段等高，密码尾部按钮不撑高', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      double fieldHeight(int index) => tester.getSize(find.byType(FxInput).at(index)).height;
      expect(fieldHeight(0), closeTo(fieldHeight(1), 0.1));
      final loginHeight = fieldHeight(0);

      await tester.tap(find.text('注册'));
      await tester.pump();
      expect(find.byType(FxInput), findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(fieldHeight(i), closeTo(loginHeight, 0.1));
      }
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('注册缺少邮箱时不会进入远端提交', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      await tester.tap(find.text('注册'));
      await tester.pump();

      final fields = find.byType(FxInput);
      await tester.enterText(fields.at(0), 'testuser');
      await tester.enterText(fields.at(2), 'password123');

      final submit = find.text('创建账号');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();

      expect(find.text('请填写邮箱'), findsOneWidget);
      await disposeFxTestHost(tester);
    });
  });
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('登录/注册表单 $platform 字体 $scale：字段与密码操作等高',
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
        final fields = find.byType(FxInput);
        expect(fields, findsNWidgets(2));
        expect(tester.getSize(find.byKey(const ValueKey('login.primary_action'))).width,
            closeTo(tester.getSize(fields.at(0)).width, 1));
        final normal = tester.getSize(fields.at(0)).height;
        final password = tester.getSize(fields.at(1)).height;
        expect(password, closeTo(normal, 0.1));
        expect(normal, greaterThanOrEqualTo(platform == TargetPlatform.android ? 44 : 36));
        await tester.ensureVisible(find.text('注册'));
        await tester.tap(find.text('注册'));
        await tester.pump();
        expect(fields, findsNWidgets(4));
        for (var i = 0; i < 4; i++) {
          expect(tester.getSize(fields.at(i)).height, closeTo(normal, 0.1));
        }
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

}
