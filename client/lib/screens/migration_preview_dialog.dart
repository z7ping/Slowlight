import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../services/auth_service.dart';
import '../services/data_mode_manager.dart';
import '../services/migration_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'login_screen.dart';

/// 本地数据迁移到云端的预览与冲突确认界面。
class MigrationPreviewDialog extends StatefulWidget {
  const MigrationPreviewDialog({super.key});

  static Future<void> show(BuildContext context) => FxDialog.show<void>(
    context: context,
    width: 880,
    child: const MigrationPreviewDialog(),
  );

  @override
  State<MigrationPreviewDialog> createState() => _MigrationPreviewDialogState();
}

class _MigrationPreviewDialogState extends State<MigrationPreviewDialog> {
  final _counts = <String, int>{'任务': 0, '习惯': 0, '打卡记录': 0, '专注记录': 0};

  bool _loading = true;
  String _choice = 'local';
  int _conflictCount = 0;
  List<Map<String, dynamic>> _conflicts = const [];
  String? _previewError;
  String? _lastReport;
  bool _executing = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final db = await LocalDb().database;
      final values = await Future.wait([
        db.rawQuery(
          'SELECT COUNT(*) AS count FROM tasks WHERE deleted_at IS NULL',
        ),
        db.rawQuery(
          'SELECT COUNT(*) AS count FROM habits WHERE deleted_at IS NULL',
        ),
        db.rawQuery('SELECT COUNT(*) AS count FROM habit_logs'),
        db.rawQuery('SELECT COUNT(*) AS count FROM work_sessions'),
      ]);
      const labels = ['任务', '习惯', '打卡记录', '专注记录'];
      for (var i = 0; i < labels.length; i++) {
        _counts[labels[i]] = (values[i].first['count'] as int?) ?? 0;
      }

      if (DataModeManager().isCloud) {
        final report = await MigrationService().latestReport();
        _lastReport = report?['created_at']?.toString();
        final preview = await MigrationService().preview();
        final summary = Map<String, dynamic>.from(preview['summary'] as Map);
        _counts['任务'] = (summary['tasks'] as num?)?.toInt() ?? _counts['任务']!;
        _counts['习惯'] = (summary['habits'] as num?)?.toInt() ?? _counts['习惯']!;
        _counts['打卡记录'] =
            (summary['habit_logs'] as num?)?.toInt() ?? _counts['打卡记录']!;
        _counts['专注记录'] =
            (summary['sessions'] as num?)?.toInt() ?? _counts['专注记录']!;
        _conflicts =
            (preview['conflicts'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
        _conflictCount = _conflicts.length;
      }
    } catch (e) {
      _previewError = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _currentStep {
    if (_loading) return 0;
    if (!DataModeManager().isCloud) return 1;
    if (_conflictCount > 0) return 1;
    return 2;
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    final theme = Theme.of(context);
    return FxCard(
      padding: padding,
      color: fxSurface(context),
      borderRadius: SlowlightRadius.lg,
      border: Border.all(color: fxBorder(context)),
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
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 880,
        maxHeight: (MediaQuery.sizeOf(context).height - 96).clamp(520.0, 660.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dialogHeader(),
          const SizedBox(height: SlowlightSpacing.xl),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _overviewCard(),
                  const SizedBox(height: SlowlightSpacing.xxxl),
                  const FxSectionHeader(
                    title: '迁移进度',
                    trailing: '先扫描、再比对，最后由你确认写入',
                  ),
                  const SizedBox(height: SlowlightSpacing.xs),
                  _progressCard(),
                  const SizedBox(height: SlowlightSpacing.xxxl),
                  const FxSectionHeader(
                    title: '迁移数据',
                    trailing: '当前只读取数量，不会修改本地数据',
                  ),
                  const SizedBox(height: SlowlightSpacing.xs),
                  _countGrid(),
                  const SizedBox(height: SlowlightSpacing.xxxl),
                  FxSectionHeader(
                    title: '冲突处理',
                    trailing:
                        DataModeManager().isCloud
                            ? (_conflictCount == 0
                                ? '云端比对完成 · 无需处理'
                                : '发现 $_conflictCount 项需要确认')
                            : '登录云端后才会读取并比较云端数据',
                  ),
                  const SizedBox(height: SlowlightSpacing.xs),
                  if (DataModeManager().isCloud && _conflictCount > 0)
                    _conflictCard()
                  else
                    _comparisonStateCard(),
                ],
              ),
            ),
          ),
          const SizedBox(height: SlowlightSpacing.xl),
          _footer(),
        ],
      ),
    );
  }

  Widget _dialogHeader() {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '迁移本地数据到云端',
                style: SlowlightTypography.pageTitle(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                '先扫描和比较，再决定如何处理冲突；预览阶段不会写入或删除数据。',
                style: SlowlightTypography.caption(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        FxIconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          icon: Icons.close,
          iconSize: 19,
        ),
      ],
    );
  }

  Widget _overviewCard() {
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
                  Icons.cloud_upload_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: SlowlightSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本机数据 → Slowlight 云端',
                      style: SlowlightTypography.cardTitle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '本地数据始终保留；只有最终确认后才会开始迁移。',
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
              _chip('本机 → 云端'),
              _chip(
                DataModeManager().isCloud ? '云端已连接' : '云端未登录',
                accent: DataModeManager().isCloud,
              ),
              _chip(
                _loading
                    ? '正在扫描'
                    : _previewError != null
                    ? '比对异常'
                    : '预览就绪',
                accent: !_loading && _previewError == null,
              ),
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

  Widget _progressCard() {
    const labels = ['扫描数据', '处理冲突', '确认迁移', '完成'];
    return _card(
      padding: const EdgeInsets.symmetric(
        horizontal: SlowlightSpacing.xl,
        vertical: SlowlightSpacing.md,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 560 ||
              MediaQuery.textScalerOf(
                    context,
                  ).scale(SlowlightTypography.secondarySize) >=
                  SlowlightTypography.secondarySize * 1.3;
          if (compact) {
            return Wrap(
              spacing: SlowlightSpacing.xl,
              runSpacing: SlowlightSpacing.md,
              children: List.generate(
                labels.length,
                (index) => _progressItem(index, labels[index]),
              ),
            );
          }
          return Row(
            children: List.generate(labels.length * 2 - 1, (position) {
              if (position.isOdd) {
                final before = position ~/ 2;
                return Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: SlowlightSpacing.xs,
                    ),
                    color:
                        before < _currentStep
                            ? Theme.of(context).colorScheme.primary
                            : fxDivider(context),
                  ),
                );
              }
              final index = position ~/ 2;
              return _progressItem(index, labels[index]);
            }),
          );
        },
      ),
    );
  }

  Widget _progressItem(int index, String label) {
    final theme = Theme.of(context);
    final completed = index < _currentStep;
    final current = index == _currentStep;
    final emphasized = completed || current;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                emphasized
                    ? theme.colorScheme.primary
                    : fxSubtleSurface(context),
            shape: BoxShape.circle,
          ),
          child:
              completed
                  ? Icon(
                    Icons.check,
                    size: 14,
                    color: theme.colorScheme.onPrimary,
                  )
                  : Text(
                    '${index + 1}',
                    style: SlowlightTypography.caption(context).copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          current
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: SlowlightTypography.caption(context).copyWith(
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
            color:
                emphasized
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _countGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final largeText =
          MediaQuery.textScalerOf(
            context,
          ).scale(SlowlightTypography.bodySize) >=
          SlowlightTypography.bodySize * 1.3;
      final columns =
          largeText
              ? 1
              : constraints.maxWidth < 520
              ? 2
              : 4;
      return GridView.count(
        crossAxisCount: columns,
        mainAxisSpacing: SlowlightSpacing.xs,
        crossAxisSpacing: SlowlightSpacing.xs,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio:
            columns == 1
                ? 3.4
                : columns == 2
                ? 2.45
                : 1.95,
        children:
            _counts.entries
                .map(
                  (entry) => FxStatCell(
                    label: entry.key,
                    value: _loading ? '—' : '${entry.value}',
                  ),
                )
                .toList(),
      );
    },
  );

  Widget _comparisonStateCard() {
    final theme = Theme.of(context);
    final cloud = DataModeManager().isCloud;
    return _card(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .42),
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
            ),
            child: Icon(
              cloud ? Icons.cloud_done_outlined : Icons.login_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: SlowlightSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cloud ? '当前没有需要确认的冲突' : '登录云端后开始数据比对',
                  style: SlowlightTypography.secondary(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  cloud ? '可以继续到确认迁移；本地数据仍不会被删除。' : '登录仅用于读取云端并生成冲突预览，确认前不会写入。',
                  style: SlowlightTypography.caption(
                    context,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictCard() {
    final theme = Theme.of(context);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final local = _version(
                theme,
                '本地版本',
                _conflictName,
                Icons.computer_outlined,
              );
              final cloud = _version(
                theme,
                '云端版本',
                _conflictName,
                Icons.cloud_outlined,
              );
              if (compact) {
                return Column(
                  children: [
                    local,
                    const SizedBox(height: SlowlightSpacing.xs),
                    cloud,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: local),
                  const SizedBox(width: SlowlightSpacing.md),
                  Expanded(child: cloud),
                ],
              );
            },
          ),
          const SizedBox(height: SlowlightSpacing.md),
          Wrap(
            spacing: SlowlightSpacing.xs,
            runSpacing: SlowlightSpacing.xs,
            children: [
              _choiceButton('local', '保留本地', Icons.computer_outlined),
              _choiceButton('cloud', '保留云端', Icons.cloud_outlined),
              _choiceButton('both', '两份都保留', Icons.copy_outlined),
            ],
          ),
          const SizedBox(height: SlowlightSpacing.xs),
          Text(
            '冲突策略将在确认迁移后应用；当前不会覆盖任何云端数据。',
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String get _conflictName {
    final conflict = _conflicts.isEmpty ? null : _conflicts.first;
    final name = conflict?['name']?.toString().trim();
    final entity = switch (conflict?['entity']) {
      'list' => '清单',
      'tag' => '标签',
      'system_tag' => '系统标签',
      'habit' => '习惯',
      _ => '记录',
    };
    return name == null || name.isEmpty ? entity : '$entity：$name';
  }

  Widget _version(ThemeData theme, String title, String item, IconData icon) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SlowlightSpacing.md),
        decoration: BoxDecoration(
          color: fxSubtleSurface(context).withValues(alpha: .45),
          borderRadius: BorderRadius.circular(SlowlightRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: SlowlightSpacing.md),
            Text(item),
            const SizedBox(height: 4),
            Text(
              '状态、截止日期等字段存在差异',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );

  Widget _choiceButton(String value, String label, IconData icon) => FxButton(
    label: label,
    icon: icon,
    variant:
        _choice == value ? FxButtonVariant.primary : FxButtonVariant.outline,
    size: FxButtonSize.sm,
    onPressed: () => setState(() => _choice = value),
  );

  Widget _footer() {
    final theme = Theme.of(context);
    final status =
        _loading
            ? '正在扫描本机数据…'
            : _previewError != null
            ? '云端比对失败：$_previewError'
            : DataModeManager().isCloud
            ? (_lastReport == null ? '预览已就绪' : '预览已就绪 · 最近迁移 $_lastReport')
            : '登录云端后将计算冲突';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: SlowlightSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: fxDivider(context))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Wrap(
            alignment: WrapAlignment.end,
            spacing: SlowlightSpacing.xs,
            runSpacing: SlowlightSpacing.xs,
            children: [
              FxButton(
                label: _previewError == null ? '取消' : '重试',
                variant: FxButtonVariant.outline,
                onPressed:
                    _previewError == null
                        ? () => Navigator.of(context, rootNavigator: true).pop()
                        : () => setState(() {
                          _loading = true;
                          _previewError = null;
                          _loadCounts();
                        }),
              ),
              FxButton(
                label:
                    _executing
                        ? '正在迁移…'
                        : DataModeManager().isCloud
                        ? '确认并迁移'
                        : '登录云端并预览',
                icon:
                    DataModeManager().isCloud
                        ? Icons.cloud_upload_outlined
                        : Icons.login_outlined,
                onPressed: _executing ? null : _continue,
              ),
            ],
          );

          final statusText = Text(
            status,
            maxLines: constraints.maxWidth < 620 ? null : 1,
            overflow: constraints.maxWidth < 620 ? null : TextOverflow.ellipsis,
            style: SlowlightTypography.caption(context).copyWith(
              color:
                  _previewError == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
            ),
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                statusText,
                const SizedBox(height: SlowlightSpacing.xs),
                actions,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: statusText),
              const SizedBox(width: SlowlightSpacing.xl),
              actions,
            ],
          );
        },
      ),
    );
  }

  Future<void> _execute() async {
    setState(() => _executing = true);
    try {
      final result = await MigrationService().execute(conflictPolicy: _choice);
      if (!mounted) return;
      final created = Map<String, dynamic>.from(result['created'] as Map);
      final report = <String>[
        '清单 ${created['lists'] ?? 0}',
        '任务 ${created['tasks'] ?? 0}',
        '子任务 ${created['subtasks'] ?? 0}',
        '习惯 ${created['habits'] ?? 0}',
        '打卡 ${created['habit_logs'] ?? 0}',
        '专注 ${created['sessions'] ?? 0}',
      ].join(' · ');
      FxNotice.showContent(context, Text('迁移完成：$report'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(context, Text('迁移失败：$e'));
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  Future<void> _continue() async {
    if (DataModeManager().isCloud) {
      await _execute();
      return;
    }

    final token = await AuthService.getToken();
    if (token == null || token.startsWith('local:')) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }

    final updatedToken = await AuthService.getToken();
    if (updatedToken == null || updatedToken.startsWith('local:')) {
      if (mounted) {
        FxNotice.showContent(context, Text('请先登录云端账号后再迁移'));
      }
      return;
    }

    await DataModeManager().setCloud();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _previewError = null;
    });
    await _loadCounts();
  }
}
