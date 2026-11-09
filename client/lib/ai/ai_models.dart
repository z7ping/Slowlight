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


/// One saved endpoint/model pair. Credentials are never serialized here.
class AiProfile {
  final String id;
  final String name;
  final AiConfig config;

  const AiProfile({
    required this.id,
    required this.name,
    required this.config,
  });

  AiProfile copyWith({String? name, AiConfig? config}) => AiProfile(
        id: id,
        name: name ?? this.name,
        config: config ?? this.config,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'config': config.toJson(),
      };

  factory AiProfile.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final rawConfig = value['config'];
    if (id is! String || id.isEmpty || rawConfig is! Map) {
      throw const FormatException('Invalid AI profile');
    }
    final config = AiConfig.fromJson(Map<String, dynamic>.from(rawConfig));
    return AiProfile(
      id: id,
      name: value['name'] is String && (value['name'] as String).trim().isNotEmpty
          ? value['name'] as String
          : config.provider.label,
      config: config.copyWith(enabled: false),
    );
  }
}

/// Global AI enablement and one optional selected profile.
class AiProfileCatalog {
  final List<AiProfile> profiles;
  final String? activeId;
  final bool enabled;

  const AiProfileCatalog({
    required this.profiles,
    required this.activeId,
    required this.enabled,
  });

  AiProfile? get active {
    for (final profile in profiles) {
      if (profile.id == activeId) return profile;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'profiles': profiles.map((item) => item.toJson()).toList(),
        'active_id': activeId,
        'enabled': enabled,
      };

  factory AiProfileCatalog.fromJson(Map<String, dynamic> value) {
    final raw = value['profiles'];
    if (raw is! List) throw const FormatException('Invalid AI profiles');
    final profiles = raw.map((item) {
      if (item is! Map) throw const FormatException('Invalid AI profile');
      return AiProfile.fromJson(Map<String, dynamic>.from(item));
    }).toList(growable: false);
    final ids = profiles.map((item) => item.id).toSet();
    if (ids.length != profiles.length) {
      throw const FormatException('Duplicate AI profile ids');
    }
    final active = value['active_id'];
    final activeId = active is String && ids.contains(active) ? active : null;
    return AiProfileCatalog(
      profiles: profiles,
      activeId: activeId,
      enabled: value['enabled'] == true && activeId != null,
    );
  }

  AiProfileCatalog copyWith({
    List<AiProfile>? profiles,
    String? activeId,
    bool clearActive = false,
    bool? enabled,
  }) {
    final nextProfiles = profiles ?? this.profiles;
    final nextActive = clearActive ? null : (activeId ?? this.activeId);
    final valid = nextActive != null &&
        nextProfiles.any((item) => item.id == nextActive);
    return AiProfileCatalog(
      profiles: nextProfiles,
      activeId: valid ? nextActive : null,
      enabled: valid && (enabled ?? this.enabled),
    );
  }
}
