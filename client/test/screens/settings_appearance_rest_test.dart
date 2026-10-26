import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:slowlight/screens/settings_screen.dart';
import 'package:slowlight/services/theme_settings.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/reminder_service.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';
import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('settings_appearance_rest');
    SharedPreferences.setMockInitialValues({});
    await DataModeManager().setLocal();
    await ThemeSettings().load();
    ReminderService().updateConfig(autoStartOnLaunch: false);
    await ReminderService().loadAll();
  });
  tearDownAll(() { ReminderService().dispose(); });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'user_data': 'invalid-data',
      'theme_font_scale': 0.85,
    });
  });

  testWidgets('Windows 的 85% 字号在设置中不被夹取到 100%', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.runAsync(() => ThemeSettings().load());
    tester.view.physicalSize = const Size(1250, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'appearance'),
    ));
    await tester.pump();

    final slider = tester.widget<FxSlider>(find.byType(FxSlider));
    expect(slider.min, 0.85);
    expect(slider.max, 1.25);
    expect(slider.value, 0.85);
    expect(find.text('85%'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
    await tester.runAsync(() => ThemeSettings().resetToDefaults());
  });

  testWidgets('Android 字号最低为 100%', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.runAsync(() => ThemeSettings().load());
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'appearance'),
    ));
    await tester.pump();

    await tester.tap(find.text('外观').first);
    await tester.pump();
    final slider = tester.widget<FxSlider>(find.byType(FxSlider));
    expect(slider.min, 1.0);
    expect(slider.max, 1.25);
    expect(slider.value, 1.0);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
    await tester.runAsync(() => ThemeSettings().resetToDefaults());
  });

  testWidgets('休息提醒正式配置不再展示未实现的提案开关', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1250, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'rest'),
    ));
    await tester.pump();

    expect(find.text('睡眠暂停计时'), findsNothing);
    expect(find.text('锁屏重置本轮'), findsNothing);
    expect(find.text('免打扰时段'), findsNothing);
    expect(find.text('提案'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
