import 'package:http/http.dart' as http;

import 'ai_models.dart';
import 'ai_provider.dart';
import 'openai_compatible_provider.dart';

class AiProviderFactory {
  const AiProviderFactory();

  AiProvider create({
    required AiConfig config,
    String apiKey = '',
    http.Client? client,
  }) {
    final endpoint = config.effectiveEndpoint;
    final model = config.effectiveModel;
    if (endpoint.isEmpty) {
      throw const AiProviderException('AI endpoint 未配置');
    }

    return OpenAiCompatibleProvider(
      type: config.provider,
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
      client: client,
    );
  }
}
