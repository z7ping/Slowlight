import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_config_store.dart';
import '../ai/ai_models.dart';
import '../ai/ai_service.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_coordinator.dart';
import '../services/data_mode_manager.dart';
import '../services/reminder_service.dart';
import '../services/sync_service.dart';
import '../services/theme_settings.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
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
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();

  bool _loading = true;
  bool _syncing = false;
  bool _savingAi = false;
  late String _open;
  AiConfig _ai = const AiConfig();
  bool _hasKey = false;
  int _conflictCount = 0;

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
    if (_reminderSupported && !_reminder.isLoaded) _reminder.loadAll();
    _load();
  }

  @override
  void dispose() {
    _reminder.removeListener(_reminderChanged);
    _endpoint.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _reminderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final ai = await _aiStore.load();
      final key = await _aiStore.loadApiKey(ai.provider);
      if (!mounted) return;
      setState(() {
        _ai = ai;
        _endpoint.text = ai.effectiveEndpoint;
        _model.text = ai.effectiveModel;
        _hasKey = key?.isNotEmpty == true;
        _loading = false;
      });
      await _loadConflictCount();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadConflictCount() async {
    if (DataModeManager().isLocal) {
      if (mounted && _conflictCount != 0) setState(() => _conflictCount = 0);
      return;
    }
    try {
      final conflicts = await SyncService().getConflicts('tasks');
      if (mounted) setState(() => _conflictCount = conflicts.length);
    } catch (_) {
      if (mounted) setState(() => _conflictCount = 0);
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
              child:
                  _loading
                      ? const Center(child: FxCircularProgress())
                      : ListView(
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
                                    icon: Icons.palette_outlined,
                                    title: '外观',
                                    summary: _appearanceSummary(),
                                    child: _appearancePanel(),
                                  ),
                                  const SizedBox(height: 10),
                                  _groupLabel('数据与服务'),
                                  _accordion(
                                    id: 'data',
                                    icon: Icons.cloud_outlined,
                                    title: '数据同步',
                                    summary: _dataSummary(),
                                    child: _dataPanel(),
                                  ),
                                  const SizedBox(height: 10),
                                  _accordion(
                                    id: 'ai',
                                    icon: Icons.auto_awesome_outlined,
                                    title: 'AI 服务',
                                    summary: _aiSummary(),
                                    child: _aiPanel(),
                                  ),
                                  const SizedBox(height: 10),
                                  _groupLabel('桌面效率'),
                                  _accordion(
                                    id: 'rest',
                                    icon: Icons.notifications_none,
                                    title: '休息提醒',
                                    summary: _restSummary(),
                                    child: _restPanel(),
                                  ),
                                  const SizedBox(height: 24),
                                  Center(
                                    child: Text(
                                      '本地数据 · 你的记录属于你',
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
    if (DataModeManager().isLocal) return '本地优先 · 仅保存在设备';
    if (_syncing) return '云同步 · 同步中…';
    if (_conflictCount > 0) return '云同步 · $_conflictCount 个冲突待处理';
    return '云同步 · 状态正常';
  }

  String _aiSummary() {
    if (!_ai.enabled) return '${_ai.provider.label} · 未启用';
    return '${_ai.provider.label} · ${_hasKey || _ai.provider == AiProviderType.ollama ? '已配置' : '缺少密钥'}';
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
      borderRadius: AppTheme.radiusLg,
      border: Border.all(color: fxBorder(context)),
      expanded: true,
      child: Column(
        children: [
          FxInkWell(
            onTap: () => setState(() => _open = open ? '' : id),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
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
                                      ? Icons.keyboard_arrow_down
                                      : Icons.chevron_right,
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
                                  ? Icons.keyboard_arrow_down
                                  : Icons.chevron_right,
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
          borderRadius: AppTheme.radiusMd,
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
                              Icons.check,
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
            style: TextStyle(fontSize: 14 * visibleScale),
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
        _segmented(const ['本地数据', '云端数据'], local ? 0 : 1, _setDataMode),
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
            _syncing ? '正在同步本地与云端数据' : '自动同步已启用',
            trailing: FxButton(
              label: _syncing ? '同步中…' : '立即同步',
              variant: FxButtonVariant.outline,
              size: FxButtonSize.sm,
              onPressed: _syncing ? null : _syncNow,
            ),
          ),
          _settingLine(
            '同步冲突',
            _conflictCount == 0 ? '无待处理冲突' : '$_conflictCount 个任务需要选择保留版本',
            trailing: FxButton(
              label: '查看冲突 ($_conflictCount)',
              variant: FxButtonVariant.ghost,
              size: FxButtonSize.sm,
              onPressed: _conflictCount == 0 ? null : _openConflicts,
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
    final theme = Theme.of(context);
    final providers = [
      AiProviderType.ollama,
      AiProviderType.openai,
      AiProviderType.deepseek,
    ];
    var providerIndex = providers.indexOf(_ai.provider);
    if (providerIndex < 0) providerIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FxSwitch(
            value: _ai.enabled,
            label: '启用 AI',
            description: '提问引擎与回顾洞察',
            onChanged:
                (value) => setState(() => _ai = _ai.copyWith(enabled: value)),
          ),
        ),
        const SizedBox(height: 12),
        _label('服务商'),
        _segmented(
          providers.map((provider) => provider.label).toList(growable: false),
          providerIndex,
          (index) => _changeProvider(providers[index]),
        ),
        const SizedBox(height: 10),
        _label('接口地址'),
        FxInput(
          controller: _endpoint,
          style: SlowlightTypography.secondary(context),
        ),
        const SizedBox(height: 10),
        _label('模型'),
        FxInput(
          controller: _model,
          style: SlowlightTypography.secondary(context),
        ),
        if (_ai.provider != AiProviderType.ollama) ...[
          const SizedBox(height: 10),
          _label('访问密钥'),
          FxInput(
            controller: _key,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            style: SlowlightTypography.secondary(context),
            placeholder: _hasKey ? '已安全保存；留空保持原值' : '仅保存在本机安全存储',
          ),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .38),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '🔒 本地 Ollama：数据不出设备。数据模式与 AI 模式相互独立。',
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            FxButton(
              label: '测试连接',
              variant: FxButtonVariant.outline,
              size: FxButtonSize.sm,
              onPressed: _savingAi ? null : _testAi,
            ),
            FxButton(
              label: _savingAi ? '保存中…' : '保存',
              size: FxButtonSize.sm,
              onPressed: _savingAi ? null : _saveAi,
            ),
          ],
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
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final stackTrailing =
        trailing != null &&
        scale >= 1.6 &&
        MediaQuery.sizeOf(context).width < 520;
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
      child:
          trailing == null
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

  Future<void> _setDataMode(int index) async {
    if (index == 0) {
      await DataModeManager().setLocal();
    } else {
      final token = await AuthService.getToken();
      if (token == null || token.startsWith('local:')) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        if (!mounted || DataModeManager().isLocal) return;
      } else {
        await DataModeManager().setCloud();
      }
    }
    if (mounted) setState(() {});
    await _loadConflictCount();
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final ok = await CloudSyncCoordinator().syncNow();
    if (!mounted) return;
    setState(() => _syncing = false);
    await _loadConflictCount();
    _message(ok ? '✓ 同步完成' : '同步未执行');
  }

  Future<void> _openConflicts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConflictScreen()),
    );
    if (mounted) await _loadConflictCount();
  }

  Future<void> _changeProvider(AiProviderType provider) async {
    final storedKey = await _aiStore.loadApiKey(provider);
    if (!mounted) return;
    setState(() {
      _ai = _ai.copyWith(provider: provider);
      _endpoint.text = provider.defaultEndpoint;
      _model.text = provider.defaultModel;
      _key.clear();
      _hasKey = storedKey?.isNotEmpty == true;
    });
  }

  AiConfig _aiDraft() =>
      _ai.copyWith(endpoint: _endpoint.text.trim(), model: _model.text.trim());

  Future<String> _effectiveKey() async =>
      _key.text.trim().isNotEmpty
          ? _key.text.trim()
          : await _aiStore.loadApiKey(_ai.provider) ?? '';

  Future<void> _saveAi() async {
    setState(() => _savingAi = true);
    try {
      final draft = _aiDraft();
      final key = await _effectiveKey();
      if (draft.effectiveEndpoint.isEmpty ||
          draft.effectiveModel.isEmpty ||
          (draft.provider.apiKeyRequired && key.isEmpty)) {
        _message('请补全 AI 配置');
        return;
      }
      await _aiStore.save(draft);
      if (_key.text.trim().isNotEmpty) {
        await _aiStore.saveApiKey(draft.provider, _key.text.trim());
      }
      if (!mounted) return;
      setState(() {
        _ai = draft;
        _hasKey = key.isNotEmpty;
        _key.clear();
      });
      _message('✓ AI 配置已保存');
    } finally {
      if (mounted) setState(() => _savingAi = false);
    }
  }

  Future<void> _testAi() async {
    try {
      final text = await AiService(
        configStore: _aiStore,
      ).testConfiguration(_aiDraft(), apiKey: await _effectiveKey());
      _message('连接成功：$text');
    } catch (e) {
      _message('连接失败：$e');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(text));
  }
}
