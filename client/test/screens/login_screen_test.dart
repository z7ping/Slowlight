import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  group('LoginScreen 稳定契约', () {
    testWidgets('空凭据提交会被本地校验拦截', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      await tester.tap(find.text('登录'));
      await tester.pump();

      expect(find.text('请填写完整信息'), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('切换注册模式后提供注册所需输入能力', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const LoginScreen()));
      await tester.pump();

      expect(find.byType(FxInput), findsNWidgets(2));
      await tester.tap(find.text('注册'));
      await tester.pump();

      expect(find.byType(FxInput), findsNWidgets(4));
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

      final submit = find.text('注册');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pump();

      expect(find.text('请填写邮箱'), findsOneWidget);
      await disposeFxTestHost(tester);
    });
  });
}
