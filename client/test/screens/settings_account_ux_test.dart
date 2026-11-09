import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/screens/focus_home_screen.dart';
import 'package:slowlight/main.dart' show authStateNotifier;
import 'package:slowlight/services/auth_service.dart';
import 'package:slowlight/services/auth_storage_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/screens/settings_screen.dart';
import 'package:slowlight/ui/fx.dart';
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
  test('侧栏账号摘要读取不校验网络或广播退出登录', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      // Simulate a JWT that expired *after* AuthGate originally opened Home.
      'auth_token': 'expired.jwt.signed',
    });
    await DataModeManager().setCloud();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_login_method', 'github');
    await prefs.setString('user_data', jsonEncode({
      'id': 42,
      'username': 'github_42',
      'nickname': '七平',
      'email': '',
      'created_at': '2026-10-21T00:00:00Z',
    }));
    final initialEvent = authStateNotifier.value;
    var eventCount = 0;
    void countEvent() => eventCount++;
    authStateNotifier.addListener(countEvent);
    try {
      expect(await AuthService.isLoggedIn(), isFalse);
      final cached = await readCachedSidebarAccountSummary();
      expect(cached['name'], '七平');
      expect(cached['status'], '最近通过 GitHub 登录 · 云端');
      expect(authStateNotifier.value, initialEvent);
      expect(eventCount, 0);
      expect(await AuthService.getToken(), 'expired.jwt.signed');
      // Neither the cached user nor the token was destroyed by the drawer.
      expect((await AuthService.getUser())?.id, 42);
    } finally {
      authStateNotifier.removeListener(countEvent);
      FlutterSecureStorage.setMockInitialValues({});
    }
  });

  testWidgets('Android 打开账号页不会自动读取 GitHub 待绑定存储',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'existing.jwt.value',
      'auth_refresh_token': 'existing-refresh',
      'github_oauth_pending': 'unrelated-pending-entry',
    });
    final traces = <String>[];
    AuthStorageDiagnostics.debugTraceSink = traces.add;
    addTearDown(() {
      AuthStorageDiagnostics.debugTraceSink = null;
      FlutterSecureStorage.setMockInitialValues({});
    });
    await tester.runAsync(() => DataModeManager().setCloud());
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'account'),
    ));
    await tester.pump();

    // GitHub and password are equally high compact rows. Their divider must
    // occupy the geometric midpoint, not inherit Shad theme separator margins
    // that paint the line below the actual row boundary.
    final githubRow = find.byKey(
      const ValueKey('settings.account.github.mobile'),
    );
    final passwordRow = find.byKey(
      const ValueKey('settings.account.password.mobile'),
    );
    final dividerFinder = find.byType(FxSeparator);
    expect(githubRow, findsOneWidget);
    expect(passwordRow, findsOneWidget);
    expect(dividerFinder, findsOneWidget);
    expect(tester.widget<FxSeparator>(dividerFinder).margin, EdgeInsets.zero);
    final midpoint = (tester.getCenter(githubRow).dy +
        tester.getCenter(passwordRow).dy) / 2;
    expect(tester.getCenter(dividerFinder).dy, closeTo(midpoint, 1));

    expect(
      traces.where((e) => e.contains('actor=oauth.pending.load')),
      isEmpty,
    );
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'auth_token'), 'existing.jwt.value');
    expect(await storage.read(key: 'auth_refresh_token'), 'existing-refresh');
    await disposeFxTestHost(tester);
  });

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
  testWidgets('本地切云端时失效的非本地 token 必须先登录，不能直接换数据源',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.runAsync(() => DataModeManager().setLocal());
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'expired-or-invalid-jwt',
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'data'),
    ));
    await tester.pump();
    await tester.tap(find.text('云端数据').first);
    await tester.pump();
    expect(find.text('切换为云端数据？'), findsOneWidget);
    await tester.tap(find.text('确认切换'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(DataModeManager().isLocal, isTrue);
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

  testWidgets('Android 账号列表保持紧凑，本地入口只能登录或管理数据', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.runAsync(() => DataModeManager().setLocal());
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'account'),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('settings.account.personal')), findsOneWidget);
    // Section captions live outside the card, as in the approved prototype.
    expect(find.ancestor(
      of: find.text('登录与安全'),
      matching: find.byType(FxCard),
    ), findsNothing);
    expect(find.ancestor(
      of: find.text('数据与同步'),
      matching: find.byType(FxCard),
    ), findsNothing);
    // The centered title is a settings detail variant of the existing header.
    expect(tester.getRect(find.text('账号')).center.dx, closeTo(180, 2));
    expect(find.byKey(const ValueKey('settings.account.login_cloud')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.account.open_data')), findsOneWidget);
    final dataTile = tester.widget<FxListTile>(
      find.byKey(const ValueKey('settings.account.open_data')),
    );
    expect(dataTile.leading, isA<CircleAvatar>());
    expect((dataTile.leading! as CircleAvatar).radius, 18);
    expect(find.byKey(const ValueKey('settings.account.github.mobile')), findsNothing);
    expect(find.byKey(const ValueKey('settings.account.logout.mobile')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings.account.open_data')));
    await tester.pump();
    expect(find.text('数据迁移'), findsOneWidget);
    expect(find.text('迁移历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
