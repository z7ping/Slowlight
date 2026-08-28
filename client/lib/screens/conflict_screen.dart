import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../services/api/task_api.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/high_fidelity/hf_page_header.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';

/// 同步冲突：明确并排展示“本地版本 / 服务端版本”，再由用户选择。
class ConflictScreen extends StatefulWidget {
  const ConflictScreen({super.key});

  @override
  State<ConflictScreen> createState() => _ConflictScreenState();
}

class _ConflictScreenState extends State<ConflictScreen> {
  final _sync = SyncService();
  List<_ConflictPreview> _conflicts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    if (mounted) setState(() => _loading = true);
    final rows = await _sync.getConflicts('tasks');
    final previews = <_ConflictPreview>[];
    for (final local in rows) {
      Map<String, dynamic>? remote;
      final serverId = local['server_id'] as int?;
      if (serverId != null && serverId > 0) {
        try {
          final task = await TaskApi.getTask(serverId);
          remote = _taskPreview(task);
        } catch (_) {}
      }
      previews.add(_ConflictPreview(local: local, remote: remote));
    }
    if (!mounted) return;
    setState(() {
      _conflicts = previews;
      _loading = false;
    });
  }

  Map<String, dynamic> _taskPreview(Task task) => {
        'title': task.title,
        'description': task.description ?? '',
        'priority': task.priority,
        'due_date': task.dueDate?.toIso8601String(),
        'due_time': task.dueTime ?? '',
        'is_completed': task.isCompleted ? 1 : 0,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            HfPageHeader(
              title: '同步冲突',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _conflicts.isEmpty
                      ? _empty(theme)
                      : RefreshIndicator(
                          onRefresh: _loadConflicts,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                            itemCount: _conflicts.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              if (index == 0) return _intro(theme);
                              return _conflictCard(
                                _conflicts[index - 1],
                                theme,
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: HfCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.triangleAlert,
                size: 18,
                color: AppTheme.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '同一条任务在本机和服务端都发生了修改。请选择要保留的版本，处理后会继续同步。',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleCheck,
            size: 38,
            color: AppTheme.success,
          ),
          const SizedBox(height: 10),
          const Text(
            '没有同步冲突',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '本地数据和服务端数据已经一致',
            style: TextStyle(
              fontSize: AppTheme.textSm,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictCard(_ConflictPreview preview, ThemeData theme) {
    final local = preview.local;
    final remote = preview.remote;
    final title = local['title']?.toString() ?? '未知任务';
    final id = local['id'] as int?;
    final mobile = MediaQuery.sizeOf(context).width < 700;

    final localCard = _versionCard(
      title: '本地版本',
      data: local,
      accent: true,
    );
    final remoteCard = _versionCard(
      title: '服务端版本',
      data: remote,
      accent: false,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: HfCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.cloudAlert,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '版本 ${local['version'] ?? 1}',
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (mobile) ...[
                localCard,
                const SizedBox(height: 10),
                remoteCard,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: localCard),
                    const SizedBox(width: 10),
                    Expanded(child: remoteCard),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FxButton(
                      label: '保留本地版本',
                      variant: FxButtonVariant.outline,
                      onPressed: id == null
                          ? null
                          : () => _resolveConflict(id, keepLocal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FxButton(
                      label: '使用服务端版本',
                      onPressed: id == null || remote == null
                          ? null
                          : () => _resolveConflict(id, keepLocal: false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _versionCard({
    required String title,
    required Map<String, dynamic>? data,
    required bool accent,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent
            ? activePalette.accent.withValues(alpha: .05)
            : theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: accent ? activePalette.accent : hfBorder(context),
        ),
      ),
      child: data == null
          ? Text(
              '暂时无法读取服务端版本',
              style: TextStyle(
                fontSize: AppTheme.textSm,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTheme.textXs,
                    fontWeight: FontWeight.w700,
                    color: accent
                        ? activePalette.accent
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _field('标题', data['title']),
                _field('描述', data['description']),
                _field('优先级', _priorityLabel(data['priority']?.toString())),
                _field('日期', _dateText(data['due_date'])),
                _field('时间', data['due_time']),
                _field(
                  '状态',
                  data['is_completed'] == 1 || data['is_completed'] == true
                      ? '已完成'
                      : '未完成',
                ),
              ],
            ),
    );
  }

  Widget _field(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTheme.textXs,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: AppTheme.textXs)),
          ),
        ],
      ),
    );
  }

  String _priorityLabel(String? value) => switch (value) {
        'high' || 'urgent_important' => '高',
        'medium' || 'important' => '中',
        'low' || 'urgent' => '低',
        _ => '无',
      };

  String _dateText(Object? value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  Future<void> _resolveConflict(int localId, {required bool keepLocal}) async {
    await _sync.resolveConflict(localId, keepLocal: keepLocal);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(keepLocal ? '已保留本地版本' : '已使用服务端版本'),
      ),
    );
    await _loadConflicts();
  }
}

class _ConflictPreview {
  final Map<String, dynamic> local;
  final Map<String, dynamic>? remote;

  const _ConflictPreview({required this.local, required this.remote});
}
