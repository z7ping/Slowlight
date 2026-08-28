import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_config_store.dart';
import '../ai/ai_models.dart';
import '../ai/ai_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _store = AiConfigStore();
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _keyController = TextEditingController();

  AiConfig _config = const AiConfig();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _hasStoredKey = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _modelController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await _store.load();
      final key = await _store.loadApiKey(config.provider);
      if (!mounted) return;
      setState(() {
        _config = config;
        _endpointController.text = config.effectiveEndpoint;
        _modelController.text = config.effectiveModel;
        _hasStoredKey = key?.isNotEmpty == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _testResult = '读取安全存储失败：$e';
      });
    }
  }

  Future<void> _changeProvider(AiProviderType provider) async {
    String? key;
    try {
      key = await _store.loadApiKey(provider);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _config = _config.copyWith(provider: provider);
      _endpointController.text = provider.defaultEndpoint;
      _modelController.text = provider.defaultModel;
      _keyController.clear();
      _hasStoredKey = key?.isNotEmpty == true;
      _testResult = null;
    });
  }

  AiConfig _draft() => _config.copyWith(
        endpoint: _endpointController.text.trim(),
        model: _modelController.text.trim(),
      );

  Future<String> _effectiveKey() async {
    if (_keyController.text.trim().isNotEmpty) return _keyController.text.trim();
    return await _store.loadApiKey(_config.provider) ?? '';
  }

  String? _validate(AiConfig config, String key) {
    if (config.effectiveEndpoint.isEmpty) return '请填写接口地址';
    if (config.effectiveModel.isEmpty) return '请填写模型名';
    if (config.provider.apiKeyRequired && key.isEmpty) return '当前 AI 服务需要访问密钥';
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final draft = _draft();
      final key = await _effectiveKey();
      final error = _validate(draft, key);
      if (error != null) {
        _message(error);
        return;
      }

      await _store.save(draft);
      if (_keyController.text.trim().isNotEmpty) {
        await _store.saveApiKey(draft.provider, _keyController.text.trim());
      }
      if (!mounted) return;
      setState(() {
        _config = draft;
        _hasStoredKey = key.isNotEmpty;
        _keyController.clear();
      });
      _message('AI 配置已保存');
    } catch (e) {
      _message('保存 AI 配置失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final draft = _draft();
      final key = await _effectiveKey();
      final error = _validate(draft, key);
      if (error != null) {
        _message(error);
        return;
      }

      final text = await AiService(configStore: _store)
          .testConfiguration(draft, apiKey: key);
      if (!mounted) return;
      setState(() => _testResult = '连接成功：$text');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearKey() async {
    try {
      await _store.clearApiKey(_config.provider);
      if (!mounted) return;
      setState(() {
        _keyController.clear();
        _hasStoredKey = false;
      });
      _message('已清除当前 AI 服务的访问密钥');
    } catch (e) {
      _message('清除访问密钥失败：$e');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                FxCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用 AI'),
                        subtitle: const Text('AI 服务与本地/云端数据模式互不绑定'),
                        value: _config.enabled,
                        onChanged: (value) =>
                            setState(() => _config = _config.copyWith(enabled: value)),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AiProviderType>(
                        value: _config.provider,
                        decoration: const InputDecoration(labelText: 'AI 服务'),
                        items: AiProviderType.values
                            .map((item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item.label),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) _changeProvider(value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _endpointController,
                        decoration: const InputDecoration(
                          labelText: '接口地址',
                          hintText: '例如 http://localhost:11434/v1',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: '模型',
                          hintText: '例如 qwen3:8b',
                        ),
                      ),
                      if (_config.provider != AiProviderType.ollama) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _keyController,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: _config.provider == AiProviderType.compatible
                                ? '访问密钥（可选）'
                                : '访问密钥',
                            hintText: _hasStoredKey
                                ? '已安全保存；留空表示保持原值'
                                : '仅保存在本机安全存储',
                          ),
                        ),
                        if (_hasStoredKey)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _clearKey,
                              child: const Text('清除已保存密钥'),
                            ),
                          ),
                      ],
                      if (kIsWeb) ...[
                        const SizedBox(height: 8),
                        Text(
                          '网页版使用访问密钥时，请使用 HTTPS 或本机 localhost 环境。',
                          style: TextStyle(
                            fontSize: AppTheme.textXs,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FxButton(
                        label: _testing ? '测试中…' : '测试连接',
                        variant: FxButtonVariant.secondary,
                        onPressed: _testing || _saving ? null : _test,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FxButton(
                        label: _saving ? '保存中…' : '保存',
                        onPressed: _saving || _testing ? null : _save,
                      ),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: AppTheme.textMd,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
