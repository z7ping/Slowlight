import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_config_store.dart';
import '../ai/ai_models.dart';
import '../ai/ai_service.dart';
import '../ui/fx.dart';

/// One screen: profile list and the selected profile's editor.
class AiSettingsScreen extends StatefulWidget {
  final AiConfigStore? store;

  const AiSettingsScreen({super.key, this.store});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late final AiConfigStore _store;
  final _nameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _keyController = TextEditingController();

  AiProfileCatalog _catalog = const AiProfileCatalog(
    profiles: [], activeId: null, enabled: false,
  );
  AiProfile? _selected;
  AiProfile? _savedSelected;
  bool _loading = true;
  bool _mutating = false;
  bool _testing = false;
  bool _hasStoredKey = false;
  bool _showOptionalKey = false;
  String? _loadError;
  String? _saveError;
  String? _testResult;
  int _revision = 0;

  bool get _busy => _loading || _mutating || _testing;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? AiConfigStore();
    for (final c in [_nameController, _endpointController, _modelController, _keyController]) {
      c.addListener(_edited);
    }
    _load();
  }

  @override
  void dispose() {
    _revision++;
    for (final c in [_nameController, _endpointController, _modelController, _keyController]) {
      c.dispose();
    }
    super.dispose();
  }

  void _edited() {
    _revision++;
    if (mounted && (_testResult != null || _saveError != null)) {
      setState(() {
        _testResult = null;
        _saveError = null;
      });
    }
  }

  bool get _dirty {
    final p = _selected, saved = _savedSelected;
    if (p == null) return false;
    if (saved == null) return true;
    return p.config.provider != saved.config.provider ||
        _nameController.text.trim() != saved.name ||
        _endpointController.text.trim() != saved.config.effectiveEndpoint ||
        _modelController.text.trim() != saved.config.effectiveModel ||
        _keyController.text.trim().isNotEmpty;
  }

  AiProfile get _draft {
    final p = _selected!;
    return p.copyWith(
      name: _nameController.text.trim(),
      config: p.config.copyWith(
        endpoint: _endpointController.text.trim(),
        model: _modelController.text.trim(),
        enabled: false,
      ),
    );
  }

  void _putEditor(AiProfile profile, {required bool saved}) {
    _selected = profile;
    _savedSelected = saved ? profile : null;
    _nameController.text = profile.name;
    _endpointController.text = profile.config.effectiveEndpoint;
    _modelController.text = profile.config.effectiveModel;
    _keyController.clear();
    _hasStoredKey = false;
    _showOptionalKey = profile.config.provider.apiKeyRequired;
    _testResult = null;
    _saveError = null;
    _revision++;
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _loadError = null;
      _saveError = null;
      _testResult = null;
    });
    try {
      final catalog = await _store.loadCatalog();
      final selected = catalog.active ??
          (catalog.profiles.isNotEmpty ? catalog.profiles.first : null);
      final key = selected == null ? null : await _store.loadProfileKey(selected);
      if (!mounted || revision != _revision) return;
      setState(() {
        _catalog = catalog;
        if (selected != null) _putEditor(selected, saved: true);
        else {
          _selected = null;
          _savedSelected = null;
        }
        _hasStoredKey = key?.isNotEmpty == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loadError = '读取 AI 配置失败，请检查本机配置与安全存储。';
        _loading = false;
      });
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_busy) return false;
    if (!_dirty) return true;
    return await FxDialog.confirm(
      context: context,
      title: '放弃未保存的修改？',
      content: 'AI 配置尚未保存，离开后这些修改不会生效。',
      confirmText: '放弃修改',
      destructive: true,
      draftDiscard: true,
    ) == true;
  }

  Future<void> _select(AiProfile profile) async {
    if (_busy || _selected?.id == profile.id) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _mutating = true);
    try {
      final key = await _store.loadProfileKey(profile);
      if (!mounted) return;
      setState(() {
        _putEditor(profile, saved: true);
        _hasStoredKey = key?.isNotEmpty == true;
      });
    } catch (_) {
      _message('读取配置密钥失败，当前编辑内容未切换');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _add() async {
    if (_busy || !await _confirmDiscard() || !mounted) return;
    final id = 'p${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _putEditor(AiProfile(
        id: id,
        name: '新配置',
        config: const AiConfig(enabled: false),
      ), saved: false);
    });
  }

  Future<void> _changeProvider(AiProviderType provider) async {
    if (_busy || _selected == null ||
        _selected!.config.provider == provider) return;
    // Keep the edit and save/test actions locked through confirmation.
    setState(() => _mutating = true);
    try {
      if (_dirty && !await _confirmDiscardProvider() || !mounted) return;
      setState(() {
        _selected = _selected!.copyWith(
          config: AiConfig(
            provider: provider,
            endpoint: provider.defaultEndpoint,
            model: provider.defaultModel,
          ),
        );
        _endpointController.text = provider.defaultEndpoint;
        _modelController.text = provider.defaultModel;
        _keyController.clear();
        _hasStoredKey = false;
        _showOptionalKey = provider.apiKeyRequired;
        _testResult = null;
        _saveError = null;
        _revision++;
      });
      if (_savedSelected?.config.provider == provider) {
        try {
          final key = await _store.loadProfileKey(_savedSelected!);
          if (mounted && _selected?.config.provider == provider) {
            setState(() => _hasStoredKey = key?.isNotEmpty == true);
          }
        } catch (_) {
          _message('密钥读取失败，请重新核对');
        }
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<bool> _confirmDiscardProvider() async =>
      await FxDialog.confirm(
        context: context,
        title: '切换服务商？',
        content: '当前编辑尚未保存。切换会重新设置接口、模型和密钥输入。',
        confirmText: '放弃并切换',
        destructive: true,
        draftDiscard: true,
      ) == true;

  Future<String> _keyFor(AiProfile profile) async {
    if (profile.id == _selected?.id) {
      final typed = _keyController.text.trim();
      if (typed.isNotEmpty) return typed;
      // New drafts and provider changes must not borrow an old credential.
      if (_savedSelected == null ||
          _savedSelected!.config.provider != profile.config.provider) {
        return '';
      }
    }
    return await _store.loadProfileKey(profile) ?? '';
  }

  String? _validate(AiProfile profile, String key) {
    if (profile.config.effectiveEndpoint.isEmpty) return '请填写接口地址';
    if (profile.config.effectiveModel.isEmpty) return '请填写模型名';
    if (profile.config.provider.apiKeyRequired && key.isEmpty) {
      return '当前 AI 服务需要访问密钥';
    }
    return null;
  }

  Future<void> _save() async {
    if (_busy || _selected == null) return;
    final draft = _draft;
    if (draft.name.isEmpty) {
      setState(() => _saveError = '请填写配置名称');
      return;
    }
    setState(() {
      _mutating = true;
      _saveError = null;
    });
    try {
      final key = await _keyFor(draft);
      final error = _validate(draft, key);
      if (error != null) {
        if (mounted) setState(() => _saveError = error);
        return;
      }
      final profiles = [..._catalog.profiles];
      final index = profiles.indexWhere((p) => p.id == draft.id);
      if (index < 0) profiles.add(draft);
      else profiles[index] = draft;
      final updated = _catalog.copyWith(profiles: profiles);
      final providerChanged = _savedSelected != null &&
          _savedSelected!.config.provider != draft.config.provider;
      await _store.saveCatalog(
        updated,
        secretProfile: draft,
        newApiKey: _keyController.text.trim().isEmpty
            ? null : _keyController.text.trim(),
        // Existing ID-scoped key belongs to the previous provider.
        clearKey: providerChanged && _keyController.text.trim().isEmpty &&
            draft.id != 'legacy',
      );
      if (!mounted) return;
      setState(() {
        _catalog = updated;
        _putEditor(draft, saved: true);
        _hasStoredKey = key.isNotEmpty;
      });
      _message('AI 配置已保存');
    } catch (_) {
      if (mounted) setState(() => _saveError =
          '保存 AI 配置失败，请检查安全存储或本机设置权限后重试；草稿已保留。');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _activate(AiProfile profile) async {
    if (_busy) return;
    if (_selected?.id == profile.id && _dirty) {
      _message('请先保存当前编辑，再设为当前使用');
      return;
    }
    setState(() => _mutating = true);
    try {
      final key = await _store.loadProfileKey(profile);
      final error = _validate(profile, key ?? '');
      if (error != null) {
        _message('该配置尚不可用：$error');
        return;
      }
      final updated = _catalog.copyWith(activeId: profile.id, enabled: true);
      await _store.saveCatalog(updated);
      if (!mounted) return;
      setState(() {
        _catalog = updated;
        _testResult = null;
      });
      _message('已设为当前使用配置');
    } catch (_) {
      _message('切换配置失败，当前使用配置未确认，请重新加载核对');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    if (_busy) return;
    if (value && _catalog.active == null) {
      _message('请先选择一套配置');
      return;
    }
    setState(() => _mutating = true);
    try {
      if (value) {
        final profile = _catalog.active!;
        final key = await _store.loadProfileKey(profile);
        final error = _validate(profile, key ?? '');
        if (error != null) {
          _message('无法启用：$error');
          return;
        }
      }
      final updated = _catalog.copyWith(enabled: value);
      await _store.saveCatalog(updated);
      if (!mounted) return;
      setState(() {
        _catalog = updated;
        _testResult = null;
      });
    } catch (_) {
      _message('切换 AI 状态失败，请重新加载核对');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || _selected == null) return;
    final target = _selected!;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '删除配置？',
      content: '删除「${_nameController.text}」后无法恢复。若正在使用此配置，AI 将同时关闭。',
      confirmText: '确认删除',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    if (_savedSelected == null) {
      final next = _catalog.active ??
          (_catalog.profiles.isNotEmpty ? _catalog.profiles.first : null);
      setState(() {
        if (next == null) { _selected = null; _savedSelected = null; }
        else _putEditor(next, saved: true);
      });
      if (next != null) await _selectAfterDiscard(next);
      return;
    }
    setState(() => _mutating = true);
    try {
      final nextList = _catalog.profiles.where((p) => p.id != target.id).toList();
      final wasActive = target.id == _catalog.activeId;
      final updated = _catalog.copyWith(
        profiles: nextList, clearActive: wasActive,
        enabled: wasActive ? false : _catalog.enabled,
      );
      await _store.saveCatalog(updated, deletedProfile: target);
      final next = updated.active ??
          (updated.profiles.isNotEmpty ? updated.profiles.first : null);
      final key = next == null ? null : await _store.loadProfileKey(next);
      if (!mounted) return;
      setState(() {
        _catalog = updated;
        if (next == null) { _selected = null; _savedSelected = null; }
        else _putEditor(next, saved: true);
        _hasStoredKey = key?.isNotEmpty == true;
      });
      _message('配置已删除');
    } catch (_) {
      _message('删除结果未确认，请重新加载核对后再操作');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _selectAfterDiscard(AiProfile profile) async {
    try {
      final key = await _store.loadProfileKey(profile);
      if (mounted && _selected?.id == profile.id) {
        setState(() => _hasStoredKey = key?.isNotEmpty == true);
      }
    } catch (_) {
      _message('读取配置密钥失败，请重新加载');
    }
  }

  Future<void> _clearKey() async {
    if (_busy || _savedSelected == null || !_hasStoredKey) return;
    setState(() => _mutating = true);
    try {
      final confirmed = await FxDialog.confirm(
        context: context,
        title: '清除访问密钥？',
        content: '仅清除此配置的密钥，不影响同服务商的其他配置。',
        confirmText: '清除密钥',
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
      await _store.saveCatalog(
        _catalog,
        secretProfile: _savedSelected,
        clearKey: true,
      );
      if (!mounted) return;
      setState(() {
        _hasStoredKey = false;
        _keyController.clear();
        _testResult = null;
        _saveError = null;
      });
      _message('已清除当前配置的密钥');
    } catch (_) {
      _message('清除密钥结果未确认，请核对安全存储');
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _test() async {
    if (_busy || _selected == null) return;
    final draft = _draft;
    final revision = ++_revision;
    String secret = '';
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      secret = await _keyFor(draft);
      final error = _validate(draft, secret);
      if (error != null) {
        if (mounted && revision == _revision) {
          setState(() => _testResult = '连接失败：$error');
        }
        return;
      }
      final result = await AiService(configStore: _store)
          .testConfiguration(draft.config, apiKey: secret);
      if (mounted && revision == _revision) {
        setState(() => _testResult = '连接成功：$result');
      }
    } catch (e) {
      final raw = e.toString();
      final safe = secret.isEmpty ? raw : raw.replaceAll(secret, '[密钥已隐藏]');
      if (mounted && revision == _revision) {
        setState(() => _testResult = '连接失败：$safe');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String get _privacyText {
    final host = Uri.tryParse(_endpointController.text.trim())?.host.toLowerCase() ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1'
        ? '当前接口地址指向本机。AI 请求将发送到配置的本机服务。'
        : 'AI 请求将发送到配置的接口地址；请确认第三方服务和数据使用范围。';
  }

  void _message(String text) {
    if (mounted) FxNotice.showContent(context, Text(text));
  }

  Widget _profileList() {
    final profiles = [..._catalog.profiles];
    if (_savedSelected == null && _selected != null) profiles.add(_selected!);
    return FxCard(
      expanded: true,
      padding: EdgeInsets.zero,
      child: profiles.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('暂无配置', style: SlowlightTypography.secondary(context)),
            )
          : Column(
              children: [
                for (var i = 0; i < profiles.length; i++)
                  FxListTile(
                    key: ValueKey('ai.profile.${profiles[i].id}'),
                    density: FxListTileDensity.detailed,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minTileHeight: 58,
                    title: profiles[i].name,
                    subtitle: '${profiles[i].config.provider.label} · ${profiles[i].config.effectiveModel.isEmpty ? "待填写模型" : profiles[i].config.effectiveModel}${_savedSelected == null && _selected?.id == profiles[i].id ? " · 未保存" : ""}',
                    trailing: _catalog.activeId == profiles[i].id
                        ? Text(_catalog.enabled ? '使用中' : '默认配置',
                            style: SlowlightTypography.caption(context))
                        : FxButton(
                            label: '设为当前',
                            size: FxButtonSize.sm,
                            variant: FxButtonVariant.outline,
                            onPressed: _busy || _savedSelected == null &&
                                    _selected?.id == profiles[i].id
                                ? null
                                : () => _activate(profiles[i]),
                          ),
                    onTap: _busy ? null : () => _select(profiles[i]),
                    selected: _selected?.id == profiles[i].id,
                    selectedTileColor: Theme.of(context)
                        .colorScheme.primary.withValues(alpha: .06),
                    showDivider: i != profiles.length - 1,
                  ),
              ],
            ),
    );
  }

  Widget _editor() {
    final selected = _selected;
    if (selected == null) return const SizedBox.shrink();
    final provider = selected.config.provider;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('编辑配置${_dirty ? " · 未保存" : ""}',
                  style: SlowlightTypography.secondary(context)
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
            FxButton(
              label: '删除',
              size: FxButtonSize.sm,
              variant: FxButtonVariant.ghost,
              onPressed: _busy ? null : _delete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          ignoring: _busy,
          child: FxCard(
            expanded: true,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FxInput(controller: _nameController, label: '配置名称'),
                const SizedBox(height: 12),
                Text('服务商', style: SlowlightTypography.secondary(context)),
                const SizedBox(height: 6),
                FxSelect<AiProviderType>(
                  value: provider,
                  options: AiProviderType.values
                      .map((p) => FxSelectOption(value: p, label: p.label))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) _changeProvider(value);
                  },
                ),
                const SizedBox(height: 12),
                FxInput(controller: _endpointController, label: '接口地址',
                    placeholder: '例如 http://localhost:11434/v1'),
                const SizedBox(height: 12),
                FxInput(controller: _modelController, label: '模型名称',
                    placeholder: '例如 qwen3:8b'),
                if (provider.apiKeyRequired || _showOptionalKey || _hasStoredKey) ...[
                  const SizedBox(height: 12),
                  FxInput(
                    controller: _keyController,
                    label: provider.apiKeyRequired
                        ? '访问密钥' : '访问密钥（可选）',
                    placeholder: _hasStoredKey
                        ? '已安全保存；留空保持原值' : '仅保存在本机安全存储',
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                  if (_hasStoredKey)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FxButton(
                        label: '清除已保存密钥',
                        size: FxButtonSize.sm,
                        variant: FxButtonVariant.ghost,
                        onPressed: _busy ? null : _clearKey,
                      ),
                    ),
                ] else ...[
                  FxButton(
                    label: '访问密钥（可选）',
                    size: FxButtonSize.sm,
                    variant: FxButtonVariant.ghost,
                    onPressed: () => setState(() => _showOptionalKey = true),
                  ),
                ],
                const SizedBox(height: 8),
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
                  const SizedBox(height: 6),
                  Text('网页版使用访问密钥时，请使用 HTTPS 或本机 localhost 环境。',
                      style: SlowlightTypography.caption(context)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_saveError != null) ...[
          Text(_saveError!,
            style: SlowlightTypography.secondary(context).copyWith(
                color: theme.colorScheme.error)),
          const SizedBox(height: 8),
        ],
        if (_testResult != null) ...[
          SelectableText(_testResult!, style: SlowlightTypography.secondary(context)),
          if (_testResult!.startsWith('连接失败'))
            Align(
              alignment: Alignment.centerRight,
              child: FxButton(
                label: '查看错误详情',
                size: FxButtonSize.sm,
                variant: FxButtonVariant.ghost,
                onPressed: () => FxNotice.errorWithDetails(
                    context, 'AI 连接测试失败', _testResult!),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _catalog.active;
    return WillPopScope(
      onWillPop: _confirmDiscard,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const FxPageHeader(title: 'AI 服务'),
              Expanded(
                child: _loading
                    ? const Center(child: FxCircularProgress())
                    : _loadError != null
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_loadError!),
                              const SizedBox(height: 12),
                              FxButton(label: '重新加载', onPressed: _load),
                            ]),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              FxCard(
                                expanded: true,
                                padding: const EdgeInsets.all(12),
                                child: FxSwitch(
                                  label: '启用 AI',
                                  description: active == null
                                      ? '尚未选择当前使用配置'
                                      : '当前使用：${active.name}',
                                  value: _catalog.enabled,
                                  onChanged: _busy ? null : _toggleEnabled,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(children: [
                                Expanded(
                                  child: Text('服务配置',
                                    style: SlowlightTypography.secondary(context)
                                        .copyWith(fontWeight: FontWeight.w600)),
                                ),
                                FxButton(
                                  label: '添加配置',
                                  variant: FxButtonVariant.outline,
                                  size: FxButtonSize.sm,
                                  onPressed: _busy ? null : _add,
                                ),
                              ]),
                              const SizedBox(height: 8),
                              _profileList(),
                              const SizedBox(height: 16),
                              _editor(),
                            ],
                          ),
              ),
              if (!_loading && _loadError == null && _selected != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Expanded(
                      flex: 2,
                      child: FxButton(
                        label: _testing ? '测试中…' : '测试连接',
                        variant: FxButtonVariant.secondary,
                        onPressed: _busy ? null : _test,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: FxButton(
                        label: _mutating ? '保存中…' : '保存配置',
                        onPressed: _busy ? null : _save,
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
