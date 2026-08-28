import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slowlight/ai/ai_models.dart';
import 'package:slowlight/ai/ai_provider.dart';
import 'package:slowlight/ai/openai_compatible_provider.dart';

void main() {
  test('DeepSeek preset uses chat completions and bearer key', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'model': 'deepseek-v4-pro',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'OK'}
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final provider = OpenAiCompatibleProvider(
      type: AiProviderType.deepseek,
      endpoint: 'https://api.deepseek.com',
      model: 'deepseek-v4-pro',
      apiKey: 'secret-key',
      client: client,
    );

    final result = await provider.complete(const AiRequest(
      messages: [AiMessage.user('hello')],
    ));

    expect(captured.url.toString(), 'https://api.deepseek.com/chat/completions');
    expect(captured.headers['Authorization'], 'Bearer secret-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-v4-pro');
    expect(body['stream'], false);
    expect(result.text, 'OK');
  });

  test('Ollama works without API key through v1 compatible endpoint', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'model': 'qwen3:8b',
          'choices': [
            {
              'message': {'content': 'local'}
            }
          ]
        }),
        200,
      );
    });

    final provider = OpenAiCompatibleProvider(
      type: AiProviderType.ollama,
      endpoint: 'http://localhost:11434/v1/',
      model: 'qwen3:8b',
      client: client,
    );

    final result = await provider.complete(const AiRequest(
      messages: [AiMessage.user('hello')],
    ));

    expect(captured.url.toString(), 'http://localhost:11434/v1/chat/completions');
    expect(captured.headers.containsKey('Authorization'), false);
    expect(result.text, 'local');
  });

  test('remote provider requires API key', () async {
    final provider = OpenAiCompatibleProvider(
      type: AiProviderType.openai,
      endpoint: 'https://api.openai.com/v1',
      model: 'test-model',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      () => provider.complete(const AiRequest(messages: [AiMessage.user('x')])),
      throwsA(isA<AiProviderException>()),
    );
  });
}
