import '../services/sync_service.dart';

/// 用于数据同步设置页的状态说明。未知/失败状态不能被表述为成功。
String cloudSyncSummary({
  required SyncStatusEnum status,
  required bool isSyncing,
  required bool conflictCheckFailed,
  required int conflictCount,
  required int pendingCount,
}) {
  if (isSyncing || status == SyncStatusEnum.syncing) {
    return '云同步 · 同步中…';
  }
  if (!conflictCheckFailed && conflictCount > 0) {
    return '云同步 · $conflictCount 个冲突待处理';
  }
  if (status == SyncStatusEnum.error) return '云同步 · 同步失败';
  if (conflictCheckFailed) return '云同步 · 冲突状态待确认';
  if (pendingCount > 0) return '云同步 · $pendingCount 项待同步';
  return '云同步 · 当前无待处理项';
}

/// 手动同步只在请求成功、状态静止且待处理项均已确认清零时显示成功。
/// 同步协调器可能仅完成了一轮请求，不能把“请求已执行”当作全部完成。
bool cloudSyncFullySettled({
  required bool requestSucceeded,
  required SyncStatusEnum status,
  required bool conflictCheckFailed,
  required int conflictCount,
  required int pendingCount,
}) =>
    requestSucceeded &&
    status == SyncStatusEnum.idle &&
    !conflictCheckFailed &&
    conflictCount == 0 &&
    pendingCount == 0;
