import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../services/api/task_api.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

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
    final rows = await _sync.getAllConflicts();
    final previews = <_ConflictPreview>[];
    for (final local in rows) {
      final type = local['_entity_type'] as String;
      Map<String, dynamic>? remote;
      final serverId = local['server_id'] as int?;
      if (serverId != null && serverId > 0) {
        try {
          if (type == 'tasks') {
            remote = _taskPreview(await TaskApi.getTask(serverId));
          } else {
            remote = await _sync.fetchConflictRemote(type, local);
          }
        } catch (_) {
          // 离线时仍显示本地冲突，不伪装成无冲突。
        }
      }
      previews.add(_ConflictPreview(
        entityType: type, local: local, remote: remote,
      ));
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
            FxPageHeader(
              title: '同步冲突',
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child:
                  _loading
                      ? const Center(child: FxCircularProgress())
                      : _conflicts.isEmpty
                      ? _empty(theme)
                      : FxRefresh(
                        onRefresh: _loadConflicts,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                          itemCount: _conflicts.length + 1,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index == 0) return _intro(theme);
                            return _conflictCard(_conflicts[index - 1], theme);
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
        child: FxCard(
          padding: const EdgeInsets.all(14),
          expanded: true,
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
                  '本地与服务端记录存在冲突。请比较版本并选择保留哪一侧；无法读取服务端时不会自动覆盖。',
                  style: SlowlightTypography.secondary(
                    context,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
          Icon(LucideIcons.circleCheck, size: 38, color: AppTheme.success),
          const SizedBox(height: 10),
          Text('没有同步冲突', style: SlowlightTypography.cardTitle(context)),
          const SizedBox(height: 4),
          Text(
            '本地数据和服务端数据已经一致',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _conflictCard(_ConflictPreview preview, ThemeData theme) {
    final local = preview.local;
    final remote = preview.remote;
    final title = local['title']?.toString() ??
        local['name']?.toString() ??
        local['date']?.toString() ??
        '记录';
    final entityType = preview.entityType;
    final id = local['id'] as int?;
    final hasServerId = (local['server_id'] as int? ?? 0) > 0;
    final canKeepLocal = hasServerId && entityType != 'habit_logs';
    final mobile = MediaQuery.sizeOf(context).width < 700;

    final localCard = _versionCard(
      title: '本地版本', data: local, accent: true,
      entityType: entityType,
    );
    final remoteCard = _versionCard(
      title: '服务端版本', data: remote, accent: false,
      entityType: entityType,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: FxCard(
          padding: const EdgeInsets.all(16),
          expanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.cloudAlert,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_entityTypeName(entityType)} · $title',
                      style: SlowlightTypography.cardTitle(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '版本 ${local['version'] ?? 1}',
                      textAlign: TextAlign.end,
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
              if (!hasServerId || entityType == 'habit_logs')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    !hasServerId
                        ? '缺少服务端记录 ID：为避免重复创建，暂不支持直接覆盖，请先核对云端记录。'
                        : '习惯记录不支持远端覆盖写入；可以使用服务端版本，或保留本地数据稍后处理。',
                    style: SlowlightTypography.secondary(context),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FxButton(
                    label: '保留本地版本',
                    variant: FxButtonVariant.outline,
                    onPressed:
                        id == null || !canKeepLocal
                            ? null
                            : () => _resolveConflict(
                                id, entityType: entityType, keepLocal: true,
                              ),
                  ),
                  FxButton(
                    label: '使用服务端版本',
                    onPressed:
                        id == null || remote == null
                            ? null
                            : () => _resolveConflict(
                                id, entityType: entityType, keepLocal: false,
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
    required String entityType,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            accent
                ? activePalette.accent.withValues(alpha: .05)
                : theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(SlowlightRadius.lg),
        border: Border.all(
          color:
              accent ? activePalette.accent : theme.colorScheme.outlineVariant,
        ),
      ),
      child:
          data == null
              ? Text(
                '暂时无法读取服务端版本',
                style: SlowlightTypography.secondary(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SlowlightTypography.caption(context).copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          accent
                              ? activePalette.accent
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (entityType == 'tasks') ...[
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
                  ] else
                    for (final entry in data.entries)
                      if (!{
                        'id', 'server_id', 'sync_status', 'version',
                        'device_id', 'last_modified', '_entity_type',
                      }.contains(entry.key))
                        _field(_attributeName(entry.key), entry.value),
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
            width: 64,
            child: Text(
              label,
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(text, style: SlowlightTypography.caption(context)),
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

  String _entityTypeName(String type) => switch (type) {
    'tasks' => '任务',
    'lists' => '清单',
    'tags' => '标签',
    'system_tags' => '标签（旧数据）',
    'habits' => '习惯',
    'habit_logs' => '习惯记录',
    _ => type,
  };

  String _attributeName(String name) => switch (name) {
    'name' => '名称',
    'date' => '日期',
    'period' => '时间段',
    'duration_min' => '时长',
    'note' => '备注',
    'color' => '颜色',
    'frequency' => '频率',
    'dimension_key' => '历史分类',
    'deleted_at' => '删除时间',
    _ => name,
  };

  Future<void> _resolveConflict(int localId, {
    required String entityType,
    required bool keepLocal,
  }) async {
    final resolved = await _sync.resolveConflict(
      localId, entityType: entityType, keepLocal: keepLocal,
    );
    if (!mounted) return;
    FxNotice.showContent(
      context,
      Text(resolved
          ? (keepLocal ? '已保留本地版本，等待同步' : '已使用服务端版本')
          : '处理失败，数据已保留，请稍后重试'),
    );
    await _loadConflicts();
  }
}

class _ConflictPreview {
  final String entityType;
  final Map<String, dynamic> local;
  final Map<String, dynamic>? remote;

  const _ConflictPreview({
    required this.entityType,
    required this.local,
    required this.remote,
  });
}
