import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: sync.getAllConflicts(),
                  builder: (context, snapshot) {
                    final conflicts = snapshot.data ?? const [];
                    if (!showHealthy &&
                        pending == 0 &&
                        conflicts.isEmpty &&
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
                    text: status == SyncStatusEnum.error
                        ? '同步失败'
                        : conflicts.isNotEmpty
                            ? '${conflicts.length} 个冲突'
                            : pending > 0
                                ? '$pending 待同步'
                                : _getStatusText(status),
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
    final notice = FxNotice.capture(context);
    Widget content(BuildContext ctx) => _SyncStatusDetails(
      sync: sync,
      notice: notice,
      onConflicts: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ConflictScreen(),
        ));
      },
    );

    if (SlowlightPlatformDensity.usesMobileTouchTargets) {
      FxSheet.show(
        context: context,
        useSafeArea: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        builder: content,
      );
    } else {
      FxDialog.show(context: context, width: 480, child: content(context));
    }
  }
}

/// 跨平台共享内容，承载方式由既有 FxDialog / FxSheet 负责。
class _SyncStatusDetails extends StatefulWidget {
  const _SyncStatusDetails({
    required this.sync,
    required this.notice,
    required this.onConflicts,
  });

  final SyncService sync;
  final FxNoticeHandle notice;
  final VoidCallback onConflicts;

  @override
  State<_SyncStatusDetails> createState() => _SyncStatusDetailsState();
}

class _SyncStatusDetailsState extends State<_SyncStatusDetails> {
  late Future<List<Map<String, dynamic>>> _conflicts;
  bool _expanded = false;
  bool _retrying = false;
  String? _feedback;
  String? _requestError;

  @override
  void initState() {
    super.initState();
    _conflicts = widget.sync.getAllConflicts();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _requestError = null;
      _feedback = null;
    });
    try {
      final completed = await CloudSyncCoordinator().syncNow();
      final conflicts = await widget.sync.getAllConflicts();
      if (!mounted) return;
      final pending = widget.sync.pendingCount +
          CloudSyncCoordinator().standalonePendingCount.value;
      if (completed &&
          widget.sync.status == SyncStatusEnum.idle &&
          conflicts.isEmpty &&
          pending == 0) {
        Navigator.of(context).pop();
        widget.notice.show('同步已完成', variant: FxNoticeVariant.success);
        return;
      }
      setState(() {
        _conflicts = Future.value(conflicts);
        _feedback = widget.sync.status == SyncStatusEnum.error
            ? '本次同步仍未完成，请查看错误或冲突。'
            : '同步请求已执行，仍有待处理项或结果尚未确认。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _requestError = error.toString();
        _feedback = '同步请求未完成，请查看技术详情。';
      });
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) => ValueListenableBuilder<int>(
        valueListenable: CloudSyncCoordinator().standalonePendingCount,
        builder: (context, standalone, _) => FutureBuilder<List<Map<String, dynamic>>>(
          future: _conflicts,
          builder: (context, snapshot) {
            final scheme = Theme.of(context).colorScheme;
            final status = widget.sync.status;
            final pending = widget.sync.pendingCount + standalone;
            final count = snapshot.data?.length ?? 0;
            final conflictsKnown =
                snapshot.connectionState == ConnectionState.done &&
                    !snapshot.hasError;
            final raw = _requestError ?? widget.sync.lastError;
            final hasRaw = raw != null && raw.trim().isNotEmpty;
            final failed = _requestError != null || status == SyncStatusEnum.error;
            final busy = _retrying || status == SyncStatusEnum.syncing;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.78,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SlowlightSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(SlowlightSpacing.xl),
                          decoration: BoxDecoration(
                            color: (failed ? scheme.error : scheme.primary)
                                .withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(SlowlightRadius.lg),
                          ),
                          child: Icon(
                            failed ? Icons.error_outline
                                : busy ? Icons.sync : Icons.cloud_outlined,
                            size: SlowlightIconSize.xl,
                            color: failed ? scheme.error : scheme.primary,
                          ),
                        ),
                        const SizedBox(width: SlowlightSpacing.xl),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                busy ? '正在同步' :
                                    failed ? '同步未完成' : '同步状态',
                                style: SlowlightTypography.sectionTitle(context),
                              ),
                              const SizedBox(height: SlowlightSpacing.xs),
                              Text(
                                busy ? '正在处理云端与本地数据…'
                                    : failed ? '同步过程中遇到异常，请检查后重试。'
                                        : '查看当前云端数据同步情况。',
                                style: SlowlightTypography.secondary(context)
                                    .copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        FxIconButton(
                          icon: Icons.close,
                          tooltip: '关闭同步状态',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: SlowlightSpacing.xxxl),
                    Container(
                      padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(SlowlightRadius.lg),
                      ),
                      child: Column(
                        children: [
                          _row(context, '同步结果',
                              busy ? '同步中' : failed ? '失败' : '待机',
                              color: failed ? scheme.error : null),
                          const SizedBox(height: SlowlightSpacing.xl),
                          _row(context, '待同步数据', '$pending 项'),
                          if (!conflictsKnown || count > 0) ...[
                            const SizedBox(height: SlowlightSpacing.xl),
                            _row(context, '同步冲突',
                                !conflictsKnown
                                    ? snapshot.hasError ? '状态待确认' : '核对中…'
                                    : '$count 项'),
                          ],
                        ],
                      ),
                    ),
                    if (failed || hasRaw) ...[
                      const SizedBox(height: SlowlightSpacing.xxxl),
                      Row(
                        children: [
                          Icon(Icons.storage_outlined,
                              size: SlowlightIconSize.sm,
                              color: scheme.onSurfaceVariant),
                          const SizedBox(width: SlowlightSpacing.md),
                          Expanded(
                            child: Text(
                              syncErrorTitle(raw),
                              style: SlowlightTypography.cardTitle(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SlowlightSpacing.md),
                      Text(
                        syncErrorDescription(raw),
                        style: SlowlightTypography.secondary(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (hasRaw) ...[
                        const SizedBox(height: SlowlightSpacing.md),
                        FxActionBar(
                          stackBelow: 280,
                          leading: FxButton(
                            label: _expanded ? '收起技术详情' : '查看技术详情',
                            icon: _expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: FxButtonSize.sm,
                            variant: FxButtonVariant.ghost,
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                          ),
                          actions: [
                            FxButton(
                              label: '复制错误',
                              icon: Icons.copy_outlined,
                              size: FxButtonSize.sm,
                              variant: FxButtonVariant.ghost,
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: raw!),
                                );
                                widget.notice.show('错误详情已复制');
                              },
                            ),
                          ],
                        ),
                        if (_expanded) ...[
                          const SizedBox(height: SlowlightSpacing.md),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(SlowlightSpacing.xl),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius.circular(SlowlightRadius.md),
                            ),
                            child: SelectionArea(
                              child: Text(
                                raw!,
                                softWrap: true,
                                style: SlowlightTypography.caption(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                    if (_feedback != null) ...[
                      const SizedBox(height: SlowlightSpacing.xl),
                      Text(
                        _feedback!,
                        style: SlowlightTypography.secondary(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    if (conflictsKnown && count > 0) ...[
                      const SizedBox(height: SlowlightSpacing.xl),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FxButton(
                          label: '解决 $count 个冲突',
                          icon: Icons.warning_amber_outlined,
                          variant: FxButtonVariant.outline,
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onConflicts();
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: SlowlightSpacing.xxxl),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final dismiss = FxButton(
                          label: '稍后处理',
                          expanded: true,
                          variant: FxButtonVariant.outline,
                          onPressed: () => Navigator.of(context).pop(),
                        );
                        final retry = FxButton(
                          label: busy ? '同步中…' : '重新同步',
                          expanded: true,
                          icon: busy ? Icons.hourglass_top : Icons.sync,
                          onPressed: busy ? null : _retry,
                        );
                        if (constraints.maxWidth < 360 ||
                            MediaQuery.textScalerOf(context).scale(1) >= 1.6) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              retry,
                              const SizedBox(height: SlowlightSpacing.md),
                              dismiss,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: dismiss),
                            const SizedBox(width: SlowlightSpacing.md),
                            Expanded(flex: 2, child: retry),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {Color? color}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: SlowlightTypography.secondary(context).copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: SlowlightTypography.secondary(context)
              .copyWith(fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

/// 对原始错误仅做有依据的归类；失败信息不臆造成功状态或根因。
String syncErrorTitle(String? error) =>
    error?.toLowerCase().contains('sqlite') == true
        ? '本地数据库异常'
        : '同步处理异常';

String syncErrorDescription(String? error) {
  if (error == null || error.trim().isEmpty) {
    return '失败原因待确认，请稍后重试。';
  }
  final code = RegExp(r'sqlite_error:\s*(\d+)', caseSensitive: false)
      .firstMatch(error);
  if (code != null) {
    return 'SQLite 返回错误代码 ' +
        code.group(1)! +
        '，请展开技术详情查看原始异常。';
  }
  return '本次同步未完成，可展开技术详情查看原始异常。';
}
