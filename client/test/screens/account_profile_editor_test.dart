import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/user.dart';
import 'package:slowlight/screens/account_profile_editor.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('昵称编辑使用统一 Fx 弹窗且取消不修改资料', (tester) async {
    final user = User(
      id: 7,
      username: 'clouduser',
      email: 'user@example.com',
      nickname: '原昵称',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(builder: (context) => FxButton(
          onPressed: () => editCloudNickname(context, user),
          label: '编辑资料',
        )),
      ),
    ));
    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();
    expect(find.text('修改昵称'), findsOneWidget);
    expect(find.byKey(const ValueKey('account.nickname.input')), findsOneWidget);
    expect(find.text('原昵称'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account.nickname.input')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final existing in [false, true]) {
    testWidgets('${existing ? "密码已设置" : "GitHub 首次设置"} 表单正确区分入口',
        (tester) async {
      await tester.pumpWidget(buildFxTestHost(
        home: Scaffold(
          body: Builder(builder: (context) => FxButton(
            onPressed: () => manageAccountPassword(
              context,
              alreadySet: existing,
              username: 'clouduser',
            ),
            label: '管理账号',
          )),
        ),
      ));
      await tester.tap(find.text('管理账号'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account.password.new')), findsOneWidget);
      expect(find.byKey(const ValueKey('account.password.username')),
          existing ? findsNothing : findsOneWidget);
      expect(find.text(existing ? '当前密码' : '确认密码'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }
}
