import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/ai/ai_config_store.dart';
import 'package:slowlight/ai/ai_models.dart';
import 'package:slowlight/screens/ai_settings_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

class _Secrets implements AiSecretStore {
  bool failOnce = false;
  bool failWrite = false;
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
    if (failWrite) throw StateError('secure store write blocked');
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
  testWidgets('托管服务商缺密钥时阻止保存并保留错误', (tester) async {
    final store = AiConfigStore(secrets: _Secrets());
    await store.save(const AiConfig(
      enabled: true,
      provider: AiProviderType.openai,
      model: 'test-model',
    ));
    await tester.pumpWidget(buildFxTestHost(home: AiSettingsScreen(store: store)));
    await tester.pump();

    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('当前 AI 服务需要访问密钥'), findsOneWidget);
    expect((await store.load()).provider, AiProviderType.openai);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('安全密钥写入失败保留输入草稿且不得声称保存成功', (tester) async {
    final secrets = _Secrets()..failWrite = true;
    final store = AiConfigStore(secrets: secrets);
    await store.save(const AiConfig(
      provider: AiProviderType.deepseek,
      model: 'test-model',
    ));
    await tester.pumpWidget(buildFxTestHost(home: AiSettingsScreen(store: store)));
    await tester.pump();

    await tester.enterText(find.byType(FxInput).last, 'new-secret');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.textContaining('保存 AI 配置失败'), findsOneWidget);
    expect(find.textContaining('草稿已保留'), findsOneWidget);
    // 密钥仍留在遮蔽的编辑草稿中，不能出现在可见错误或通知里。
    expect(find.textContaining('new-secret', findRichText: true), findsOneWidget);
    final secretField = tester.widget<EditableText>(find.byType(EditableText).last);
    expect(secretField.obscureText, isTrue);
    expect(secretField.controller.text, 'new-secret');
    expect(find.textContaining('new-secret', skipOffstage: false)
        .evaluate().where((element) => element.widget is Text), isEmpty);
    expect(await secrets.read(AiProviderType.deepseek), isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('测试不等于保存，必填校验失败留在当前表单', (tester) async {
    final store = AiConfigStore(secrets: _Secrets());
    await store.save(const AiConfig(
      provider: AiProviderType.openai,
      model: 'test-model',
    ));
    await tester.pumpWidget(buildFxTestHost(home: AiSettingsScreen(store: store)));
    await tester.pump();

    await tester.ensureVisible(find.text('测试连接'));
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(find.text('连接失败：当前 AI 服务需要访问密钥'), findsOneWidget);
    expect((await store.load()).enabled, false);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
