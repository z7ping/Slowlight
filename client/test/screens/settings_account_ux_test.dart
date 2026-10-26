import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/screens/settings_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/reminder_service.dart';

import '../support/fx_test_host.dart';
import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('settings_account_ux');
    SharedPreferences.setMockInitialValues({});
    ReminderService().updateConfig(autoStartOnLaunch: false);
    await ReminderService().loadAll();
  });
  tearDownAll(() { ReminderService().dispose(); });
  test('GitHub OAuth 内部占位邮箱不向用户展示', () {
    expect(
      accountEmailLabel('gh-17805674@oauth.slowlight.invalid'),
      '未设置联系邮箱',
    );
    expect(accountEmailLabel('user@example.com'), 'user@example.com');
    expect(accountEmailLabel(''), '未设置联系邮箱');
  });

  testWidgets('本地账号不显示不可执行的 GitHub 绑定，而是说明云端登录和迁移',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.runAsync(() => DataModeManager().setLocal());
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1200, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'account'),
    ));
    await tester.pump();
    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('登录方式'), findsOneWidget);
    expect(find.text('GH'), findsOneWidget);
    expect(find.text('数据模式'), findsOneWidget);
    expect(find.text('本地使用'), findsOneWidget);
    expect(find.text('登录云端账号'), findsOneWidget);
    expect(find.textContaining('当前没有云端身份'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.github_link')), findsNothing);
    expect(find.byKey(const ValueKey('settings.account.logout')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings.account.open_data')));
    await tester.pump();
    expect(find.text('数据迁移'), findsOneWidget);
    expect(find.text('迁移历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('Windows 双栏不重复内容页头，并使用 24px 外边距展开右侧内容',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.runAsync(() => DataModeManager().setLocal());
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1184, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'account'),
    ));
    await tester.pump();

    expect(find.text('管理账号、登录方式与身份关联'), findsNothing);
    final card = tester.getRect(
      find.byKey(const ValueKey('settings.account.personal')),
    );
    // 1184px 窗口未触发 1180px 上限，右侧内容应贴合 24px 页面外边距，
    // 不再被旧的 1050px 居中容器和 820px 二次限宽收窄。
    expect(card.right, closeTo(1160, 3));
    expect(card.left, lessThan(290));
    expect(card.top, lessThan(150));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
