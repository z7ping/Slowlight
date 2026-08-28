import 'package:sqflite/sqflite.dart';

import '../db/cloud_cache_db.dart';
import '../models/task.dart';
import '../repositories/cloud_cache_repository.dart';
import 'sync_service.dart';

/// 将 Cloud 模式下离线的 Task complete/uncomplete 保存为“目标状态”。
///
/// 普通 Task 字段仍通过 sync_queue push；completion 意图由
/// CloudSyncCoordinator 在普通 push 成功后调用服务端 /complete 对齐。
class CloudTaskCompletionCache {
  final CloudCacheDb _cache = CloudCacheDb();

  Future<Task> toggle(int publicTaskId) async {
    final db = await _cache.database;
    final row = await _findTask(db, publicTaskId);
    final localId = row['id'] as int;
    final serverId = row['server_id'] as int?;
    final desired = (row['is_completed'] as int? ?? 0) != 1;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'tasks',
        {
          'is_completed': desired ? 1 : 0,
          'completed_at': desired ? now : null,
          'updated_at': now,
          'last_modified': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [localId],
      );
      await txn.insert(
        'sync_intents',
        {
          'entity_type': 'tasks',
          'entity_local_id': localId,
          'intent': 'completion',
          'value': desired ? '1' : '0',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    final queued = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM sync_queue '
      'WHERE entity_type = ? AND entity_local_id = ?',
      ['tasks', localId],
    );
    if ((queued.first['cnt'] as int? ?? 0) == 0 && serverId != null) {
      // completion-only 修改也需要一个普通 update 屏障：Coordinator 会等待它
      // 先成功，再执行具有副作用的 /complete。
      await SyncService().enqueue(
        entityType: 'tasks',
        entityLocalId: localId,
        entityServerId: serverId,
        operation: 'update',
      );
    }

    final tasks = await CloudCacheRepository().getAllTasks();
    return tasks.firstWhere((task) => task.id == publicTaskId);
  }

  Future<Map<String, Object?>> _findTask(Database db, int publicTaskId) async {
    final rows = publicTaskId < 0
        ? await db.query(
            'tasks',
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [-publicTaskId],
            limit: 1,
          )
        : await db.query(
            'tasks',
            where: 'server_id = ? AND deleted_at IS NULL',
            whereArgs: [publicTaskId],
            limit: 1,
          );
    if (rows.isEmpty) {
      throw StateError('Cloud cache task not found: $publicTaskId');
    }
    return rows.first;
  }
}
