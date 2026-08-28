import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../services/data_mode_manager.dart';
import '../services/auth_service.dart';
import '../services/migration_service.dart';
import 'login_screen.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';

/// 数据迁移的 UI 原型。执行与冲突计算将在迁移服务接入后绑定到本界面。
class MigrationPreviewDialog extends StatefulWidget {
  const MigrationPreviewDialog({super.key});

  static Future<void> show(BuildContext context) => FxDialog.show<void>(
        context: context,
        width: 920,
        child: const MigrationPreviewDialog(),
      );

  @override
  State<MigrationPreviewDialog> createState() => _MigrationPreviewDialogState();
}

class _MigrationPreviewDialogState extends State<MigrationPreviewDialog> {
  final _counts = <String, int>{
    '任务': 0,
    '习惯': 0,
    '打卡记录': 0,
    '专注记录': 0,
  };
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
            'SELECT COUNT(*) AS count FROM tasks WHERE deleted_at IS NULL'),
        db.rawQuery(
            'SELECT COUNT(*) AS count FROM habits WHERE deleted_at IS NULL'),
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
        _conflicts = (preview['conflicts'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _conflictCount = _conflicts.length;
      }
    } catch (e) {
      // 某些旧数据库尚未拥有所有表；保留已读到的零值，避免阻断设置页。
      _previewError = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 920,
        maxHeight: (MediaQuery.sizeOf(context).height - 72).clamp(480, 700),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogHeader(),
              const SizedBox(height: AppTheme.spaceMd),
              if (compact) ...[
                _steps(horizontal: true),
                const SizedBox(height: AppTheme.spaceMd),
              ],
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact) ...[
                      _steps(horizontal: false),
                      const SizedBox(width: AppTheme.spaceLg),
                      VerticalDivider(color: hfDivider(context), width: 1),
                      const SizedBox(width: AppTheme.spaceLg),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        child: _content(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogHeader() {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Icon(Icons.cloud_upload_outlined,
              size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: AppTheme.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('迁移本地数据到云端',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('先扫描和比较，不会在预览阶段写入或删除数据。',
                  style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            icon: const Icon(Icons.close, size: 19),
          ),
        ),
      ],
    );
  }

  Widget _steps({required bool horizontal}) {
    final items = const [
      (1, '扫描数据', true),
      (2, '处理冲突', true),
      (3, '确认迁移', false),
      (4, '完成', false),
    ];
    if (horizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items
              .map((item) => Padding(
                    padding: const EdgeInsets.only(right: AppTheme.spaceSm),
                    child: _step(item.$1, item.$2, item.$3),
                  ))
              .toList(),
        ),
      );
    }
    return SizedBox(
      width: 136,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
                  child: _step(item.$1, item.$2, item.$3),
                ))
            .toList(),
      ),
    );
  }

  Widget _step(int number, String label, bool active) {
    final theme = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: active
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        child: Text('$number',
            style: TextStyle(
                fontSize: 12,
                color: active
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant)),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
              fontSize: AppTheme.textXs,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
    ]);
  }

  Widget _content() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: AppTheme.spaceMd),
          padding: const EdgeInsets.all(AppTheme.spaceSm),
          decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          child: Row(children: [
            Icon(Icons.shield_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: AppTheme.spaceXs),
            Expanded(
              child: Text('迁移不会删除本地数据，可在完成后查看报告',
                  style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ]),
        ),
        _countGrid(theme),
        const SizedBox(height: 18),
        Text(
          DataModeManager().isCloud
              ? (_conflictCount == 0
                  ? '云端比对完成 · 无冲突'
                  : '处理冲突 · 1 / $_conflictCount')
              : '处理冲突 · 请先登录云端',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (DataModeManager().isCloud && _conflictCount > 0)
          _conflict(theme)
        else
          _emptyComparison(theme),
        Divider(color: hfDivider(context)),
        Text(
            _loading
                ? '正在扫描本机数据…'
                : _previewError != null
                    ? '云端比对失败：$_previewError'
                    : DataModeManager().isCloud
                        ? (_lastReport == null
                            ? '已完成云端比对'
                            : '已完成云端比对 · 最近迁移 $_lastReport')
                        : '登录云端后将计算冲突',
            style: TextStyle(
                fontSize: AppTheme.textXs,
                color: _previewError == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error)),
        const SizedBox(height: AppTheme.spaceSm),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppTheme.spaceXs,
          runSpacing: AppTheme.spaceXs,
          children: [
            FxButton(
                label: _previewError == null ? '取消' : '重试',
                variant: FxButtonVariant.outline,
                onPressed: _previewError == null
                    ? () => Navigator.of(context, rootNavigator: true).pop()
                    : () => setState(() {
                          _loading = true;
                          _previewError = null;
                          _loadCounts();
                        })),
            FxButton(
                label: _executing
                    ? '正在迁移…'
                    : DataModeManager().isCloud
                        ? '确认并迁移'
                        : '切换到云端并预览',
                icon: DataModeManager().isCloud
                    ? Icons.cloud_upload_outlined
                    : Icons.login_outlined,
                onPressed: _executing ? null : _continue),
          ],
        ),
      ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('迁移完成：$report')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('迁移失败：$e')));
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
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
    final updatedToken = await AuthService.getToken();
    if (updatedToken == null || updatedToken.startsWith('local:')) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先登录云端账号后再迁移')));
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

  Widget _countGrid(ThemeData theme) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 440 ? 2 : 4;
          return GridView.count(
            crossAxisCount: columns,
            mainAxisSpacing: AppTheme.spaceXs,
            crossAxisSpacing: AppTheme.spaceXs,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: columns == 2 ? 2.15 : 1.65,
            children: _counts.entries
                .map((entry) => HfStatCell(
                      label: entry.key,
                      value: _loading ? '—' : '${entry.value}',
                    ))
                .toList(),
          );
        },
      );

  Widget _conflict(ThemeData theme) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 500;
            final local =
                _version(theme, '本地版本', _conflictName, Icons.computer_outlined);
            final cloud =
                _version(theme, '云端版本', _conflictName, Icons.cloud_outlined);
            if (compact) {
              return Column(children: [
                local,
                const SizedBox(height: AppTheme.spaceXs),
                cloud,
              ]);
            }
            return Row(children: [
              Expanded(child: local),
              const SizedBox(width: AppTheme.spaceSm),
              Expanded(child: cloud),
            ]);
          }),
          const SizedBox(height: 12),
          Wrap(
            spacing: AppTheme.spaceXs,
            runSpacing: AppTheme.spaceXs,
            children: [
              _choiceButton('local', '保留本地', Icons.computer_outlined),
              _choiceButton('cloud', '保留云端', Icons.cloud_outlined),
              _choiceButton('both', '两份都保留', Icons.copy_outlined),
            ],
          ),
          const SizedBox(height: 10),
          Text('冲突策略将在下一步执行时应用；当前不会覆盖云端数据',
              style:
                  TextStyle(fontSize: 12, color: theme.colorScheme.tertiary)),
        ]),
      );

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

  Widget _emptyComparison(ThemeData theme) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(Icons.cloud_done_outlined,
              color: theme.colorScheme.primary, size: 26),
          const SizedBox(height: 8),
          Text(DataModeManager().isCloud ? '当前没有需要确认的冲突' : '登录云端后即可比较两端数据'),
        ]),
      );

  Widget _version(ThemeData theme, String title, String task, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600))
          ]),
          const SizedBox(height: 12),
          Text(task),
          const SizedBox(height: 5),
          Text('状态、截止日期等字段存在差异',
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ]),
      );

  Widget _choiceButton(String value, String label, IconData icon) => FxButton(
        label: label,
        icon: icon,
        variant: _choice == value
            ? FxButtonVariant.primary
            : FxButtonVariant.outline,
        size: FxButtonSize.sm,
        onPressed: () => setState(() => _choice = value),
      );
}
