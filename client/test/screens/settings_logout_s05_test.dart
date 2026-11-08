import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/screens/settings_screen.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';
import '../support/fx_test_host.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('settings_logout_s05');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_data': 'invalid-data'});
    FlutterSecureStorage.setMockInitialValues({});
    DataModeManager().resetForTesting();
    await DataModeManager().setCloud();
  });

  void desktop(WidgetTester tester) {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('S05 退出期间阻止重复提交，清理异常不误跳登录', (tester) async {
    desktop(tester);
    final pending = Completer<void>();
    var invocations = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: SettingsScreen(
        initialSection: 'account',
        logoutAction: () {
          invocations++;
          return pending.future;
        },
      ),
    ));
    await tester.pump();

    final logout = find.byKey(const ValueKey('settings.account.logout'));
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pump();
    await tester.tap(find.text('确认').last);
    await tester.pump();

    expect(invocations, 1);
    expect(find.text('退出中…'), findsOneWidget);
    final disabled = tester.widget<FxButton>(logout);
    expect(disabled.onPressed, isNull);

    pending.completeError(StateError('secure storage failed'));
    await tester.pump();
    await tester.pump();

    expect(invocations, 1);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('退出中…'), findsNothing);
    expect(tester.widget<FxButton>(logout).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('S05 取消退出只关闭确认，不清理登录状态', (tester) async {
    desktop(tester);
    var invocations = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: SettingsScreen(
        initialSection: 'account',
        logoutAction: () async { invocations++; },
      ),
    ));
    await tester.pump();

    final logout = find.byKey(const ValueKey('settings.account.logout'));
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pump();
    await tester.tap(find.text('取消').last);
    await tester.pump();

    expect(invocations, 0);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.widget<FxButton>(logout).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
