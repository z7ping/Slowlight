import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/sync_service.dart';
import 'package:slowlight/widgets/sync_status_badge.dart';

void main() {
  test('X09 真实冲突读取失败显示徽章，健康加载中不闪烁', () {
    expect(shouldShowCloudSyncBadge(
      showHealthy: false,
      conflictReadFailed: true,
      pendingCount: 0,
      conflictCount: 0,
      status: SyncStatusEnum.idle,
    ), isTrue);
    expect(shouldShowCloudSyncBadge(
      showHealthy: false,
      conflictReadFailed: false,
      pendingCount: 0,
      conflictCount: 0,
      status: SyncStatusEnum.idle,
    ), isFalse);
    expect(shouldShowCloudSyncBadge(
      showHealthy: false,
      conflictReadFailed: false,
      pendingCount: 0,
      conflictCount: 0,
      standalonePendingUnknown: true,
      status: SyncStatusEnum.idle,
    ), isTrue);
    expect(shouldShowCloudSyncBadge(
      showHealthy: false,
      conflictReadFailed: false,
      pendingCount: 0,
      conflictCount: 2,
      status: SyncStatusEnum.idle,
    ), isTrue);
    expect(shouldShowCloudSyncBadge(
      showHealthy: false,
      conflictReadFailed: false,
      pendingCount: 0,
      conflictCount: 0,
      status: SyncStatusEnum.syncing,
    ), isTrue);
  });


  test('X09 未确认或冲突状态只允许核对，不会触发普通同步', () {
    bool safe(SyncStatusEnum status, {
      bool known = true,
      int conflicts = 0,
      bool requestError = false,
    }) => syncMayStartUserRetry(
      status: status,
      conflictsKnown: known,
      conflictCount: conflicts,
      hasRequestError: requestError,
    );
    expect(safe(SyncStatusEnum.idle), isTrue);
    expect(safe(SyncStatusEnum.syncing), isFalse);
    expect(safe(SyncStatusEnum.error), isFalse);
    expect(safe(SyncStatusEnum.idle, known: false), isFalse);
    expect(safe(SyncStatusEnum.idle, conflicts: 1), isFalse);
    expect(safe(SyncStatusEnum.idle, requestError: true), isFalse);
  });


  test('同步失败队列未能读取或有未核对记录时不允许重发', () {
    bool safe({
      SyncStatusEnum status = SyncStatusEnum.idle,
      bool failuresKnown = true,
      bool standaloneKnown = true,
      int failures = 0,
      bool verified = false,
      bool requestError = false,
    }) => syncMayStartUserRetry(
      status: status,
      conflictsKnown: true,
      conflictCount: 0,
      hasRequestError: requestError,
      failuresKnown: failuresKnown,
      standalonePendingKnown: standaloneKnown,
      pendingFailureCount: failures,
      verifiedAfterFailure: verified,
    );

    expect(safe(failuresKnown: false), isFalse);
    expect(safe(standaloneKnown: false), isFalse);
    expect(safe(standaloneKnown: false, verified: true), isFalse);
    expect(safe(failures: 1), isFalse);
    expect(safe(status: SyncStatusEnum.error), isFalse);
    expect(safe(status: SyncStatusEnum.error, verified: true), isTrue);
    expect(safe(
      status: SyncStatusEnum.error,
      verified: true,
      failures: 1,
    ), isFalse);
    expect(safe(
      status: SyncStatusEnum.error,
      verified: true,
      requestError: true,
    ), isTrue);
    expect(safe(
      status: SyncStatusEnum.syncing,
      verified: true,
    ), isFalse);
  });

  test('同步状态同时区分待同步、冲突、未知和已知无待处理', () {
    String label({
      bool busy = false,
      bool failed = false,
      bool known = true,
      int conflicts = 0,
      int pending = 0,
      SyncQueueRunEvidence? evidence,
      bool networkUnreachable = false,
      bool standalonePendingUnknown = false,
    }) => syncDetailResultLabel(
      busy: busy,
      failed: failed,
      conflictsKnown: known,
      conflictCount: conflicts,
      pendingCount: pending,
      lastQueueRun: evidence,
      networkUnreachable: networkUnreachable,
      standalonePendingUnknown: standalonePendingUnknown,
    );
    expect(label(busy: true), '同步中');
    expect(label(failed: true), '同步未完成');
    expect(label(known: false), '状态待确认');
    expect(label(conflicts: 2, pending: 3), '冲突待处理');
    expect(label(pending: 1), '待同步');
    expect(label(), '无待处理项');
    expect(label(standalonePendingUnknown: true), '状态待确认');
    expect(label(
      failed: true,
      evidence: const SyncQueueRunEvidence(attempted: 4, failed: 1),
    ), '部分成功（已处理 3 项，未完成 1 项）');
    expect(label(
      failed: true,
      networkUnreachable: true,
    ), '网络不可达（可能离线）');
    expect(label(
      failed: true,
      evidence: const SyncQueueRunEvidence(attempted: 4, failed: 4),
    ), '同步未完成');
  });

  test('SQLite 错误按真实错误代码描述，不把泛用代码冒充确定根因', () {
    const raw =
        'SqliteFfiException(sqlite_error: 1, SqliteException(1): while preparing statement)';
    expect(syncErrorTitle(raw), '本地数据库异常');
    expect(syncErrorDescription(raw), contains('SQLite 返回错误代码 1'));
    expect(syncErrorDescription(raw), isNot(contains('损坏')));
  });

  test('没有具体异常时标记原因待确认，不虚构可复制的错误', () {
    expect(syncErrorTitle(null), '同步处理异常');
    expect(syncErrorDescription(null), contains('原因待确认'));
    expect(syncErrorDescription('  '), contains('原因待确认'));
  });

  test('非 SQLite 失败使用中性描述，保留原始诊断文本展示入口', () {
    const raw = 'SocketException: connection failed';
    expect(syncErrorTitle(raw), '同步处理异常');
    expect(syncErrorDescription(raw), contains('展开技术详情'));
    expect(syncErrorDescription(raw), isNot(contains('SQLite')));
  });

  test('SQLite 未提供错误码时不编造代码', () {
    const raw = 'SqliteException: failed opening cache';
    expect(syncErrorTitle(raw), '本地数据库异常');
    expect(syncErrorDescription(raw), isNot(contains('代码')));
  });
}
