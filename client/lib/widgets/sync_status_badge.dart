import 'package:flutter/material.dart';

import '../screens/conflict_screen.dart';
import '../services/cloud_sync_coordinator.dart';
import '../services/data_mode_manager.dart';
import '../services/sync_service.dart';
import '../ui/fx.dart';

/// 同步状态指示器 — 显示在 AppBar 或 Drawer
class SyncStatusBadge extends StatelessWidget {
  final bool showHealthy;
  final bool showLocal;

  const SyncStatusBadge({
    super.key,
    this.showHealthy = false,
    this.showLocal = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataModeManager(),
      builder: (context, _) {
        if (DataModeManager().isLocal) {
          return showLocal
              ? _statusPill(
                context,
                icon: Icons.check_circle_outline,
                text: '本地数据',
                color: Theme.of(context).colorScheme.primary,
              )
              : const SizedBox.shrink();
        }

        return ListenableBuilder(
          listenable: SyncService(),
          builder: (context, _) {
            final sync = SyncService();
            return ValueListenableBuilder<int>(
              valueListenable: CloudSyncCoordinator().standalonePendingCount,
              builder: (context, standalonePending, _) {
                final pending = sync.pendingCount + standalonePending;
                final status = sync.status;

                if (!showHealthy &&
                    pending == 0 &&
                    status != SyncStatusEnum.error) {
                  return const SizedBox.shrink();
                }

                return FxGestureDetector(
                  onTap: () => _showDetail(context, sync, pending),
                  child: _statusPill(
                    context,
                    icon:
                        status == SyncStatusEnum.error
                            ? Icons.cloud_off
                            : Icons.cloud_queue,
                    text: pending > 0 ? '$pending 待同步' : _getStatusText(status),
                    color: _getColor(status, context),
                    loading: status == SyncStatusEnum.syncing,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _statusPill(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
    bool loading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: 12,
              height: 12,
              child: FxCircularProgress(strokeWidth: 1.5, color: color),
            )
          else
            Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Color _getColor(SyncStatusEnum status, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case SyncStatusEnum.idle:
        return scheme.onSurfaceVariant;
      case SyncStatusEnum.syncing:
        return scheme.primary;
      case SyncStatusEnum.error:
        return scheme.error;
    }
  }

  String _getStatusText(SyncStatusEnum status) {
    switch (status) {
      case SyncStatusEnum.idle:
        return '同步待机';
      case SyncStatusEnum.syncing:
        return '同步中';
      case SyncStatusEnum.error:
        return '同步失败';
    }
  }

  void _showDetail(BuildContext context, SyncService sync, int pending) {
    FxSheet.show(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '同步状态',
                    style: SlowlightTypography.cardTitle(
                      ctx,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _infoRow(ctx, '状态', _getStatusText(sync.status)),
                  _infoRow(ctx, '待同步', '$pending 项'),
                  if (sync.lastError != null)
                    _infoRow(
                      ctx,
                      '错误',
                      sync.lastError!.substring(
                        0,
                        sync.lastError!.length.clamp(0, 80),
                      ),
                    ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: sync.getConflicts('tasks'),
                    builder: (ctx, snap) {
                      final conflicts = snap.data ?? [];
                      if (conflicts.isEmpty) return const SizedBox.shrink();
                      return Column(
                        children: [
                          _infoRow(ctx, '冲突', '${conflicts.length} 项'),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FxButton(
                              label: '解决 ${conflicts.length} 个冲突',
                              icon: Icons.warning_amber,
                              variant: FxButtonVariant.outline,
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ConflictScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FxButton(
                      label: '立即同步',
                      icon: Icons.sync,
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await CloudSyncCoordinator().syncNow();
                        if (context.mounted) {
                          FxNotice.showContent(context, Text('手动同步已触发'));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: SlowlightTypography.caption(context)),
          ),
        ],
      ),
    );
  }
}
