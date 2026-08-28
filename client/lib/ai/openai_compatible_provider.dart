import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_models.dart';
import 'ai_provider.dart';

class OpenAiCompatibleProvider implements AiProvider {
  @override
  final AiProviderType type;
  final String endpoint;
  final String model;
  final String apiKey;
  final double temperature;
  final int maxTokens;
  final http.Client _client;
  final Duration timeout;

  OpenAiCompatibleProvider({
    required this.type,
    required this.endpoint,
    required this.model,
    this.apiKey = '',
    this.temperature = 0.2,
    this.maxTokens = 800,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client();

  Uri get chatCompletionsUri {
    var base = endpoint.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) return Uri.parse(base);
    return Uri.parse('$base/chat/completions');
  }

  @override
  Future<AiResponse> complete(AiRequest request) async {
    final selectedModel = (request.model ?? model).trim();
    if (endpoint.trim().isEmpty) {
      throw const AiProviderException('AI endpoint 未配置');
    }
    if (selectedModel.isEmpty) {
      throw const AiProviderException('AI model 未配置');
    }
    if (type.apiKeyRequired && apiKey.trim().isEmpty) {
      throw const AiProviderException('API Key 未配置');
    }
    if (request.messages.isEmpty) {
      throw const AiProviderException('messages 不能为空');
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    final response = await _client
        .post(
          chatCompletionsUri,
          headers: headers,
          body: jsonEncode({
            'model': selectedModel,
            'messages': request.messages.map((item) => item.toJson()).toList(),
            'temperature': request.temperature ?? temperature,
            'max_tokens': request.maxTokens ?? maxTokens,
            'stream': false,
          }),
        )
        .timeout(timeout);

    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data['error'];
      final message = error is Map
          ? (error['message']?.toString() ?? response.body)
          : response.body;
      throw AiProviderException(
        message.isEmpty ? 'AI 请求失败' : message,
        statusCode: response.statusCode,
      );
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiProviderException('AI 返回缺少 choices');
    }
    final choice = Map<String, dynamic>.from(choices.first as Map);
    final message = choice['message'];
    if (message is! Map) {
      throw const AiProviderException('AI 返回缺少 message');
    }
    final content = _contentText(message['content']);
    if (content.trim().isEmpty) {
      throw const AiProviderException('AI 返回内容为空');
    }

    return AiResponse(
      text: content.trim(),
      model: data['model']?.toString() ?? selectedModel,
      raw: data,
    );
  }

  String _contentText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content.map((part) {
        if (part is String) return part;
        if (part is Map) {
          final map = Map<String, dynamic>.from(part);
          return map['text']?.toString() ?? '';
        }
        return '';
      }).where((text) => text.isNotEmpty).join('\n');
    }
    return content?.toString() ?? '';
  }
}
