part of 'feishu_screen.dart';

extension _FeishuScreenSections on _FeishuScreenState {
  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    Color? color,
    Border? border,
  }) {
    final theme = Theme.of(context);
    return FxCard(
      padding: padding,
      color: color ?? fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: border ?? Border.all(color: fxBorder(context)),
      boxShadow:
          theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
      expanded: true,
      child: child,
    );
  }

  Widget _chip(String label, {bool accent = false}) {
    final theme = Theme.of(context);
    return FxChip(
      label: label,
      backgroundColor:
          accent
              ? activePalette.accent.withValues(alpha: .12)
              : fxSubtleSurface(context),
      foregroundColor:
          accent ? activePalette.accent : theme.colorScheme.onSurfaceVariant,
      borderRadius: SlowlightRadius.pill,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    );
  }

  Widget _buildLoadError() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 34,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: SlowlightSpacing.md),
              const Text(
                '无法读取飞书配置',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: SlowlightTypography.caption(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: SlowlightSpacing.xl),
              FxButton(
                label: '重新加载',
                icon: Icons.refresh,
                variant: FxButtonVariant.outline,
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _loadError = null;
                  });
                  _loadConfig();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            SlowlightSpacing.xl,
            SlowlightSpacing.xl,
            SlowlightSpacing.xl,
            SlowlightSpacing.page,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverview(),
                  const SizedBox(height: SlowlightSpacing.xxxl),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: _buildConfigurationColumn()),
                        const SizedBox(width: SlowlightSpacing.xxxl),
                        Expanded(flex: 6, child: _buildOperationsColumn()),
                      ],
                    )
                  else ...[
                    _buildConfigurationColumn(),
                    const SizedBox(height: SlowlightSpacing.xxxl),
                    _buildOperationsColumn(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverview() {
    final theme = Theme.of(context);
    return _card(
      padding: const EdgeInsets.all(SlowlightSpacing.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final identity = Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: .55,
                  ),
                  borderRadius: BorderRadius.circular(SlowlightRadius.md),
                ),
                child: Icon(
                  Icons.table_chart_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: SlowlightSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '飞书多维表格',
                      style: SlowlightTypography.cardTitle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _isConfigured ? '连接已就绪，可按数据类型同步' : '填写应用凭据后创建或绑定数据表',
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          );
          final badges = Wrap(
            spacing: SlowlightSpacing.xs,
            runSpacing: SlowlightSpacing.xs,
            children: [
              _chip(_cloud ? '云端配置' : '本机配置'),
              _chip(_isConfigured ? '已连接' : '未连接', accent: _isConfigured),
              if (_tables.isNotEmpty) _chip('已识别 ${_tables.length} 张表'),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: SlowlightSpacing.md),
                badges,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: SlowlightSpacing.xl),
              badges,
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigurationColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FxSectionHeader(title: '连接配置', trailing: '密钥保存在当前数据模式对应的安全存储中'),
        const SizedBox(height: SlowlightSpacing.xs),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FxInput(
                controller: _appIdController,
                label: '应用标识',
                placeholder: 'cli_xxxxxxxxxxxxxxxx',
                leading: const Icon(Icons.key_outlined, size: 18),
              ),
              const SizedBox(height: SlowlightSpacing.md),
              FxInput(
                controller: _appSecretController,
                label: '应用密钥',
                placeholder: _isConfigured ? '重新保存配置时需要填写' : '请输入应用密钥',
                obscureText: !_showSecret,
                leading: const Icon(Icons.lock_outline, size: 18),
                trailing: FxIconButton(
                  tooltip: _showSecret ? '隐藏密钥' : '显示密钥',
                  onPressed: () => setState(() => _showSecret = !_showSecret),
                  icon:
                      _showSecret
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                ),
              ),
              const SizedBox(height: SlowlightSpacing.md),
              FxInput(
                controller: _tableUrlController,
                label: '多维表格链接',
                placeholder: 'https://my.feishu.cn/base/xxxxx',
                leading: const Icon(Icons.link, size: 18),
              ),
              const SizedBox(height: SlowlightSpacing.xl),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: SlowlightSpacing.xs,
                runSpacing: SlowlightSpacing.xs,
                children: [
                  FxButton(
                    label: _isConnecting ? '绑定中…' : '绑定现有表格',
                    icon: Icons.link,
                    variant: FxButtonVariant.outline,
                    onPressed: _isConnecting ? null : _connectExisting,
                  ),
                  FxButton(
                    label: _isSaving ? '保存中…' : '保存配置',
                    icon: Icons.save_outlined,
                    onPressed: _isSaving ? null : _saveConfig,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SlowlightSpacing.xxxl),
        const FxSectionHeader(title: '数据模板', trailing: '首次连接建议从这里开始'),
        const SizedBox(height: SlowlightSpacing.xs),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: SlowlightSpacing.xs),
                  Expanded(
                    child: Text(
                      '创建标准的 8 张数据表',
                      style: SlowlightTypography.secondary(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SlowlightSpacing.xs),
              Text(
                '任务、子任务、清单、习惯、习惯记录、专注、休息记录和标签。创建后会自动填入表格链接。',
                style: SlowlightTypography.caption(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SlowlightSpacing.md),
              FxButton(
                label: _isCreatingTemplate ? '创建中…' : '创建数据模板',
                icon: Icons.auto_awesome,
                variant: FxButtonVariant.outline,
                onPressed: _isCreatingTemplate ? null : _createTemplate,
              ),
            ],
          ),
        ),
        const SizedBox(height: SlowlightSpacing.xxxl),
        _buildGuide(),
      ],
    );
  }

  Widget _buildOperationsColumn() {
    final disabled = !_isConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FxSectionHeader(
          title: '数据同步',
          trailing: _cloud ? '通过 Slowlight Server' : '从本机 SQLite 单向导出',
          trailingWidget: FxButton(
            label: _isSyncingAll ? '同步中…' : '同步全部',
            icon: Icons.sync,
            size: FxButtonSize.sm,
            onPressed: disabled || _isSyncingAll ? null : _syncAll,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.xs),
        _card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _FeishuActionTile(
                icon: Icons.task_alt_outlined,
                title: '任务与清单',
                subtitle: '同步任务、子任务、清单与习惯数据',
                busy: _isSyncing,
                enabled: !disabled,
                onTap: _syncToFeishu,
              ),
              _FeishuActionTile(
                icon: Icons.timer_outlined,
                title: '专注记录',
                subtitle: '同步已结束的专注会话与关联任务',
                busy: _isSyncingSessions,
                enabled: !disabled,
                onTap: _syncSessionsToFeishu,
              ),
              _FeishuActionTile(
                icon: Icons.self_improvement_outlined,
                title: '休息记录',
                subtitle: '同步工作与休息行为事实',
                busy: _isSyncingReminders,
                enabled: !disabled,
                onTap: _syncRemindersToFeishu,
              ),
              _FeishuActionTile(
                icon: Icons.label_outline,
                title: '标签',
                subtitle: '同步观察标签及关联信息',
                busy: _isSyncingTags,
                enabled: !disabled,
                onTap: _syncTagsToFeishu,
                last: !_cloud,
              ),
              if (_cloud)
                _FeishuActionTile(
                  icon: Icons.cloud_download_outlined,
                  title: '从飞书导入',
                  subtitle: '仅云端模式可用；导入前请确认表格内容',
                  busy: _isImporting,
                  enabled: !disabled,
                  onTap: _importFromFeishu,
                  last: true,
                ),
            ],
          ),
        ),
        if (!_cloud) ...[
          const SizedBox(height: SlowlightSpacing.xs),
          Text(
            '本机模式当前只支持导出，不支持从飞书导入或双向冲突处理。',
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
        if (_cloud) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          _buildCalendarSection(),
        ],
      ],
    );
  }

  Widget _buildCalendarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FxSectionHeader(
          title: '飞书日历',
          trailing: '把有截止日期的任务创建为日历事件',
          trailingWidget: FxButton(
            label: '刷新',
            variant: FxButtonVariant.ghost,
            size: FxButtonSize.sm,
            onPressed: _isLoadingCalendars ? null : _loadCalendars,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.xs),
        _card(
          child:
              _isLoadingCalendars
                  ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(SlowlightSpacing.xl),
                      child: FxCircularProgress(),
                    ),
                  )
                  : _calendars.isEmpty
                  ? _calendarEmpty()
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FxSelect<String>(
                        value: _selectedCalendarId,
                        placeholder: '选择飞书日历',
                        options:
                            _calendars
                                .map(
                                  (item) => FxSelectOption<String>(
                                    value: item['id']?.toString() ?? '',
                                    label:
                                        '${item['name'] ?? '未命名'}${item['is_primary'] == true ? ' · 主日历' : ''}',
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (value) =>
                                setState(() => _selectedCalendarId = value),
                      ),
                      const SizedBox(height: SlowlightSpacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FxButton(
                          label: _isSyncingCalendar ? '同步中…' : '同步到日历',
                          icon: Icons.event_available_outlined,
                          onPressed:
                              _isSyncingCalendar ? null : _syncToCalendar,
                        ),
                      ),
                    ],
                  ),
        ),
      ],
    );
  }

  Widget _calendarEmpty() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: SlowlightSpacing.xs),
          Expanded(
            child: Text(
              '没有读取到可用日历，请检查应用权限后刷新。',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuide() {
    final theme = Theme.of(context);
    const steps = [
      '在飞书开放平台创建企业自建应用',
      '开通多维表格读写权限，并将应用加入表格协作者',
      '填写应用标识和密钥，创建模板或绑定已有表格',
      '按数据类型同步；首次操作建议先检查目标表格',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FxSectionHeader(title: '连接步骤'),
        const SizedBox(height: SlowlightSpacing.xs),
        _card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: .22),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: .12),
          ),
          child: Column(
            children: List.generate(
              steps.length,
              (index) => Padding(
                padding: EdgeInsets.only(
                  bottom: index == steps.length - 1 ? 0 : SlowlightSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: SlowlightTypography.caption(context).copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: SlowlightSpacing.xs),
                    Expanded(
                      child: Text(
                        steps[index],
                        style: SlowlightTypography.caption(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeishuActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;
  final bool last;

  const _FeishuActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: FxInkWell(
        onTap: enabled && !busy ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(
            horizontal: SlowlightSpacing.md,
            vertical: SlowlightSpacing.xs,
          ),
          decoration: BoxDecoration(
            border:
                last
                    ? null
                    : Border(bottom: BorderSide(color: fxDivider(context))),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: .42,
                  ),
                  borderRadius: BorderRadius.circular(SlowlightRadius.md),
                ),
                child: Icon(icon, size: 19, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: SlowlightSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                ),
              ),
              const SizedBox(width: SlowlightSpacing.xs),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: FxCircularProgress(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
