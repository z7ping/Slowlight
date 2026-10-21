import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ai/ai_config_store.dart';
import '../ai/ai_models.dart';
import '../models/user.dart';
import '../main.dart' show authStateNotifier;
import '../services/auth_service.dart';
import '../services/cloud_sync_coordinator.dart';
import '../services/data_mode_manager.dart';
import '../services/github_sign_in.dart';
import '../services/reminder_service.dart';
import '../services/sync_service.dart';
import '../services/theme_settings.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../ui/sync_status_text.dart';
import 'ai_settings_screen.dart';
import 'diagnostics_screen.dart';import 'conflict_screen.dart';
import 'integration_screen.dart';
import 'login_screen.dart';
import 'migration_history_dialog.dart';
import 'migration_preview_dialog.dart';
import 'reminder_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String initialSection;

  const SettingsScreen({super.key, this.initialSection = 'appearance'});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _aiStore = AiConfigStore();
  final _reminder = ReminderService();

  bool _loadingAi = true;
  String? _aiLoadError;
  bool _syncing = false;
  bool _switchingMode = false;
  bool _linkingGitHub = false;
  bool _loadingAccount = true;
  int _accountLoadVersion = 0;
  User? _accountUser;
  bool? _githubLinked;
  late String _open;
  AiConfig _ai = const AiConfig();
  bool _hasKey = false;
  int _conflictCount = 0;
  // 首次查询完成前不能把未知冲突状态宣称为正常。
  bool _conflictCheckFailed = true;
  SyncStatusEnum? _observedSyncStatus;

  bool get _reminderSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _open = widget.initialSection;
    _reminder.addListener(_reminderChanged);
    SyncService().addListener(_syncStatusChanged);
    if (_reminderSupported && !_reminder.isLoaded) _reminder.loadAll();
    _load();
    _loadAccount();
  }

  @override
  void dispose() {
    _reminder.removeListener(_reminderChanged);
    SyncService().removeListener(_syncStatusChanged);
    super.dispose();
  }

  void _reminderChanged() {
    if (mounted) setState(() {});
  }

  void _syncStatusChanged() {
    final status = SyncService().status;
    if (status == _observedSyncStatus) return;
    _observedSyncStatus = status;
    if (status != SyncStatusEnum.syncing) _loadConflictCount();
  }

  Future<void> _load() async {
    setState(() {
      _loadingAi = true;
      _aiLoadError = null;
    });
    try {
      final ai = await _aiStore.load();
      final key = await _aiStore.loadApiKey(ai.provider);
      if (!mounted) return;
      setState(() {
        _ai = ai;
        _hasKey = key?.isNotEmpty == true;
        _loadingAi = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAi = false;
        _aiLoadError = '读取 AI 配置失败';
      });
    }
  }

  Future<void> _openAiSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _loadAccount() async {
    final version = ++_accountLoadVersion;
    if (mounted) {
      setState(() {
        _loadingAccount = true;
        _accountUser = null;
        _githubLinked = null;
      });
    }
    if (DataModeManager().isLocal) {
      if (mounted && version == _accountLoadVersion) {
        setState(() => _loadingAccount = false);
      }
      return;
    }
    try {
      final user = await AuthService.getUser();
      if (!mounted || version != _accountLoadVersion || DataModeManager().isLocal) return;
      setState(() {
        _accountUser = user;
        _loadingAccount = false;
      });
      // 无法确认绑定状态时保持「未知」，不能伪装成「未绑定」。
      final linked = await AuthService.isGitHubLinked();
      if (mounted && version == _accountLoadVersion && DataModeManager().isCloud) {
        setState(() => _githubLinked = linked);
      }
    } catch (_) {
      if (mounted && version == _accountLoadVersion && DataModeManager().isCloud) {
        setState(() => _loadingAccount = false);
      }
    }
  }

  String _accountSummary() {
    if (DataModeManager().isLocal) return '本地使用';
    if (_loadingAccount) return '正在读取账号…';
    final user = _accountUser;
    return user == null
        ? '云端账号 · 信息待确认'
        : '${user.nickname ?? user.username ?? '云端账号'} · 云端';
  }

  Widget _accountPanel() {
    final style = SlowlightTypography.secondary(context);
    if (DataModeManager().isLocal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前以本地模式使用，不需要云端账号。', style: style),
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            label: '前往云端登录',
            variant: FxButtonVariant.outline,
            onPressed: () => _setDataMode(1),
          ),
        ],
      );
    }
    final user = _accountUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(user?.nickname ?? user?.username ?? '账号信息待确认',
            style: SlowlightTypography.cardTitle(context)),
        const SizedBox(height: SlowlightSpacing.xs),
        Text(user?.email.isNotEmpty == true ? user!.email : '请检查账号状态',
            style: style),
        if (user == null) ...[
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            label: '重新读取账号信息',
            variant: FxButtonVariant.outline,
            onPressed: _loadAccount,
          ),
        ],
        const SizedBox(height: SlowlightSpacing.md),
        Text(_githubLinked == true
            ? 'GitHub：已绑定'
            : _githubLinked == false
                ? 'GitHub：未绑定'
                : 'GitHub：绑定状态暂不可用',
            style: style),
        const SizedBox(height: SlowlightSpacing.md),
        if (_githubLinked == false || _linkingGitHub)
          FxButton(
            key: const ValueKey('settings.github_link'),
            label: _linkingGitHub ? '等待 GitHub 授权…' : '绑定 GitHub',
            icon: LucideIcons.gitFork,
            variant: FxButtonVariant.outline,
            onPressed: _linkingGitHub ? null : _bindGitHub,
          ),
        if (_githubLinked == null)
          FxButton(
            label: '重新检查绑定状态',
            variant: FxButtonVariant.outline,
            onPressed: _loadAccount,
          ),
        if (_linkingGitHub) ...[
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            label: '取消授权等待',
            variant: FxButtonVariant.link,
            onPressed: () => setState(() => _linkingGitHub = false),
          ),
        ],
        const SizedBox(height: SlowlightSpacing.md),
        FxButton(
          label: '退出登录',
          icon: LucideIcons.logOut,
          variant: FxButtonVariant.ghost,
          onPressed: _logoutAccount,
        ),
      ],
    );
  }

  Future<void> _logoutAccount() async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '退出登录',
      content: '确认退出当前云端账号？本机未同步的记录请先检查同步状态。',
    );
    if (confirmed != true) return;
    await AuthService.logout();
    CloudSyncCoordinator().stop();
    authStateNotifier.value = !authStateNotifier.value;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _loadConflictCount() async {
    if (DataModeManager().isLocal) {
      if (mounted && (_conflictCount != 0 || _conflictCheckFailed)) {
        setState(() {
          _conflictCount = 0;
          _conflictCheckFailed = false;
        });
      }
      return;
    }
    try {
      final conflicts = await SyncService().getAllConflicts();
      if (mounted && DataModeManager().isCloud) {
        setState(() {
          _conflictCount = conflicts.length;
          _conflictCheckFailed = false;
        });
      }
    } catch (_) {
      if (mounted && DataModeManager().isCloud) {
        setState(() => _conflictCheckFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const FxPageHeader(title: '设置'),
            Expanded(
              child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _settingsIntro(),
                                  _groupLabel('个性化'),
                                  _accordion(
                                    id: 'appearance',
                                    icon: LucideIcons.palette,
                                    title: '外观',
                                    summary: _appearanceSummary(),
                                    child: _appearancePanel(),
                                  ),
                                  const SizedBox(height: 10),
                                  _groupLabel('数据与服务'),
                                  _accordion(
                                    id: 'account',
                                    icon: LucideIcons.userRound,
                                    title: '账号',
                                    summary: _accountSummary(),
                                    child: _accountPanel(),
                                  ),
                                  const SizedBox(height: 10),
                                  ListenableBuilder(
                                    listenable: SyncService(),
                                    builder: (context, _) =>
                                        ValueListenableBuilder<int>(
                                      valueListenable: CloudSyncCoordinator()
                                          .standalonePendingCount,
                                      builder: (context, _, __) => _accordion(
                                        id: 'data',
                                        icon: LucideIcons.cloud,
                                        title: '数据同步',
                                        summary: _dataSummary(),
                                        child: _dataPanel(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _accordion(
                                    id: 'ai',
                                    icon: LucideIcons.sparkles,
                                    title: 'AI 服务',
                                    summary: _aiSummary(),
                                    child: _aiPanel(),
                                  ),
                                  const SizedBox(height: 10),
                                  _groupLabel('应用维护'),
                                  _accordion(
                                    id: 'diagnostics',
                                    icon: LucideIcons.bug,
                                    title: '应用诊断',
                                    summary: '查看、导出或清理本机错误日志',
                                    child: FxButton(
                                      label: '查看错误日志',
                                      icon: LucideIcons.fileText,
                                      variant: FxButtonVariant.outline,
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const DiagnosticsScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _groupLabel('桌面效率'),
                                  _accordion(
                                    id: 'rest',
                                    icon: LucideIcons.bell,
                                    title: '休息提醒',
                                    summary: _restSummary(),
                                    child: _restPanel(),
                                  ),
                                  const SizedBox(height: 24),
                                  Center(
                                    child: Text(
                                      DataModeManager().isCloud
                                          ? '云端模式 · 本机保留离线缓存'
                                          : '本地模式 · 数据由本设备管理',
                                      style: SlowlightTypography.caption(
                                        context,
                                      ).copyWith(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsIntro() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      '调整所行映我的工作方式与数据边界',
      style: SlowlightTypography.secondary(
        context,
      ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  Widget _groupLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 7),
    child: Text(
      label,
      style: SlowlightTypography.caption(context).copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  String _dataSummary() {
    if (DataModeManager().isLocal) return '本地独立使用 · 无需云端';
    final sync = SyncService();
    return cloudSyncSummary(
      status: sync.status,
      isSyncing: _syncing,
      conflictCheckFailed: _conflictCheckFailed,
      conflictCount: _conflictCount,
      pendingCount: sync.pendingCount +
          CloudSyncCoordinator().standalonePendingCount.value,
    );
  }

  String _aiSummary() {
    if (_loadingAi) return '正在读取…';
    if (_aiLoadError != null) return '配置读取失败';
    if (!_ai.enabled) return '${_ai.provider.label} · 未启用';
    return '${_ai.provider.label} · ${_hasKey || !_ai.provider.apiKeyRequired ? '已配置' : '缺少密钥'}';
  }

  Widget _accordion({
    required String id,
    required IconData icon,
    required String title,
    required String summary,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final open = _open == id;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final stackHeader = scale >= 1.6 && MediaQuery.sizeOf(context).width < 520;
    return FxCard(
      padding: EdgeInsets.zero,
      color: fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(color: fxBorder(context)),
      expanded: true,
      child: Column(
        children: [
          FxInkWell(
            onTap: () => setState(() => _open = open ? '' : id),
            borderRadius: BorderRadius.circular(SlowlightRadius.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child:
                    stackHeader
                        ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(icon, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: SlowlightTypography.secondary(
                                      context,
                                    ).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Icon(
                                  open
                                      ? LucideIcons.chevronDown
                                      : LucideIcons.chevronRight,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 28),
                              child: Text(
                                summary,
                                style: SlowlightTypography.caption(
                                  context,
                                ).copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        )
                        : Row(
                          children: [
                            Icon(icon, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: SlowlightTypography.secondary(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                summary,
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                style: SlowlightTypography.caption(
                                  context,
                                ).copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              open
                                  ? LucideIcons.chevronDown
                                  : LucideIcons.chevronRight,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: fxDivider(context))),
              ),
              child: child,
            ),
            crossFadeState:
                open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
          ),
        ],
      ),
    );
  }

  Widget _segmented(
    List<String> labels,
    int selected,
    ValueChanged<int> change,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final expanded = constraints.maxWidth >= 320 && scale < 1.6;
        final segmented = FxSegmented(
          labels: labels,
          selectedIndex: selected,
          onChanged: change,
          backgroundColor: fxSubtleSurface(context),
          selectedColor: fxSurface(context),
          borderRadius: SlowlightRadius.md,
          expanded: expanded,
        );
        if (expanded) {
          return SizedBox(width: double.infinity, child: segmented);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: segmented,
        );
      },
    );
  }

  Widget _appearancePanel() {
    final theme = Theme.of(context);
    final settings = ThemeSettings();
    final modeIndex = switch (settings.themeMode) {
      ThemeMode.light => 1,
      ThemeMode.dark => 2,
      _ => 0,
    };
    final visibleScale = settings.fontScale.clamp(1.0, 1.25).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('主题模式'),
        _segmented(const ['跟随系统', '浅色', '深色'], modeIndex, (index) async {
          await settings.setThemeMode(
            [ThemeMode.system, ThemeMode.light, ThemeMode.dark][index],
          );
          if (mounted) setState(() {});
        }),
        const SizedBox(height: 14),
        _label('配色'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allPalettes
              .map((palette) {
                final selected = settings.palette == palette.name;
                return FxInkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    await settings.setPalette(palette.name);
                    if (mounted) setState(() {});
                  },
                  child: SizedBox(
                    width: 116,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              selected
                                  ? palette.accent
                                  : theme.colorScheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                        color: theme.colorScheme.surface,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette.accent,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              palette.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SlowlightTypography.caption(
                                context,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Opacity(
                            opacity: selected ? 1 : 0,
                            child: Icon(
                              LucideIcons.check,
                              size: 14,
                              color: palette.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _label('应用内字号'),
            const Spacer(),
            Text(
              '${(visibleScale * 100).round()}%',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        FxSlider(
          value: visibleScale,
          min: 1.0,
          max: 1.25,
          divisions: 5,
          label: '${(visibleScale * 100).round()}%',
          onChanged: (value) {
            settings.setFontScale(value);
            setState(() {});
          },
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            '预览：所行映我帮你了解自己',
            style: TextStyle(fontSize: SlowlightTypography.secondarySize * visibleScale),
          ),
        ),
        const SizedBox(height: 12),
        _label('字体'),
        FxSelect<String>(
          value: settings.fontFamily,
          options: ThemeSettings.fontFamilyOptions.entries
              .map(
                (entry) => FxSelectOption<String>(
                  value: entry.key,
                  label: entry.value,
                ),
              )
              .toList(growable: false),
          onChanged: (value) async {
            if (value == null) return;
            await settings.setFontFamily(value);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FxButton(
            label: '恢复默认',
            variant: FxButtonVariant.ghost,
            size: FxButtonSize.sm,
            onPressed: () async {
              await settings.resetToDefaults();
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _dataPanel() {
    final local = DataModeManager().isLocal;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('数据模式'),
        IgnorePointer(
          ignoring: _switchingMode,
          child: _segmented(
            const ['本地数据', '云端数据'],
            local ? 0 : 1,
            _setDataMode,
          ),
        ),
        if (_switchingMode)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('正在切换数据模式…'),
          ),
        const SizedBox(height: 6),
        Text(
          local
              ? '数据仅从本机数据库读写。切换模式不会自动把现有本地数据上传到云端。'
              : '数据以所行映我服务端为准，并在本机保留同步缓存；不会自动导入本地模式中的记录。',
          style: SlowlightTypography.caption(
            context,
          ).copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (!local) ...[
          const SizedBox(height: 10),
          _settingLine(
            '同步状态',
            _dataSummary(),
            trailing: FxButton(
              label: _syncing ? '同步中…' : '立即同步',
              variant: FxButtonVariant.outline,
              size: FxButtonSize.sm,
              onPressed: _syncing ? null : _syncNow,
            ),
          ),
          _settingLine(
            '同步冲突',
            _conflictCheckFailed
                ? '暂时无法读取冲突，请检查同步状态'
                : _conflictCount == 0
                    ? '无待处理冲突'
                    : '$_conflictCount 条记录需要选择保留版本',
            trailing: FxButton(
              label: '查看冲突 ($_conflictCount)',
              variant: FxButtonVariant.ghost,
              size: FxButtonSize.sm,
              onPressed: _conflictCount == 0 && !_conflictCheckFailed
                  ? null
                  : _openConflicts,
            ),
          ),
        ],
        _settingLine(
          '数据迁移',
          '先预览本机记录与潜在冲突，再确认迁移到云端',
          trailing: FxButton(
            label: '预览迁移',
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: () => MigrationPreviewDialog.show(context),
          ),
        ),
        _settingLine(
          '迁移历史',
          '查看最近 20 次迁移的时间、策略与结果摘要',
          trailing: FxButton(
            label: '查看历史',
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: () => MigrationHistoryDialog.show(context),
          ),
        ),
        _settingLine(
          '平台集成',
          '连接飞书多维表格，同步任务、习惯与行为记录',
          trailing: FxButton(
            label: '打开飞书表格',
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const IntegrationScreen()),
                ),
          ),
        ),
      ],
    );
  }

  Widget _aiPanel() {
    if (_aiLoadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_aiLoadError!, style: SlowlightTypography.secondary(context)),
          const SizedBox(height: 8),
          FxButton(
            label: '重试读取',
            variant: FxButtonVariant.outline,
            onPressed: _load,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _loadingAi
              ? '正在读取 AI 服务配置…'
              : '当前服务商：${_ai.provider.label}。模型、密钥、连接测试和保存统一在配置页管理。',
          style: SlowlightTypography.secondary(context),
        ),
        const SizedBox(height: 10),
        FxButton(
          label: '配置 AI 服务',
          variant: FxButtonVariant.outline,
          onPressed: _loadingAi ? null : _openAiSettings,
        ),
      ],
    );
  }

  Widget _statusChip(String label, {bool accent = false}) {
    final theme = Theme.of(context);
    return FxChip(
      label: label,
      backgroundColor:
          accent
              ? activePalette.accent.withValues(alpha: .12)
              : fxSubtleSurface(context),
      foregroundColor:
          accent ? activePalette.accent : theme.colorScheme.onSurfaceVariant,
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    );
  }

  Widget _restPanel() {
    final theme = Theme.of(context);
    if (!_reminderSupported) {
      return Column(
        children: [
          _settingLine(
            '桌面专属',
            '休息提醒只在桌面端采集；移动端仅在回顾中查看同步来的工作/休息事实',
            trailing: _statusChip('只读回顾'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '查看随处，采集归位。',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final fullscreen = isWindows && _reminder.lockScreenMode == 'fullscreen';
    return Column(
      children: [
        _settingLine(
          '微休息提醒',
          _reminder.isLoaded
              ? '每 ${_reminder.workMinutes} 分钟小憩 ${_reminder.microRestSeconds} 秒'
              : '读取提醒配置中…',
          trailing: _statusChip('已启用', accent: true),
        ),
        _settingLine(
          '长休息提醒',
          _reminder.isLoaded
              ? '小憩满 ${_reminder.microRestsBeforeLong} 次后进入 ${_reminder.longRestMinutes} 分钟长休息'
              : '读取提醒配置中…',
          trailing: _statusChip('已启用', accent: true),
        ),
        _settingLine(
          '霸屏休息',
          isWindows ? '休息触发时全屏接管桌面' : '仅 Windows 桌面端生效',
          trailing: FxSwitch(
            value: fullscreen,
            onChanged: isWindows ? _setReminderFullscreen : null,
          ),
        ),
        _settingLine(
          '小憩严格模式',
          '小憩开始后不可跳过本轮',
          trailing: FxSwitch(
            value: _reminder.microRestStrict,
            onChanged: (value) => _setReminderStrict(micro: true, value: value),
          ),
        ),
        _settingLine(
          '长休息严格模式',
          '长休息开始后不可跳过本轮',
          trailing: FxSwitch(
            value: _reminder.longRestStrict,
            onChanged:
                (value) => _setReminderStrict(micro: false, value: value),
          ),
        ),
        _settingLine('睡眠暂停计时', '系统睡眠/休眠期间不累计工作时长', trailing: _statusChip('提案')),
        _settingLine('锁屏重置本轮', '解锁后本轮从零开始', trailing: _statusChip('提案')),
        _settingLine(
          '免打扰时段',
          '建议 22:00 – 08:00 不提醒',
          trailing: _statusChip('提案'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '未落地项继续明确标记为提案，不伪装成可用开关。',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            FxButton(
              label: '打开休息提醒',
              variant: FxButtonVariant.outline,
              size: FxButtonSize.sm,
              onPressed:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReminderScreen()),
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _settingLine(String title, String subtitle, {Widget? trailing}) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        // 根据该设置行的真实内容宽度折行，不读取整机屏幕宽度。
        final stackTrailing =
            trailing != null &&
            (constraints.maxWidth < 360 ||
                (scale >= 1.6 && constraints.maxWidth < 520));
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );
        return Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: fxDivider(context))),
          ),
          child: trailing == null
              ? copy
              : stackTrailing
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    copy,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: trailing),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 10),
                    trailing,
                  ],
                ),
        );
      },
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: SlowlightTypography.caption(context).copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  String _appearanceSummary() {
    final settings = ThemeSettings();
    final scale = settings.fontScale.clamp(1.0, 1.25);
    return '${ThemeSettings.themeModeOptions[settings.themeMode]} · ${getPalette(settings.palette).label} · ${(scale * 100).round()}%';
  }

  String _restSummary() {
    if (!_reminderSupported) return '仅桌面端';
    if (!_reminder.isLoaded) return '读取中…';
    final fullscreen =
        defaultTargetPlatform == TargetPlatform.windows &&
        _reminder.lockScreenMode == 'fullscreen';
    return '${_reminder.workMinutes} 分钟 · ${fullscreen ? '霸屏' : '窗口'}';
  }

  Future<void> _setReminderFullscreen(bool enabled) async {
    if (!_reminderSupported) return;
    _reminder.updateConfig(lockScreenMode: enabled ? 'fullscreen' : 'window');
    try {
      await _reminder.saveConfig();
      _message(enabled ? '已启用霸屏休息' : '已改为窗口休息');
    } catch (e) {
      _message('保存休息提醒设置失败：$e');
    }
  }

  Future<void> _setReminderStrict({
    required bool micro,
    required bool value,
  }) async {
    if (!_reminderSupported) return;
    _reminder.updateConfig(
      microRestStrict: micro ? value : null,
      longRestStrict: micro ? null : value,
    );
    try {
      await _reminder.saveConfig();
      final label = micro ? '小憩严格模式' : '长休息严格模式';
      _message(value ? '已启用$label' : '已关闭$label');
    } catch (e) {
      _message('保存休息提醒设置失败：$e');
    }
  }

  Future<void> _bindGitHub() async {
    if (DataModeManager().isLocal) return;
    setState(() => _linkingGitHub = true);
    try {
      final completed = await GitHubSignIn.signIn(
        linkExisting: true,
        shouldContinue: () => mounted && _linkingGitHub,
      );
      if (mounted && completed) {
        _message('GitHub 已绑定到当前云端账号');
        await _loadAccount();
      }
    } catch (e) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '绑定 GitHub 失败', e.toString());
      }
    } finally {
      if (mounted) setState(() => _linkingGitHub = false);
    }
  }

  Future<void> _setDataMode(int index) async {
    final manager = DataModeManager();
    final toLocal = index == 0;
    if (_switchingMode || manager.isLocal == toLocal) return;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: toLocal ? '切换为本地数据？' : '切换为云端数据？',
      confirmText: '确认切换',
      content: toLocal
          ? '切换后将读取本设备的本地数据库，不再显示云端记录。'
              '这不会把云端记录下载或合并到本地，也不会删除任何现有数据。'
          : '切换后将读取云端账号中的数据，本地记录不会自动上传或合并。'
              '如需导入已有本地记录，请使用「数据迁移」先预览和处理冲突。'
              '原本的本地数据不会删除。',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _switchingMode = true);
    try {
      if (toLocal) {
        await manager.setLocal();
      } else {
        final token = await AuthService.getToken();
        if (!mounted) return;
        if (token == null || token.startsWith('local:')) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
          // 登录页负责认证成功后切换模式；取消登录时保留原模式。
          if (!mounted || manager.isLocal) return;
        } else {
          await manager.setCloud();
        }
      }
      if (!mounted) return;
      setState(() {});
      await _loadConflictCount();
      await _loadAccount();
      if (mounted) {
        _message(toLocal ? '已切换为本地数据' : '已切换为云端数据');
      }
    } catch (e) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '切换数据模式失败', e.toString());
      }
    } finally {
      if (mounted) setState(() => _switchingMode = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncing || DataModeManager().isLocal) return;
    setState(() => _syncing = true);
    try {
      final ok = await CloudSyncCoordinator().syncNow();
      if (!mounted) return;
      await _loadConflictCount();
      if (mounted) {
        _message(ok ? '同步完成' : '同步未完成，请检查待同步记录和冲突');
      }
    } catch (e) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '同步失败', e.toString());
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openConflicts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConflictScreen()),
    );
    if (mounted) await _loadConflictCount();
  }

  void _message(String text) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(text));
  }
}
