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
  }) =>
      cloudSyncSummary(
        status: status,
        isSyncing: syncing,
        conflictCheckFailed: unknown,
        conflictCount: conflicts,
        pendingCount: pending,
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
  });

  test('待同步与正在同步状态有明确反馈', () {
    expect(label(pending: 3), '云同步 · 3 项待同步');
    expect(label(syncing: true), '云同步 · 同步中…');
    expect(label(status: SyncStatusEnum.syncing), '云同步 · 同步中…');
  });

  test('冲突优先于普通同步错误展示，避免用户找不到处置入口', () {
    expect(
      label(status: SyncStatusEnum.error, conflicts: 2),
      '云同步 · 2 个冲突待处理',
    );
  });
}
