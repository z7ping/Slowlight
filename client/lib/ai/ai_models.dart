enum AiProviderType {
  ollama,
  openai,
  deepseek,
  compatible;

  String get wireName => name;

  String get label => switch (this) {
        AiProviderType.ollama => 'Ollama',
        AiProviderType.openai => 'OpenAI',
        AiProviderType.deepseek => 'DeepSeek',
        AiProviderType.compatible => 'OpenAI 兼容接口',
      };

  String get defaultEndpoint => switch (this) {
        AiProviderType.ollama => 'http://localhost:11434/v1',
        AiProviderType.openai => 'https://api.openai.com/v1',
        AiProviderType.deepseek => 'https://api.deepseek.com',
        AiProviderType.compatible => '',
      };

  String get defaultModel => switch (this) {
        AiProviderType.deepseek => 'deepseek-v4-pro',
        _ => '',
      };

  /// 只有明确的托管 Provider 预设强制 Key；Compatible 可能指向无鉴权的本地服务。
  bool get apiKeyRequired => switch (this) {
        AiProviderType.openai || AiProviderType.deepseek => true,
        AiProviderType.ollama || AiProviderType.compatible => false,
      };

  static AiProviderType fromWireName(String? value) {
    return AiProviderType.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => AiProviderType.ollama,
    );
  }
}

class AiConfig {
  final bool enabled;
  final AiProviderType provider;
  final String endpoint;
  final String model;
  final double temperature;
  final int maxTokens;

  const AiConfig({
    this.enabled = false,
    this.provider = AiProviderType.ollama,
    this.endpoint = 'http://localhost:11434/v1',
    this.model = '',
    this.temperature = 0.2,
    this.maxTokens = 800,
  });

  String get effectiveEndpoint =>
      endpoint.trim().isEmpty ? provider.defaultEndpoint : endpoint.trim();

  String get effectiveModel =>
      model.trim().isEmpty ? provider.defaultModel : model.trim();

  AiConfig copyWith({
    bool? enabled,
    AiProviderType? provider,
    String? endpoint,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return AiConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      endpoint: endpoint ?? this.endpoint,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.wireName,
        'endpoint': endpoint,
        'model': model,
        'temperature': temperature,
        'max_tokens': maxTokens,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final provider = AiProviderType.fromWireName(json['provider'] as String?);
    return AiConfig(
      enabled: json['enabled'] == true,
      provider: provider,
      endpoint: json['endpoint'] as String? ?? provider.defaultEndpoint,
      model: json['model'] as String? ?? provider.defaultModel,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      maxTokens: (json['max_tokens'] as num?)?.toInt() ?? 800,
    );
  }
}
