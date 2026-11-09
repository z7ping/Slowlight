import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// CalDAV 配置页面
class CalDAVScreen extends StatefulWidget {
  const CalDAVScreen({super.key});

  @override
  State<CalDAVScreen> createState() => _CalDAVScreenState();
}

/// 保留旧 CalDAV 表单的验证语义；视觉统一不应削弱校验。
/// 真实数据源为空/失败时不得展示“0 个已同步任务”。
String calDavSyncedTaskLabel(
  Map<String, dynamic>? status, {
  required bool loading,
  required bool stale,
}) {
  if (status == null) return loading ? '读取中…' : '状态未知';
  final count = status['task_count'];
  if (count == null) return '状态未知';
  return '$count 个${stale ? '（上次记录）' : ''}';
}

abstract final class CalDavFormValidation {
  static String? serverUrl(String value) {
    if (value.trim().isEmpty) return '请输入服务器地址';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      return '请输入有效地址（以 http:// 或 https:// 开头）';
    }
    return null;
  }

  static String? username(String value) =>
      value.trim().isEmpty ? '请输入用户名' : null;

  static String? password(String value) =>
      value.isEmpty ? '请输入密码或访问令牌' : null;

  static String? paths(String value) =>
      value.trim().isEmpty ? '请至少输入一个项目路径' : null;
}

class _CalDAVScreenState extends State<CalDAVScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pathsController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _syncing = false;
  bool _statusLoading = false;
  String? _statusError;
  bool _testing = false;
  bool _configured = false;
  bool _configReadFailed = false;
  bool _hasStoredPassword = false;
  String _savedBaseUrl = '';
  String _savedUsername = '';
  String? _connectionFeedback;
  bool _obscurePassword = true;

  Map<String, dynamic>? _status;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathsController.dispose();
    super.dispose();
  }

  bool get _canReusePassword => _configured && _hasStoredPassword &&
      _baseUrlController.text.trim() == _savedBaseUrl &&
      _usernameController.text.trim() == _savedUsername;

  Future<void> _loadConfig() async {
    if (mounted) setState(() { _loading = true; _configReadFailed = false; });
    try {
      final config = await ApiService.getCalDAVConfig();
      if (!mounted) return;
      setState(() {
        _configured = config['configured'] == true;
        _configReadFailed = false;
        _lastError = null;
        _hasStoredPassword = false;
        if (_configured && config['value'] != null) {
          final value = config['value'];
          if (value is Map) {
            _baseUrlController.text = value['base_url'] ?? '';
            _usernameController.text = value['username'] ?? '';
            _savedBaseUrl = _baseUrlController.text.trim();
            _savedUsername = _usernameController.text.trim();
            _hasStoredPassword = value['has_password'] == true;
            _passwordController.clear();
            if (value['paths'] != null) {
              _pathsController.text = (value['paths'] as List).join('\n');
            }
          }
        }
        _loading = false;
      });

      if (_configured) {
        _loadStatus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _configReadFailed = true;
        _lastError = e.toString();
      });
    }
  }

  Future<void> _loadStatus() async {
    if (_statusLoading) return;
    if (mounted) setState(() {
      _statusLoading = true;
      _statusError = null;
    });
    try {
      final status = await ApiService.getCalDAVStatus();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _statusError = error.toString());
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _lastError = null;
      _connectionFeedback = null;
    });

    try {
      final result = await ApiService.testCalDAVConnection(
        baseUrl: _baseUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        paths:
            _pathsController.text
                .split('\n')
                .where((p) => p.trim().isNotEmpty)
                .map((p) => p.trim())
                .toList(),
      );

      if (mounted) {
        final connected = result['connected'] ?? false;
        final queryOk = result['query_ok'] ?? false;
        final taskCount = result['task_count'] ?? 0;
        final error = result['error'] as String?;

        String message;
        FxNoticeVariant noticeVariant;
        if (connected && queryOk) {
          message = '连接成功！找到 $taskCount 个任务';
          noticeVariant = FxNoticeVariant.success;
        } else if (connected) {
          message = '已连接，但查询失败：${error ?? "未知错误"}';
          noticeVariant = FxNoticeVariant.warning;
        } else {
          message = '连接失败：${error ?? "未知错误"}';
          noticeVariant = FxNoticeVariant.destructive;
        }

        setState(() => _connectionFeedback = message);

        FxNotice.showContent(
          context,
          Text(message),
          duration: const Duration(seconds: 3),
          variant: noticeVariant,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectionFeedback = '测试失败：$e');
        FxNotice.showContent(
          context,
          Text('测试失败：$e'),
          duration: const Duration(seconds: 3),
          variant: FxNoticeVariant.destructive,
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _lastError = null;
    });

    try {
      await ApiService.saveCalDAVConfig(
        baseUrl: _baseUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        paths:
            _pathsController.text
                .split('\n')
                .where((p) => p.trim().isNotEmpty)
                .map((p) => p.trim())
                .toList(),
      );

      if (!mounted) return;
      setState(() {
        _configured = true;
        _hasStoredPassword = true;
        _savedBaseUrl = _baseUrlController.text.trim();
        _savedUsername = _usernameController.text.trim();
        _passwordController.clear();
        _saving = false;
      });

      _loadStatus();

      FxNotice.showContent(
        context,
        Text('配置保存成功！系统将每5分钟自动同步'),
        duration: Duration(seconds: 3),
        variant: FxNoticeVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _lastError = e.toString();
      });

      FxNotice.showContent(
        context,
        Text('保存失败：$e'),
        duration: const Duration(seconds: 3),
        variant: FxNoticeVariant.destructive,
      );
    }
  }

  Future<void> _syncNow() async {
    if (!_configured || _syncing || _saving || _testing) return;
    setState(() => _syncing = true);
    try {
      final result = await ApiService.syncCalDAV();
      if (mounted) {
        final created = result['tasks_created'] ?? 0;
        final updated = result['tasks_updated'] ?? 0;
        final skipped = result['tasks_skipped'] ?? 0;
        final errors = result['errors'] as List?;

        String message = '同步完成：创建 $created，更新 $updated，跳过 $skipped';
        if (errors != null && errors.isNotEmpty) {
          message += '\n错误：${errors.length} 个';
        }

        FxNotice.showContent(
          context,
          Text(message),
          duration: const Duration(seconds: 5),
          variant:
              errors?.isNotEmpty == true
                  ? FxNoticeVariant.warning
                  : FxNoticeVariant.success,
        );

        await _loadStatus();
      }
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(
          context,
          Text('同步失败：$e'),
          duration: const Duration(seconds: 3),
          variant: FxNoticeVariant.destructive,
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: 'CalDAV 同步',
              actionIcon: _configured ? LucideIcons.refreshCw : null,
              actionTooltip: '刷新同步状态',
              onAction: _configured && !_statusLoading ? _loadStatus : null,
            ),
            Expanded(
              child: _loading
                  ? const Center(child: FxCircularProgress())
                  : _configReadFailed
                      ? FxEmptyState(
                          icon: LucideIcons.circleAlert,
                          title: '配置状态未确认',
                          subtitle: '无法读取 CalDAV 配置，请检查连接后重试。',
                          action: FxButton(label: '重新读取', onPressed: _loadConfig),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _configured ? _buildStatusCard() : _buildInitialSummary(),
                              const SizedBox(height: SlowlightSpacing.xl),
                              _buildConfigForm(),
                              const SizedBox(height: SlowlightSpacing.xl),
                              _buildInfoCard(),
                              if (_lastError != null) ...[
                                const SizedBox(height: SlowlightSpacing.xl),
                                _buildErrorCard(),
                              ],
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialSummary() {
    final theme = Theme.of(context);
    return FxCard(
      padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
      child: Row(
        children: [
          const Icon(LucideIcons.calendarDays, size: SlowlightIconSize.lg),
          const SizedBox(width: SlowlightSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('未配置', style: SlowlightTypography.cardTitle(context)),
                const SizedBox(height: SlowlightSpacing.xs),
                Text('填写服务器和访问凭据，测试连接后即可保存。',
                  style: SlowlightTypography.caption(context).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final theme = Theme.of(context);
    return FxCard(
      padding: EdgeInsets.zero,
      child: FxExpansionTile(
        leading: const Icon(LucideIcons.info, size: SlowlightIconSize.md),
        title: Text('如何配置 · 兼容服务与路径说明',
          style: SlowlightTypography.secondary(context)),
        children: [
          Text('1. 获取服务器地址及 CalDAV 账号或访问令牌。\n'
              '2. 填写任务项目路径，每行一个。\n'
              '3. 测试连接并确认能查询任务后保存配置。',
            style: SlowlightTypography.secondary(context)),
          const SizedBox(height: SlowlightSpacing.md),
          Text('Vikunja、Nextcloud Tasks、Baïkal、Radicale 等服务的实际兼容范围'
              '以连接测试和任务查询结果为准。',
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          const SizedBox(height: SlowlightSpacing.md),
          Text('Vikunja 项目路径一般可从项目设置中复制；'
              '不同服务路径格式可能不同，请使用服务端提供的地址。',
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        ],
      ),
    );
  }

  /// 原生 FormField 保留 Form.validate() 规则；视觉交给现有 FxInput。
  Widget _validatedInput({
    required TextEditingController controller,
    required String label,
    required String placeholder,
    required String? Function(String value) validate,
    IconData? icon,
    Widget? trailing,
    bool obscureText = false,
    int maxLines = 1,
  }) {
    return FormField<String>(
      validator: (_) => validate(controller.text),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FxInput(
            controller: controller,
            label: label,
            placeholder: placeholder,
            enabled: !_saving && !_testing,
            leading: icon == null ? null : Icon(icon, size: SlowlightIconSize.md),
            trailing: trailing,
            obscureText: obscureText,
            minLines: maxLines,
            maxLines: maxLines,
            onChanged: (value) {
              field.didChange(value);
              if (_connectionFeedback != null) {
                setState(() => _connectionFeedback = null);
              }
            },
          ),
          if (field.hasError) ...[
            const SizedBox(height: SlowlightSpacing.xs),
            Text(
              field.errorText!,
              style: SlowlightTypography.caption(context).copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigForm() {
    return FxCard(
      child: Padding(
        padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('连接配置', style: SlowlightTypography.cardTitle(context)),
              const SizedBox(height: 16),
              _validatedInput(
                controller: _baseUrlController,
                label: '服务器地址',
                placeholder: 'https://vikunja.example.com',
                icon: LucideIcons.link2,
                validate: CalDavFormValidation.serverUrl,
              ),
              const SizedBox(height: 16),
              _validatedInput(
                controller: _usernameController,
                label: '用户名',
                placeholder: '输入 CalDAV 用户名',
                icon: LucideIcons.user,
                validate: CalDavFormValidation.username,
              ),
              const SizedBox(height: 16),
              _validatedInput(
                controller: _passwordController,
                label: '密码 / 访问令牌',
                placeholder: _canReusePassword
                    ? '留空沿用已保存凭据' : '输入密码或访问令牌',
                icon: LucideIcons.lock,
                obscureText: _obscurePassword,
                trailing: FxIconButton(
                  icon: _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                ),
                validate: (value) => value.isNotEmpty || _canReusePassword
                    ? null : CalDavFormValidation.password(value),
              ),
              const SizedBox(height: 16),
              _validatedInput(
                controller: _pathsController,
                label: '项目路径（每行一个）',
                placeholder: '/dav/projects/5\n/dav/projects/8',
                icon: LucideIcons.folder,
                maxLines: 3,
                validate: CalDavFormValidation.paths,
              ),
              const SizedBox(height: 8),
              Text(
                '格式：/dav/projects/{项目ID}，可在 Vikunja 项目设置中查看',
                style: SlowlightTypography.caption(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_canReusePassword) ...[
                const SizedBox(height: SlowlightSpacing.xs),
                Text('服务器地址及用户名不变时，可留空沿用已保存凭据。',
                  style: SlowlightTypography.caption(context)),
              ],
              if (_connectionFeedback != null) ...[
                const SizedBox(height: SlowlightSpacing.xl),
                Text(_connectionFeedback!,
                  key: const ValueKey('caldav.connection-feedback'),
                  style: SlowlightTypography.secondary(context)),
              ],
              const SizedBox(height: SlowlightSpacing.xxxl),
              FxDialogActions(
                actions: [
                  FxButton(
                    label: '测试连接',
                    onPressed: _testing || _saving ? null : _testConnection,
                    variant: FxButtonVariant.outline,
                  ),
                  FxButton(
                    label: '保存配置',
                    onPressed: _testing || _saving ? null : _saveConfig,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final theme = Theme.of(context);
    final states = _status?['states'];
    final projects = states is List ? states.length : null;
    final known = _status != null && _statusError == null;
    return FxCard(
      padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.calendarDays,
              size: SlowlightIconSize.lg,
              color: theme.colorScheme.primary),
            const SizedBox(width: SlowlightSpacing.md),
            Expanded(child: Text('同步概况',
              style: SlowlightTypography.cardTitle(context))),
            Text(known ? '状态已读取' : '状态待核对',
              style: SlowlightTypography.caption(context).copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: SlowlightSpacing.xxxl),
          Row(children: [
            Expanded(child: Column(children: [
              Text(calDavSyncedTaskLabel(_status,
                  loading: _statusLoading, stale: _statusError != null),
                style: SlowlightTypography.sectionTitle(context)),
              Text('已同步任务',
                style: SlowlightTypography.caption(context)),
            ])),
            Expanded(child: Column(children: [
              Text(projects == null ? '—' : '$projects',
                style: SlowlightTypography.sectionTitle(context)),
              Text('项目状态记录',
                style: SlowlightTypography.caption(context)),
            ])),
          ]),
          if (_statusError != null) ...[
            const SizedBox(height: SlowlightSpacing.xl),
            Text('状态读取失败，以上数字仅为上次已载入数据。',
              style: SlowlightTypography.caption(context).copyWith(
                color: theme.colorScheme.error)),
            FxButton(
              label: '重试读取',
              variant: FxButtonVariant.outline,
              size: FxButtonSize.sm,
              onPressed: _statusLoading ? null : _loadStatus),
          ],
          if (states is List && states.isNotEmpty) ...[
            const SizedBox(height: SlowlightSpacing.xl),
            FxExpansionTile(
              title: Text('各项目上次同步时间',
                style: SlowlightTypography.secondary(context)),
              children: states.map<Widget>((state) => Padding(
                padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.xs),
                child: Text(
                  '${state['project_path'] ?? '未知'} · ${state['last_synced_at'] ?? '从未同步'}',
                  style: SlowlightTypography.caption(context)),
              )).toList(),
            ),
          ],
          const SizedBox(height: SlowlightSpacing.xxxl),
          FxButton(
            label: _syncing ? '同步中…' : '立即同步',
            icon: LucideIcons.refreshCw,
            expanded: true,
            onPressed: _syncing || _saving || _testing ? null : _syncNow),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: SlowlightTypography.buttonSize,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: SlowlightTypography.buttonSize, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return FxCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.circleAlert, color: AppTheme.error, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '错误信息',
                  style: TextStyle(
                    fontSize: SlowlightTypography.buttonSize,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _lastError!,
              style: const TextStyle(
                fontSize: SlowlightTypography.buttonSize,
                height: 1.5,
                color: AppTheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
