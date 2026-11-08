import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/sync_service.dart';
import 'package:slowlight/ui/sync_status_text.dart';

void main() {
  String label({
    SyncStatusEnum status = SyncStatusEnum.idle,
    bool syncing = false,
    bool unknown = false,
    int conflicts = 0,
    int pending = 0,
    SyncQueueRunEvidence? queueRun,
    bool networkUnreachable = false,
    bool standalonePendingUnknown = false,
  }) =>
      cloudSyncSummary(
        status: status,
        isSyncing: syncing,
        conflictCheckFailed: unknown,
        conflictCount: conflicts,
        pendingCount: pending,
        lastQueueRun: queueRun,
        networkUnreachable: networkUnreachable,
        standalonePendingUnknown: standalonePendingUnknown,
      );

  test('云同步冲突显示全实体合计数量', () {
    expect(label(conflicts: 6), '云同步 · 6 个冲突待处理');
  });

  test('冲突查询失败不能显示为同步正常', () {
    expect(label(unknown: true), '云同步 · 冲突状态待确认');
  });

  test('队列失败不因 pending 清零而显示成功', () {
    expect(
      label(status: SyncStatusEnum.error),
      '云同步 · 同步失败',
    );
    expect(
      label(status: SyncStatusEnum.error, unknown: true),
      '云同步 · 同步失败',
    );
  });

  test('待同步与正在同步状态有明确反馈', () {
    expect(label(pending: 3), '云同步 · 3 项待同步');
    expect(label(syncing: true), '云同步 · 同步中…');
    expect(label(status: SyncStatusEnum.syncing), '云同步 · 同步中…');
  });

  test('独立意图计数读取失败不伪报无待处理项或同步完成', () {
    expect(
      label(standalonePendingUnknown: true),
      '云同步 · 待同步数量待确认',
    );
    expect(
      label(standalonePendingUnknown: true, pending: 2),
      '云同步 · 待同步数量待确认',
    );
    expect(
      cloudSyncFullySettled(
        requestSucceeded: true,
        status: SyncStatusEnum.idle,
        conflictCheckFailed: false,
        conflictCount: 0,
        pendingCount: 0,
        standalonePendingUnknown: true,
      ),
      isFalse,
    );
    expect(label(unknown: true, standalonePendingUnknown: true),
        '云同步 · 冲突状态待确认');
  });

  test('P1-11 仅确证部分写入才显示部分成功，不把未知项算成功', () {
    const partial = SyncQueueRunEvidence(attempted: 5, failed: 2);
    expect(partial.processed, 3);
    expect(partial.partiallyProcessed, isTrue);
    expect(label(
      status: SyncStatusEnum.error,
      queueRun: partial,
    ), '云同步 · 部分成功（3 项已处理，2 项未完成）');

    const allFailed = SyncQueueRunEvidence(attempted: 3, failed: 3);
    expect(allFailed.partiallyProcessed, isFalse);
    expect(label(
      status: SyncStatusEnum.error,
      queueRun: allFailed,
    ), '云同步 · 同步失败');
    expect(label(
      status: SyncStatusEnum.error,
      queueRun: const SyncQueueRunEvidence(attempted: 0, failed: 0),
    ), '云同步 · 同步失败');
  });

  test('P1-11 连接异常只表示可能离线，不误判 HTTP 失败', () {
    expect(label(
      status: SyncStatusEnum.error,
      networkUnreachable: true,
    ), '云同步 · 网络不可达（可能离线）');
    expect(label(status: SyncStatusEnum.error), '云同步 · 同步失败');
    expect(label(
      status: SyncStatusEnum.error,
      networkUnreachable: true,
      queueRun: const SyncQueueRunEvidence(attempted: 3, failed: 1),
    ), contains('部分成功'));
    expect(label(
      status: SyncStatusEnum.error,
      conflicts: 1,
      networkUnreachable: true,
    ), '云同步 · 1 个冲突待处理');
  });

  test('冲突优先于普通同步错误展示，避免用户找不到处置入口', () {
    expect(
      label(status: SyncStatusEnum.error, conflicts: 2),
      '云同步 · 2 个冲突待处理',
    );
  });
  test('即使协调器返回 true，剩余队列或冲突状态未知也不得报同步完成', () {
    bool settled({
      int queue = 0,
      int intents = 0,
      bool conflictsKnown = true,
      int conflicts = 0,
      SyncStatusEnum status = SyncStatusEnum.idle,
    }) => cloudSyncFullySettled(
      requestSucceeded: true,
      status: status,
      conflictCheckFailed: !conflictsKnown,
      conflictCount: conflicts,
      pendingCount: queue + intents,
    );

    expect(settled(), isTrue);
    expect(settled(queue: 1), isFalse);
    expect(settled(intents: 1), isFalse);
    expect(settled(conflictsKnown: false), isFalse);
    expect(settled(conflicts: 1), isFalse);
    expect(settled(status: SyncStatusEnum.error), isFalse);
    expect(settled(status: SyncStatusEnum.syncing), isFalse);
  });

  test('只有成功、静止、待处理项与冲突均归零才是同步完成', () {
    bool settled({
      bool success = true,
      SyncStatusEnum status = SyncStatusEnum.idle,
      bool unknown = false,
      int conflicts = 0,
      int pending = 0,
    }) => cloudSyncFullySettled(
      requestSucceeded: success,
      status: status,
      conflictCheckFailed: unknown,
      conflictCount: conflicts,
      pendingCount: pending,
    );
    expect(settled(), isTrue);
    expect(settled(success: false), isFalse);
    expect(settled(status: SyncStatusEnum.syncing), isFalse);
    expect(settled(status: SyncStatusEnum.error), isFalse);
    expect(settled(unknown: true), isFalse);
    expect(settled(conflicts: 1), isFalse);
    expect(settled(pending: 3), isFalse);
  });

}
