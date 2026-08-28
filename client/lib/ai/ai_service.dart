import 'dart:convert';

import 'package:http/http.dart' as http;

import '../repositories/reflection_repository.dart';
import 'ai_config_store.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_provider_factory.dart';

class AiService {
  final AiConfigStore configStore;
  final AiProviderFactory factory;
  final http.Client? client;

  AiService({
    AiConfigStore? configStore,
    AiProviderFactory? factory,
    this.client,
  })  : configStore = configStore ?? AiConfigStore(),
        factory = factory ?? const AiProviderFactory();

  Future<AiConfig> loadConfig() => configStore.load();

  Future<bool> isEnabled() async => (await configStore.load()).enabled;

  Future<AiResponse> complete(List<AiMessage> messages) async {
    final config = await configStore.load();
    if (!config.enabled) {
      throw const AiProviderException('AI 功能未启用');
    }
    final key = await configStore.loadApiKey(config.provider) ?? '';
    final provider = factory.create(config: config, apiKey: key, client: client);
    return provider.complete(AiRequest(messages: messages));
  }

  /// 对 Review 做解释和提问。
  ///
  /// 当前事实和模式来自系统；最近 Reflection 来自用户本人。AI 必须把后者视为
  /// 更高优先级的第一方解释，而不是用统计替用户重新定义感受。
  Future<String> reflectOnReview(Map<String, dynamic> review) async {
    final facts = review['facts'] is Map
        ? Map<String, dynamic>.from(review['facts'] as Map)
        : <String, dynamic>{};
    final patterns = review['patterns'] is Map
        ? Map<String, dynamic>.from(review['patterns'] as Map)
        : <String, dynamic>{};

    var reflections = <Map<String, dynamic>>[];
    try {
      final recent = await ReflectionRepository().recent(limit: 8);
      reflections = recent
          .map((entry) => {
                'entry_type': entry.entryType,
                'dimension_key': entry.dimensionKey,
                'content': entry.content,
                'created_at': entry.createdAt.toIso8601String(),
              })
          .toList();
    } catch (_) {
      // Reflection 不可用不应阻断一次 AI 解读。
    }

    final response = await complete([
      const AiMessage.system(
        '你是所行映我的行为回顾助手。只基于提供的数据描述事实、指出可能的模式并提出开放问题。'
        'recent_reflections 是用户本人过去写下的解释和感受，其优先级高于你对统计的猜测；不要反驳或改写用户的自我解释。'
        '不要评价用户好坏，不要制造焦虑，不要直接命令用户该做什么，不要假装知道数据中没有的信息。'
        '如果系统数据与用户过去的解释看起来有张力，只指出这种张力并提问。回答简洁。',
      ),
      AiMessage.user(jsonEncode({
        'facts': facts,
        'patterns': patterns,
        'recent_reflections': reflections,
      })),
    ]);
    return response.text;
  }

  Future<String> testConfiguration(AiConfig config, {String apiKey = ''}) async {
    final provider = factory.create(config: config, apiKey: apiKey, client: client);
    final response = await provider.complete(const AiRequest(
      messages: [
        AiMessage.system('这是连接测试。'),
        AiMessage.user('只回复 OK'),
      ],
      maxTokens: 16,
      temperature: 0,
    ));
    return response.text;
  }
}
