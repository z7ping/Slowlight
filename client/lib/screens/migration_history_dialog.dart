import 'dart:convert';

import 'package:flutter/material.dart';

import '../repositories/migration_history_repository.dart';
import '../services/data_mode_manager.dart';
import '../services/migration_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

class MigrationHistoryDialog extends StatefulWidget {
  const MigrationHistoryDialog({super.key});

  static Future<void> show(BuildContext context) => FxDialog.show<void>(
    context: context,
    width: 720,
    title: '迁移历史',
    description: '本机留痕与云端审计分开保存，不会跨模式读取。',
    child: const MigrationHistoryDialog(),
  );

  @override
  State<MigrationHistoryDialog> createState() => _MigrationHistoryDialogState();
}

class _MigrationHistoryDialogState extends State<MigrationHistoryDialog> {
  final _repository = MigrationHistoryRepository();
  late String _source = DataModeManager().isLocal ? 'local' : 'cloud';
  late Future<List<Map<String, dynamic>>> _reports = _load();
  int? _retryingId;

  Future<List<Map<String, dynamic>>> _load() =>
      _source == 'local' ? _repository.local() : _repository.cloud();

  void _reload() => setState(() => _reports = _load());

  @override
  Widget build(BuildContext context) {
    final cloudMode = DataModeManager().isCloud;
    final theme = Theme.of(context);
    return SizedBox(
      width: 660,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cloudMode) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FxSegmented(
                labels: const ['云端审计', '本机记录'],
                selectedIndex: _source == 'cloud' ? 0 : 1,
                onChanged: (index) {
                  _source = index == 0 ? 'cloud' : 'local';
                  _reload();
                },
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
          ] else ...[
            const FxChip(label: '本机记录', variant: FxChipVariant.secondary),
            const SizedBox(height: AppTheme.spaceMd),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 180,
              maxHeight: (MediaQuery.sizeOf(context).height - 260).clamp(
                240,
                480,
              ),
            ),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _reports,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: FxCircularProgress());
                }
                if (snapshot.hasError) return _errorState(snapshot.error);
                final reports = snapshot.data ?? const [];
                if (reports.isEmpty) return _emptyState();
                return ListView.separated(
                  itemCount: reports.length,
                  separatorBuilder:
                      (_, __) => const SizedBox(height: AppTheme.spaceXs),
                  itemBuilder: (_, index) => _report(reports[index]),
                );
              },
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppTheme.spaceSm,
            runSpacing: AppTheme.spaceSm,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Text(
                  _source == 'local'
                      ? '失败的本机记录保留快照，可在云端模式下重试。'
                      : '云端审计不包含原始用户内容或应用密钥。',
                  style: SlowlightTypography.caption(
                    context,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              FxButton(
                label: '关闭',
                variant: FxButtonVariant.outline,
                onPressed:
                    () => Navigator.of(context, rootNavigator: true).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorState(Object? error) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            '读取${_source == 'local' ? '本机' : '云端'}迁移历史失败',
            style: SlowlightTypography.cardTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          FxButton(
            label: '重新加载',
            variant: FxButtonVariant.outline,
            size: FxButtonSize.sm,
            onPressed: _reload,
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_outlined,
            size: 30,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            _source == 'local' ? '还没有本机迁移记录' : '还没有云端审计记录',
            style: SlowlightTypography.cardTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            '完成一次迁移后，时间、策略与结果会显示在这里。',
            textAlign: TextAlign.center,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _report(Map<String, dynamic> report) {
    final status = report['status']?.toString() ?? 'succeeded';
    final local = report['source'] == 'local';
    final id = (report['id'] as num?)?.toInt();
    final canRetry = local && status == 'failed' && id != null;
    final theme = Theme.of(context);
    return FxCard(
      padding: const EdgeInsets.all(AppTheme.spaceSm),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                local ? Icons.computer_outlined : Icons.cloud_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppTheme.spaceXs),
              Expanded(
                child: Text(
                  _formatTime(report['created_at']),
                  style: SlowlightTypography.secondary(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            '${local ? '本机记录' : '云端审计'} · ${_policy(report['conflict_policy'])}',
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          _countLine('扫描', report['scanned']),
          const SizedBox(height: 4),
          _countLine('写入', report['created']),
          if (_error(report).isNotEmpty) ...[
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              _error(report),
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.error),
            ),
          ],
          if (canRetry) ...[
            const SizedBox(height: AppTheme.spaceSm),
            Align(
              alignment: Alignment.centerRight,
              child: FxButton(
                label: _retryingId == id ? '重试中…' : '重试迁移',
                icon: Icons.refresh,
                variant: FxButtonVariant.outline,
                size: FxButtonSize.sm,
                onPressed: _retryingId == null ? () => _retry(report) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final theme = Theme.of(context);
    final failed = status == 'failed';
    final running = status == 'running';
    final color =
        failed
            ? theme.colorScheme.error
            : running
            ? theme.colorScheme.tertiary
            : theme.colorScheme.primary;
    final label =
        failed
            ? '失败'
            : running
            ? '执行中'
            : '成功';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: SlowlightTypography.caption(
          context,
        ).copyWith(fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _countLine(String label, Object? value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            _counts(value),
            style: SlowlightTypography.caption(context),
          ),
        ),
      ],
    );
  }

  Future<void> _retry(Map<String, dynamic> report) async {
    if (!DataModeManager().isCloud) {
      _message('重试需要切换到云端并登录');
      return;
    }
    final id = (report['id'] as num?)?.toInt();
    if (id == null) return;
    setState(() => _retryingId = id);
    try {
      await MigrationService().retryLocalReport(id);
      if (!mounted) return;
      _message('迁移重试成功');
      _reload();
    } catch (error) {
      if (mounted) _message('重试失败：$error');
      _reload();
    } finally {
      if (mounted) setState(() => _retryingId = null);
    }
  }

  void _message(String text) {
    FxNotice.showContent(context, Text(text));
  }

  String _formatTime(Object? value) {
    final raw = value?.toString() ?? '';
    final time = DateTime.tryParse(raw)?.toLocal();
    if (time == null) return raw.isEmpty ? '未知时间' : raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String _error(Map<String, dynamic> report) {
    final error = report['error_summary']?.toString().trim() ?? '';
    return error.isEmpty ? '' : '错误：$error';
  }

  String _policy(Object? value) => switch (value) {
    'local' => '保留本地，云端留备份',
    'cloud' => '保留云端',
    'both' => '两份都保留',
    _ => '无冲突直接写入',
  };

  String _counts(Object? value) {
    try {
      final raw =
          value is Map
              ? Map<String, dynamic>.from(value)
              : Map<String, dynamic>.from(
                jsonDecode(value?.toString() ?? '{}') as Map,
              );
      const labels = {
        'lists': '清单',
        'tasks': '任务',
        'subtasks': '子任务',
        'habits': '习惯',
        'habit_logs': '打卡',
        'sessions': '专注',
      };
      return labels.entries
          .map((item) => '${item.value} ${raw[item.key] ?? 0}')
          .join(' · ');
    } catch (_) {
      return '统计摘要不可用';
    }
  }
}
