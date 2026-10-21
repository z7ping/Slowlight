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
import 'about_screen.dart';
import 'diagnostics_screen.dart';
import 'conflict_screen.dart';
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
  bool _savingReminder = false;
  bool _switchingMode = false;
  bool _linkingGitHub = false;
  bool _loadingAccount = true;
  int _accountLoadVersion = 0;
  User? _accountUser;
  bool? _githubLinked;
  late String _open;
  late bool _mobileDetail;
  bool _openedAsDeepLink = false;
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
    _openedAsDeepLink = widget.initialSection != 'appearance';
    _mobileDetail = _openedAsDeepLink;
    _reminder.addListener(_reminderChanged);
    authStateNotifier.addListener(_authenticationChanged);
    DataModeManager().addListener(_authenticationChanged);
    SyncService().addListener(_syncStatusChanged);
    if (_reminderSupported && !_reminder.isLoaded) _reminder.loadAll();
    _load();
    _loadAccount();
  }

  @override
  void dispose() {
    _reminder.removeListener(_reminderChanged);
    authStateNotifier.removeListener(_authenticationChanged);
    DataModeManager().removeListener(_authenticationChanged);
    SyncService().removeListener(_syncStatusChanged);
    super.dispose();
  }

  void _authenticationChanged() {
    if (!mounted) return;
    _loadAccount();
    _loadConflictCount();
    setState(() {});
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
    if (user == null) return '云端账号 · 信息待确认';
    if (_githubLinked == true) {
      return '${user.nickname ?? user.username ?? '云端账号'} · GitHub 已绑定';
    }
    return '${user.nickname ?? user.username ?? '云端账号'} · 云端';
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
          if (defaultTargetPlatform == TargetPlatform.windows) ...[
            Text(
              '浏览器完成 GitHub 授权后，本应用会自动核验。'
              '如果仍显示等待，可以主动检查授权结果。',
              style: style,
            ),
            const SizedBox(height: SlowlightSpacing.md),
            FxButton(
              label: '检查授权结果',
              variant: FxButtonVariant.outline,
              onPressed: () {
                if (!GitHubSignIn.checkAuthorizationNow()) {
                  _message('授权会话正在初始化，请稍后重试');
                }
              },
            ),
            const SizedBox(height: SlowlightSpacing.md),
          ],
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


  String _sectionTitle(String id) => switch (id) {
    'appearance' => '外观',
    'ai' => 'AI 服务',
    'account' => '账号',
    'data' => '数据管理',
    'sync' => '连接与同步',
    'privacy' => '隐私与安全',
    'diagnostics' => '应用诊断',
    'rest' => '休息提醒',
    'about' => '关于',
    _ => '设置',
  };

  String _sectionDescription(String id) => switch (id) {
    'appearance' => '主题、配色、字体与显示',
    'ai' => _aiSummary(),
    'account' => _accountSummary(),
    'data' => DataModeManager().isLocal ? '本地数据模式' : '云端数据模式',
    'sync' => _dataSummary(),
    'privacy' => '数据位置与第三方连接',
    'diagnostics' => '查看与导出本机错误记录',
    'rest' => _restSummary(),
    'about' => '版本与应用信息',
    _ => '',
  };

  void _openSection(String id) {
    if (id == 'diagnostics') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
      return;
    }
    if (id == 'about') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AboutScreen()));
      return;
    }
    setState(() {
      _open = id;
      _mobileDetail = true;
      _openedAsDeepLink = false;
    });
  }

  void _backFromDetail() {
    if (_openedAsDeepLink) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _mobileDetail = false);
    }
  }

  Widget _groupLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 7),
    child: Text(label,
      style: SlowlightTypography.caption(context).copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _category({
    required String id,
    required IconData icon,
    required bool desktop,
  }) {
    final selected = desktop && _open == id;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 单列导航的摘要靠右；空间不足或大字体时保留二行可读性。
        final stackSummary = !desktop &&
            (constraints.maxWidth < 400 ||
                MediaQuery.textScalerOf(context).scale(1) >= 1.6);
        return FxListTile(
          key: ValueKey('settings.category.$id'),
          density: desktop
              ? FxListTileDensity.sidebar
              : stackSummary
                  ? FxListTileDensity.detailed
                  : FxListTileDensity.standard,
          minTileHeight: desktop ? 44.0 : 58.0,
          title: _sectionTitle(id),
          subtitle: stackSummary ? _sectionDescription(id) : null,
          leading: Icon(icon, size: 20),
          trailing: desktop
              ? null
              : stackSummary
                  ? Icon(
                      LucideIcons.chevronRight,
                      key: ValueKey('settings.chevron.$id'),
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _sectionDescription(id),
                              key: ValueKey('settings.summary.$id'),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SlowlightTypography.caption(context)
                                  .copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.chevronRight,
                            key: ValueKey('settings.chevron.$id'),
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
          selected: selected,
          selectedColor: theme.colorScheme.primary,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: .07),
          onTap: () => _openSection(id),
        );
      },
    );
  }

  Widget _navigationList({required bool desktop}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!desktop)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Text(
            DataModeManager().isCloud
                ? '当前使用云端数据 · 本机保留离线缓存'
                : '当前使用本地数据 · 不自动上传',
            style: SlowlightTypography.secondary(context).copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      _groupLabel('个性化'),
      _category(id: 'appearance', icon: LucideIcons.palette, desktop: desktop),
      _category(id: 'ai', icon: LucideIcons.sparkles, desktop: desktop),
      if (_reminderSupported)
        _category(id: 'rest', icon: LucideIcons.bell, desktop: desktop),
      _groupLabel('数据与服务'),
      _category(id: 'account', icon: LucideIcons.userRound, desktop: desktop),
      _category(id: 'data', icon: LucideIcons.database, desktop: desktop),
      _category(id: 'sync', icon: LucideIcons.cloud, desktop: desktop),
      _category(id: 'privacy', icon: LucideIcons.shieldCheck, desktop: desktop),
      _groupLabel('应用维护'),
      _category(id: 'diagnostics', icon: LucideIcons.bug, desktop: desktop),
      _category(id: 'about', icon: LucideIcons.info, desktop: desktop),
    ],
  );

  Widget _sectionContent(String id) => switch (id) {
    'appearance' => _appearancePanel(),
    'ai' => _aiPanel(),
    'account' => _accountPanel(),
    'data' => _dataManagementPanel(),
    'sync' => _syncPanel(),
    'privacy' => _privacyPanel(),
    'rest' => _reminderSupported
        ? _restPanel()
        : Text('休息提醒仅在桌面端配置',
            style: SlowlightTypography.secondary(context)),
    _ => const SizedBox.shrink(),
  };

  Widget _detailContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_sectionTitle(_open),
        style: SlowlightTypography.componentPageTitle(context)),
      const SizedBox(height: 6),
      Text(
        _sectionDescription(_open),
        style: SlowlightTypography.caption(context).copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      FxSeparator.horizontal(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      const SizedBox(height: 20),
      _sectionContent(_open),
    ],
  );

  String _dataSummary() {
    if (DataModeManager().isLocal) return '仅本地使用';
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final android = !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android;
        final twoPane = !android && viewport.maxWidth >= 760 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.8;
        final detail = !twoPane && _mobileDetail;
        return PopScope(
          canPop: !detail || _openedAsDeepLink,
          onPopInvoked: (didPop) {
            if (!didPop && detail && !_openedAsDeepLink && mounted) {
              setState(() => _mobileDetail = false);
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  FxPageHeader(
                    title: detail ? _sectionTitle(_open) : '设置',
                    onBack: detail ? _backFromDetail : null,
                  ),
                  Expanded(
                    child: ListView(
                      key: PageStorageKey(
                        detail ? 'settings.detail.$_open' : 'settings.overview',
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1050),
                            child: twoPane
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 226,
                                        child: _navigationList(desktop: true),
                                      ),
                                      const SizedBox(width: 28),
                                      Expanded(child: _detailContent()),
                                    ],
                                  )
                                : detail
                                    ? _sectionContent(_open)
                                    : _navigationList(desktop: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    final minScale = ThemeSettings.fontScaleOptions.keys.first;
    final maxScale = ThemeSettings.fontScaleOptions.keys.last;
    final visibleScale = settings.fontScale.clamp(minScale, maxScale).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('主题模式'),
        _segmented(const ['跟随系统', '浅色', '深色'], modeIndex, (index) async {
          await _saveAppearance(() => settings.setThemeMode(
            [ThemeMode.system, ThemeMode.light, ThemeMode.dark][index],
          ));
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
                    await _saveAppearance(() => settings.setPalette(palette.name));
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
          min: minScale,
          max: maxScale,
          divisions: ((maxScale - minScale) / .05).round(),
          label: '${(visibleScale * 100).round()}%',
          onChanged: (value) {
            _saveAppearance(() => settings.setFontScale(value));
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
            // 根级 MediaQuery 已应用字号倍率，预览不再重复放大。
            style: SlowlightTypography.secondary(context),
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
            await _saveAppearance(() => settings.setFontFamily(value));
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
              await _saveAppearance(settings.resetToDefaults);
            },
          ),
        ),
      ],
    );
  }


  Widget _dataManagementPanel() {
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
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('正在切换数据模式…',
              style: SlowlightTypography.caption(context)),
          ),
        const SizedBox(height: 12),
        Text(
          local
              ? '当前记录从本机数据库读写。切换不会自动上传或合并本地记录。'
              : '当前记录以云端数据为准，本机保留离线缓存。切换不会自动导入本地记录。',
          style: SlowlightTypography.secondary(context).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _settingLine(
          '数据迁移',
          '先预览本机记录及冲突，再确认迁移',
          trailing: FxButton(
            label: '预览迁移',
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: () => MigrationPreviewDialog.show(context),
          ),
        ),
        _settingLine(
          '迁移历史',
          '查看历史迁移时间、策略和结果',
          trailing: FxButton(
            label: '查看历史',
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: () => MigrationHistoryDialog.show(context),
          ),
        ),
      ],
    );
  }

  Widget _syncPanel() => ListenableBuilder(
    listenable: SyncService(),
    builder: (context, _) => ValueListenableBuilder<int>(
      valueListenable: CloudSyncCoordinator().standalonePendingCount,
      builder: (context, _, __) {
        final local = DataModeManager().isLocal;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (local)
              Text(
                '目前为本地数据模式。云端同步不会运行，登录后可选择使用云端数据。',
                style: SlowlightTypography.secondary(context),
              )
            else ...[
              _settingLine(
                '同步状态',
                _dataSummary(),
                trailing: FxButton(
                  label: _syncing ? '同步中…' : '立即同步',
                  size: FxButtonSize.sm,
                  variant: FxButtonVariant.outline,
                  onPressed: _syncing ? null : _syncNow,
                ),
              ),
              _settingLine(
                '同步冲突',
                _conflictCheckFailed
                    ? '暂时无法读取冲突，请检查云端连接'
                    : _conflictCount == 0
                        ? '无待处理冲突'
                        : '$_conflictCount 条记录需要选择保留版本',
                trailing: FxButton(
                  label: '查看冲突',
                  size: FxButtonSize.sm,
                  variant: FxButtonVariant.outline,
                  onPressed: _conflictCount == 0 && !_conflictCheckFailed
                      ? null
                      : _openConflicts,
                ),
              ),
            ],
            _settingLine(
              '平台集成',
              '连接飞书多维表格，管理已支持的同步范围',
              trailing: FxButton(
                label: '打开集成',
                size: FxButtonSize.sm,
                variant: FxButtonVariant.outline,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const IntegrationScreen(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _privacyPanel() {
    final local = DataModeManager().isLocal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingLine(
          '当前记录来源',
          local
              ? '本地数据模式：读写本设备数据库，不自动上传记录。'
              : '云端数据模式：数据以服务端为准，本机保留离线缓存。',
        ),
        _settingLine(
          'AI 请求',
          '请求发往已配置的模型接口。是否离开本设备取决于实际接口地址。',
          trailing: FxButton(
            label: '查看配置',
            size: FxButtonSize.sm,
            variant: FxButtonVariant.outline,
            onPressed: _openAiSettings,
          ),
        ),
        _settingLine(
          '第三方授权',
          'GitHub 绑定信息以云端返回为准；飞书连接由集成页面管理。',
        ),
        _settingLine(
          '错误日志',
          '仅保存在本机，用户主动导出前应检查个人信息。',
          trailing: FxButton(
            label: '应用诊断',
            size: FxButtonSize.sm,
            variant: FxButtonVariant.outline,
            onPressed: () => _openSection('diagnostics'),
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
              : _reminder.loadFailed ? '读取提醒配置失败，可重试' : '读取提醒配置中…',
          trailing: _statusChip(_reminder.loadFailed ? '读取失败' : _reminder.isLoaded ? '已配置' : '读取中…', accent: _reminder.isLoaded),
        ),
        _settingLine(
          '长休息提醒',
          _reminder.isLoaded
              ? '小憩满 ${_reminder.microRestsBeforeLong} 次后进入 ${_reminder.longRestMinutes} 分钟长休息'
              : _reminder.loadFailed ? '读取提醒配置失败，可重试' : '读取提醒配置中…',
          trailing: _statusChip(_reminder.loadFailed ? '读取失败' : _reminder.isLoaded ? '已配置' : '读取中…', accent: _reminder.isLoaded),
        ),
        if (isWindows) _settingLine(
          '霸屏休息',
          '休息触发时全屏接管桌面',
          trailing: FxSwitch(
            value: fullscreen,
            onChanged: isWindows && _reminder.isLoaded && !_savingReminder ? _setReminderFullscreen : null,
          ),
        ),
        _settingLine(
          '小憩严格模式',
          '小憩开始后不可跳过本轮',
          trailing: FxSwitch(
            value: _reminder.microRestStrict,
            onChanged: _reminder.isLoaded && !_savingReminder ? (value) => _setReminderStrict(micro: true, value: value) : null,
          ),
        ),
        _settingLine(
          '长休息严格模式',
          '长休息开始后不可跳过本轮',
          trailing: FxSwitch(
            value: _reminder.longRestStrict,
            onChanged: _reminder.isLoaded && !_savingReminder ? (value) => _setReminderStrict(micro: false, value: value) : null,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_reminder.loadFailed)
              FxButton(
                label: '重试读取提醒配置',
                variant: FxButtonVariant.outline,
                size: FxButtonSize.sm,
                onPressed: _savingReminder ? null : _reminder.loadAll,
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
    final scale = settings.fontScale;
    return '${ThemeSettings.themeModeOptions[settings.themeMode]} · ${getPalette(settings.palette).label} · ${(scale * 100).round()}%';
  }

  String _restSummary() {
    if (!_reminderSupported) return '仅桌面端';
    if (!_reminder.isLoaded) return _reminder.loadFailed ? '读取失败' : '读取中…';
    final fullscreen =
        defaultTargetPlatform == TargetPlatform.windows &&
        _reminder.lockScreenMode == 'fullscreen';
    return '${_reminder.workMinutes} 分钟 · ${fullscreen ? '霸屏' : '窗口'}';
  }

  Future<void> _saveAppearance(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) FxNotice.errorWithDetails(context, '外观设置保存失败，已恢复原设置', e.toString());
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveReminderChange({
    required String successMessage,
    required void Function() apply,
    required void Function() rollback,
  }) async {
    if (!_reminderSupported || !_reminder.isLoaded || _savingReminder) return;
    setState(() => _savingReminder = true);
    apply();
    try {
      await _reminder.saveConfig();
      if (mounted) _message(successMessage);
    } catch (e) {
      rollback();
      if (mounted) {
        FxNotice.errorWithDetails(context, '休息提醒设置保存失败，已恢复原设置', e.toString());
      }
    } finally {
      if (mounted) setState(() => _savingReminder = false);
    }
  }

  Future<void> _setReminderFullscreen(bool enabled) async {
    final before = _reminder.lockScreenMode;
    await _saveReminderChange(
      successMessage: enabled ? '已启用霸屏休息' : '已改为窗口休息',
      apply: () => _reminder.updateConfig(lockScreenMode: enabled ? 'fullscreen' : 'window'),
      rollback: () => _reminder.updateConfig(lockScreenMode: before),
    );
  }

  Future<void> _setReminderStrict({
    required bool micro,
    required bool value,
  }) async {
    final before = micro ? _reminder.microRestStrict : _reminder.longRestStrict;
    final label = micro ? '小憩严格模式' : '长休息严格模式';
    await _saveReminderChange(
      successMessage: value ? '已启用$label' : '已关闭$label',
      apply: () => _reminder.updateConfig(
        microRestStrict: micro ? value : null,
        longRestStrict: micro ? null : value,
      ),
      rollback: () => _reminder.updateConfig(
        microRestStrict: micro ? before : null,
        longRestStrict: micro ? null : before,
      ),
    );
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
        // OAuth 回调已完成后仍需刷新本机身份和真实绑定状态。
        // 侧栏可能已经存在，显式广播避免停留在旧的账户摘要。
        authStateNotifier.value = !authStateNotifier.value;
        await _loadAccount();
        if (!mounted) return;
        if (_githubLinked == true) {
          _message('GitHub 已绑定到当前云端账号');
        } else {
          _message('GitHub 授权已完成，请重新检查账号绑定状态');
        }
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
