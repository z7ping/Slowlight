import '../services/sync_service.dart';

/// One evidence-first view policy for the settings summary, badge and detail.
/// A transport SocketException is NOT proof that the whole device is offline.
enum CloudSyncViewState {
  syncing,
  conflict,
  partial,
  networkUnreachable,
  failed,
  unknown,
  pending,
  idle,
}

CloudSyncViewState cloudSyncViewState({
  required SyncStatusEnum status,
  required bool isSyncing,
  required bool conflictCheckFailed,
  required int conflictCount,
  required int pendingCount,
  SyncQueueRunEvidence? lastQueueRun,
  bool networkUnreachable = false,
  bool standalonePendingUnknown = false,
}) {
  if (isSyncing || status == SyncStatusEnum.syncing) {
    return CloudSyncViewState.syncing;
  }
  if (!conflictCheckFailed && conflictCount > 0) {
    return CloudSyncViewState.conflict;
  }
  if (status == SyncStatusEnum.error) {
    if (lastQueueRun?.partiallyProcessed == true) {
      return CloudSyncViewState.partial;
    }
    if (networkUnreachable) return CloudSyncViewState.networkUnreachable;
    return CloudSyncViewState.failed;
  }
  if (conflictCheckFailed || standalonePendingUnknown) {
    return CloudSyncViewState.unknown;
  }
  if (pendingCount > 0) return CloudSyncViewState.pending;
  return CloudSyncViewState.idle;
}

/// 用于数据同步设置页的状态说明。只把普通队列本轮确证的回执称作部分成功。
String cloudSyncSummary({
  required SyncStatusEnum status,
  required bool isSyncing,
  required bool conflictCheckFailed,
  required int conflictCount,
  required int pendingCount,
  SyncQueueRunEvidence? lastQueueRun,
  bool networkUnreachable = false,
  bool standalonePendingUnknown = false,
}) {
  final phase = cloudSyncViewState(
    status: status,
    isSyncing: isSyncing,
    conflictCheckFailed: conflictCheckFailed,
    conflictCount: conflictCount,
    pendingCount: pendingCount,
    lastQueueRun: lastQueueRun,
    networkUnreachable: networkUnreachable,
    standalonePendingUnknown: standalonePendingUnknown,
  );
  return switch (phase) {
    CloudSyncViewState.syncing => '云同步 · 同步中…',
    CloudSyncViewState.conflict => '云同步 · $conflictCount 个冲突待处理',
    CloudSyncViewState.partial =>
      '云同步 · 部分成功（${lastQueueRun!.processed} 项已处理，'
          '${lastQueueRun!.failed} 项未完成）',
    CloudSyncViewState.networkUnreachable =>
      '云同步 · 网络不可达（可能离线）',
    CloudSyncViewState.failed => '云同步 · 同步失败',
    CloudSyncViewState.unknown => conflictCheckFailed
        ? '云同步 · 冲突状态待确认'
        : '云同步 · 待同步数量待确认',
    CloudSyncViewState.pending => '云同步 · $pendingCount 项待同步',
    CloudSyncViewState.idle => '云同步 · 当前无待处理项',
  };
}

/// 手动同步只在请求成功、状态静止且待处理项均已确认清零时显示成功。
/// 同步协调器可能仅完成了一轮请求，不能把“请求已执行”当作全部完成。
bool cloudSyncFullySettled({
  required bool requestSucceeded,
  required SyncStatusEnum status,
  required bool conflictCheckFailed,
  required int conflictCount,
  required int pendingCount,
  bool standalonePendingUnknown = false,
}) =>
    requestSucceeded &&
    status == SyncStatusEnum.idle &&
    !conflictCheckFailed &&
    conflictCount == 0 &&
    !standalonePendingUnknown &&
    pendingCount == 0;
