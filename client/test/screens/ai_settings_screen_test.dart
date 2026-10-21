import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/ai/ai_config_store.dart';
import 'package:slowlight/ai/ai_models.dart';
import 'package:slowlight/screens/ai_settings_screen.dart';

import '../support/fx_test_host.dart';

class _Secrets implements AiSecretStore {
  bool failOnce = false;
  final values = <AiProviderType, String>{};

  @override
  Future<String?> read(AiProviderType provider) async {
    if (failOnce) {
      failOnce = false;
      throw StateError('secure storage unavailable');
    }
    return values[provider];
  }

  @override
  Future<void> write(AiProviderType provider, String value) async {
    values[provider] = value;
  }

  @override
  Future<void> delete(AiProviderType provider) async {
    values.remove(provider);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('兼容接口复用同一配置页，API 密钥允许留空', (tester) async {
    final store = AiConfigStore(secrets: _Secrets());
    await store.save(const AiConfig(
      provider: AiProviderType.compatible,
      endpoint: 'http://127.0.0.1:9000/v1',
      model: 'test-model',
    ));

    await tester.pumpWidget(buildFxTestHost(
      home: AiSettingsScreen(store: store),
    ));
    await tester.pump();
    expect(find.text('访问密钥（可选）'), findsOneWidget);
    expect(find.textContaining('当前接口地址指向本机'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('安全存储读取失败时提供重试，避免用默认配置冒充成功', (tester) async {
    final secrets = _Secrets()..failOnce = true;
    final store = AiConfigStore(secrets: secrets);

    await tester.pumpWidget(buildFxTestHost(
      home: AiSettingsScreen(store: store),
    ));
    await tester.pump();
    expect(find.textContaining('读取 AI 配置失败'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);

    await tester.tap(find.text('重新加载'));
    await tester.pump();
    expect(find.text('启用 AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
