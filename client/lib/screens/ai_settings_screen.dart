import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_config_store.dart';
import '../ai/ai_models.dart';
import '../ai/ai_service.dart';
import '../ui/fx.dart';

class AiSettingsScreen extends StatefulWidget {
  final AiConfigStore? store;

  const AiSettingsScreen({super.key, this.store});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final AiConfigStore _store;
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _keyController = TextEditingController();

  AiConfig _config = const AiConfig();
  AiConfig _savedConfig = const AiConfig();
  String? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _hasStoredKey = false;
  bool _providerSwitching = false;
  int _loadVersion = 0;
  String? _testResult;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? AiConfigStore();
    for (final controller in [_endpointController, _modelController, _keyController]) {
      controller.addListener(_onDraftEdited);
    }
    _load();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _modelController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _onDraftEdited() {
    if (mounted && (_testResult != null || _saveError != null)) {
      setState(() {
        _testResult = null;
        _saveError = null;
      });
    }
  }

  bool get _isDirty =>
      _config.enabled != _savedConfig.enabled ||
      _config.provider != _savedConfig.provider ||
      _endpointController.text.trim() != _savedConfig.effectiveEndpoint ||
      _modelController.text.trim() != _savedConfig.effectiveModel ||
      _keyController.text.trim().isNotEmpty;

  Future<bool> _confirmLeave() async {
    if (_saving || _testing || _providerSwitching) return false;
    if (!_isDirty) return true;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '放弃未保存的修改？',
      content: 'AI 配置尚未保存，离开后这些修改不会生效。',
      confirmText: '放弃修改',
      destructive: true,
    );
    return confirmed == true;
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _loadError = null;
      _testResult = null;
      _saveError = null;
    });
    try {
      final config = await _store.load();
      final key = await _store.loadApiKey(config.provider);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _savedConfig = config;
        _config = config;
        _endpointController.text = config.effectiveEndpoint;
        _modelController.text = config.effectiveModel;
        _keyController.clear();
        _hasStoredKey = key?.isNotEmpty == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadError = '读取 AI 配置失败：$e';
      });
    }
  }

  Future<void> _changeProvider(AiProviderType provider) async {
    if (provider == _config.provider || _saving || _testing || _providerSwitching) return;
    setState(() => _providerSwitching = true);
    try {
      if (_isDirty) {
        final confirmed = await FxDialog.confirm(
          context: context,
          title: '切换服务商？',
          content: '当前 AI 配置尚未保存。切换后会放弃本次编辑的内容。',
          confirmText: '放弃并切换',
          destructive: true,
        );
        if (confirmed != true || !mounted) return;
      }
      final key = await _store.loadApiKey(provider);
      if (!mounted) return;
      setState(() {
        _testResult = null;
        _saveError = null;
        _config = _savedConfig.copyWith(provider: provider);
        _endpointController.text = provider.defaultEndpoint;
        _modelController.text = provider.defaultModel;
        _keyController.clear();
        _hasStoredKey = key?.isNotEmpty == true;
      });
    } catch (_) {
      if (mounted) _message('读取服务商密钥失败，请检查安全存储后重试');
    } finally {
      if (mounted) setState(() => _providerSwitching = false);
    }
  }

  AiConfig _draft() => _config.copyWith(
    endpoint: _endpointController.text.trim(),
    model: _modelController.text.trim(),
  );

  Future<String> _effectiveKey() async {
    if (_keyController.text.trim().isNotEmpty) {
      return _keyController.text.trim();
    }
    return await _store.loadApiKey(_config.provider) ?? '';
  }

  String? _validate(AiConfig config, String key, {bool testing = false}) {
    // 关闭 AI 可以无密钥保存；仅启用或主动测试时校验服务连接参数。
    if (!config.enabled && !testing) return null;
    if (config.effectiveEndpoint.isEmpty) return '请填写接口地址';
    if (config.effectiveModel.isEmpty) return '请填写模型名';
    if (config.provider.apiKeyRequired && key.isEmpty) return '当前 AI 服务需要访问密钥';
    return null;
  }

  Future<void> _save() async {
    if (_saving || _testing || _providerSwitching) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final draft = _draft();
      final key = await _effectiveKey();
      final error = _validate(draft, key);
      if (error != null) {
        setState(() => _saveError = error);
        return;
      }

      // 先提交安全存储的密钥，再提交生效配置；失败不清空草稿。
      await _store.saveConfiguration(
        draft,
        newApiKey: _keyController.text.trim().isEmpty
            ? null
            : _keyController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _config = draft;
        _savedConfig = draft;
        _hasStoredKey = key.isNotEmpty;
        _testResult = null;
        _keyController.clear();
      });
      _message('AI 配置已保存');
    } catch (_) {
      if (mounted) {
        setState(() => _saveError =
            '保存 AI 配置失败，请检查安全存储或本机设置权限后重试；草稿已保留。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_testing || _saving || _providerSwitching) return;
    String secret = '';
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final draft = _draft();
      secret = await _effectiveKey();
      final error = _validate(draft, secret, testing: true);
      if (error != null) {
        if (mounted) setState(() => _testResult = '连接失败：$error');
        return;
      }

      final text = await AiService(
        configStore: _store,
      ).testConfiguration(draft, apiKey: secret);
      if (!mounted) return;
      setState(() => _testResult = '连接成功：$text');
    } catch (e) {
      if (!mounted) return;
      final details = e.toString();
      // 第三方 HTTP 异常可能回显请求内容；不得展示已输入/已存储密钥。
      final safeDetails = secret.isEmpty
          ? details
          : details.replaceAll(secret, '[密钥已隐藏]');
      setState(() => _testResult = '连接失败：$safeDetails');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearKey() async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '清除访问密钥？',
      content: '清除后当前服务商可能无法继续使用，之后可以重新填写密钥。',
      confirmText: '清除密钥',
      destructive: true,
    );
    if (confirmed != true || !mounted || _saving || _testing || _providerSwitching) return;
    try {
      await _store.clearApiKey(_config.provider);
      if (!mounted) return;
      setState(() {
        _keyController.clear();
        _hasStoredKey = false;
      });
      _message('已清除当前 AI 服务的访问密钥');
    } catch (_) {
      _message('清除访问密钥失败，请检查安全存储后重试');
    }
  }

  String get _privacyText {
    final endpoint = _endpointController.text.trim();
    final uri = Uri.tryParse(endpoint);
    final host = uri?.host.toLowerCase() ?? '';
    final local = host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1';
    return local
        ? '当前接口地址指向本机。AI 请求将发送到配置的本机服务。'
        : 'AI 请求将发送到配置的接口地址；请确认第三方服务和数据使用范围。';
  }

  void _message(String text) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const FxPageHeader(title: 'AI 设置'),
            Expanded(
              child:
                  _loading
                      ? const Center(child: FxCircularProgress())
                      : _loadError != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_loadError!, style: SlowlightTypography.secondary(context)),
                                    const SizedBox(height: 12),
                                    FxButton(label: '重新加载', onPressed: _load),
                                  ],
                                ),
                              ),
                            )
                          : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          IgnorePointer(
                            ignoring: _saving || _testing || _providerSwitching,
                            child: FxCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FxSwitch(
                                  label: '启用 AI',
                                  description: 'AI 服务与本地/云端数据模式互不绑定',
                                  value: _config.enabled,
                                  onChanged:
                                      (value) => setState(
                                        () =>
                                            _config = _config.copyWith(
                                              enabled: value,
                                            ),
                                      ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'AI 服务',
                                  style: SlowlightTypography.secondary(
                                    context,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                FxSelect<AiProviderType>(
                                  value: _config.provider,
                                  options: AiProviderType.values
                                      .map(
                                        (item) => FxSelectOption(
                                          value: item,
                                          label: item.label,
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: _providerSwitching || _saving || _testing
                                      ? null
                                      : (value) {
                                          if (value != null) _changeProvider(value);
                                        },
                                ),
                                const SizedBox(height: 12),
                                FxInput(
                                  controller: _endpointController,
                                  label: '接口地址',
                                  placeholder: '例如 http://localhost:11434/v1',
                                ),
                                const SizedBox(height: 12),
                                FxInput(
                                  controller: _modelController,
                                  label: '模型',
                                  placeholder: '例如 qwen3:8b',
                                ),
                                if (_config.provider !=
                                    AiProviderType.ollama) ...[
                                  const SizedBox(height: 12),
                                  FxInput(
                                    controller: _keyController,
                                    label:
                                        _config.provider ==
                                                AiProviderType.compatible
                                            ? '访问密钥（可选）'
                                            : '访问密钥',
                                    placeholder:
                                        _hasStoredKey
                                            ? '已安全保存；留空表示保持原值'
                                            : '仅保存在本机安全存储',
                                    obscureText: true,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                  ),
                                  if (_hasStoredKey)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FxButton(
                                        label: '清除已保存密钥',
                                        variant: FxButtonVariant.ghost,
                                        size: FxButtonSize.sm,
                                        onPressed: _saving || _testing || _providerSwitching
                                            ? null
                                            : _clearKey,
                                      ),
                                    ),
                                ],
                                const SizedBox(height: 12),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _endpointController,
                                  builder: (context, _, __) => Text(
                                    _privacyText,
                                    style: SlowlightTypography.caption(context).copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (kIsWeb) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '网页版使用访问密钥时，请使用 HTTPS 或本机 localhost 环境。',
                                    style: SlowlightTypography.caption(
                                      context,
                                    ).copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
                          if (_saveError != null) ...[
                            const SizedBox(height: 12),
                            Text(_saveError!,
                                style: SlowlightTypography.secondary(context).copyWith(
                                    color: theme.colorScheme.error)),
                          ],
                          if (_testResult != null) ...[
                            const SizedBox(height: 12),
                            SelectableText(
                              _testResult!,
                              style: SlowlightTypography.secondary(
                                context,
                              ).copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (_testResult!.startsWith('连接失败'))
                              Align(
                                alignment: Alignment.centerRight,
                                child: FxButton(
                                  label: '查看错误详情',
                                  size: FxButtonSize.sm,
                                  variant: FxButtonVariant.ghost,
                                  onPressed: () => FxNotice.errorWithDetails(
                                    context,
                                    'AI 连接测试失败',
                                    _testResult!,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
