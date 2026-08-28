import 'ai_models.dart';

class AiMessage {
  final String role;
  final String content;

  const AiMessage({required this.role, required this.content});

  const AiMessage.system(String content) : this(role: 'system', content: content);
  const AiMessage.user(String content) : this(role: 'user', content: content);
  const AiMessage.assistant(String content)
      : this(role: 'assistant', content: content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AiRequest {
  final List<AiMessage> messages;
  final String? model;
  final double? temperature;
  final int? maxTokens;

  const AiRequest({
    required this.messages,
    this.model,
    this.temperature,
    this.maxTokens,
  });
}

class AiResponse {
  final String text;
  final String model;
  final Map<String, dynamic> raw;

  const AiResponse({
    required this.text,
    this.model = '',
    this.raw = const {},
  });
}

abstract interface class AiProvider {
  AiProviderType get type;

  Future<AiResponse> complete(AiRequest request);
}

class AiProviderException implements Exception {
  final String message;
  final int? statusCode;

  const AiProviderException(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null
      ? 'AiProviderException: $message'
      : 'AiProviderException($statusCode): $message';
}
