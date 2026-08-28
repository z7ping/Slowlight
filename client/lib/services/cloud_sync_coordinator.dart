import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/cloud_cache_db.dart';
import '../repositories/cloud_reflection_cache_repository.dart';
import 'api/reflection_api.dart';
import 'api/task_api.dart';
import 'auth_service.dart';
import 'data_mode_manager.dart';
import 'sync_service.dart';

/// Cloud Cache 的同步编排层。
///
/// SyncService 继续负责普通实体 CRUD push/pull；这里处理不能安全退化成普通 update
/// 的业务语义：Task completion 以及追加型 Reflection/Observation 离线提交。
class CloudSyncCoordinator {
  static final CloudSyncCoordinator _instance = CloudSyncCoordinator._();
  factory CloudSyncCoordinator() => _instance;
  CloudSyncCoordinator._();

  final CloudCacheDb _cache = CloudCacheDb();
  final CloudReflectionCacheRepository _reflectionCache =
      CloudReflectionCacheRepository();

  /// 没有普通 sync_queue 屏障的独立 intent 数量。
  ///
  /// 目前主要是 Reflection create。Task completion 通常已有同实体 queue，
  /// 因此不会在 UI 中重复计算两次。
  final ValueNotifier<int> standalonePendingCount = ValueNotifier<int>(0);

  Timer? _timer;
  bool _running = false;
  bool _rerunRequested = false;
  int _generation = 0;

  Future<void> start() async {
    if (!DataModeManager().isCloud) return;
    _generation++;
    await SyncService().init(startPeriodic: false);
    await refreshStandalonePendingCount();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(syncNow());
    });
  }

  Future<void> refreshStandalonePendingCount() async {
    if (!DataModeManager().isCloud) {
      standalonePendingCount.value = 0;
      return;
    }
    try {
      final db = await _cache.database;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) AS cnt
        FROM sync_intents i
        WHERE NOT EXISTS (
          SELECT 1 FROM sync_queue q
          WHERE q.entity_type = i.entity_type
            AND q.entity_local_id = i.entity_local_id
        )
      ''');
      standalonePendingCount.value = rows.first['cnt'] as int? ?? 0;
    } catch (_) {
      // 未认证 / 账号切换中的短窗口不保留上一账号的 pending UI 状态。
      standalonePendingCount.value = 0;
    }
  }

  /// 同一时间只允许一轮同步执行。
  ///
  /// 如果同步期间又有写入请求触发 syncNow，不丢弃该请求，而是在当前轮结束后
  /// 串行再跑一轮。这样既避免并发 push/pull，也避免新写入被迫等下一个 5 分钟周期。
  Future<bool> syncNow() async {
    if (!DataModeManager().isCloud) return false;
    if (_running) {
      _rerunRequested = true;
      return true;
    }

    _running = true;
    var result = false;
    try {
      do {
        _rerunRequested = false;
        result = await _runOnce() || result;
      } while (_rerunRequested && DataModeManager().isCloud);
      return result;
    } finally {
      _running = false;
      await refreshStandalonePendingCount();
    }
  }

  Future<bool> _runOnce() async {
    await SyncService().init(startPeriodic: false);
    final db = await _cache.database;
    final accountId = _cache.currentAccountId;
    final generation = _generation;
    if (accountId == null ||
        !await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }

    final taskIntents = await db.query(
      'sync_intents',
      where: 'entity_type = ? AND intent = ?',
      whereArgs: ['tasks', 'completion'],
    );

    if (taskIntents.isNotEmpty) {
      // 先 push 普通 Task 字段/离线 create，确保 server_id 与普通字段已经落服务端。
      await SyncService().syncBatch(batchSize: 50);
      if (!await _isRunValid(accountId: accountId, generation: generation)) {
        return false;
      }
      for (final intent in taskIntents) {
        if (!await _isRunValid(accountId: accountId, generation: generation)) {
          return false;
        }
        await _applyTaskCompletionIntent(
          db: db,
          accountId: accountId,
          generation: generation,
          entityLocalId: intent['entity_local_id'] as int,
          desiredCompleted: intent['value'] == '1',
        );
      }

      // completion 意图未完成时不能 pull，否则远端旧状态会覆盖本地用户动作。
      final remaining = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM sync_intents "
        "WHERE entity_type = 'tasks' AND intent = 'completion'",
      );
      if ((remaining.first['cnt'] as int? ?? 0) > 0) return false;
    }

    await _syncReflectionIntents(
      db: db,
      accountId: accountId,
      generation: generation,
    );
    if (!await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }

    return SyncService().manualSync();
  }

  Future<void> _applyTaskCompletionIntent({
    required Database db,
    required int accountId,
    required int generation,
    required int entityLocalId,
    required bool desiredCompleted,
  }) async {
    // 普通字段/create 尚未 push 成功时，保留意图等待下次同步。
    final queued = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM sync_queue '
      'WHERE entity_type = ? AND entity_local_id = ?',
      ['tasks', entityLocalId],
    );
    if ((queued.first['cnt'] as int? ?? 0) > 0) return;

    final rows = await db.query(
      'tasks',
      columns: ['server_id'],
      where: 'id = ?',
      whereArgs: [entityLocalId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _deleteTaskIntent(db, entityLocalId);
      return;
    }
    final serverId = rows.first['server_id'] as int?;
    if (serverId == null || serverId <= 0) return;
    if (!await _isRunValid(accountId: accountId, generation: generation)) return;

    try {
      final remote = await TaskApi.getTask(serverId);
      if (!await _isRunValid(accountId: accountId, generation: generation)) return;
      if (remote.isCompleted != desiredCompleted) {
        await TaskApi.completeTask(serverId);
      }
      if (!await _isRunValid(accountId: accountId, generation: generation)) return;
      await _deleteTaskIntent(db, entityLocalId);
    } catch (_) {
      if (!await _isRunValid(accountId: accountId, generation: generation)) return;
      // 意图失败时补回普通 update 屏障：既让 pendingCount 对用户可见，
      // 也保证下一轮仍先经过 push 阶段，再重试具有副作用的 /complete。
      await _ensureTaskBarrier(entityLocalId, serverId);
    }
  }

  Future<void> _syncReflectionIntents({
    required Database db,
    required int accountId,
    required int generation,
  }) async {
    final intents = await db.query(
      'sync_intents',
      where: 'entity_type = ? AND intent = ?',
      whereArgs: ['reflections', 'create'],
      orderBy: 'created_at ASC',
    );
    for (final intent in intents) {
      if (!await _isRunValid(accountId: accountId, generation: generation)) return;
      final localId = intent['entity_local_id'] as int;
      final rows = await db.query(
        'reflections',
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (rows.isEmpty) {
        await _deleteReflectionIntent(db, localId);
        continue;
      }
      final row = rows.first;
      final serverId = row['server_id'] as int?;
      if (serverId != null && serverId > 0) {
        await _deleteReflectionIntent(db, localId);
        continue;
      }

      Map<String, dynamic> context = const {};
      try {
        final decoded = jsonDecode(row['context_json']?.toString() ?? '{}');
        if (decoded is Map) context = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      try {
        final remote = await ReflectionApi.create(
          content: row['content'] as String? ?? '',
          entryType: row['entry_type'] as String? ?? 'reflection',
          questionId: row['question_id'] as String?,
          dimensionKey: row['dimension_key'] as String?,
          context: context,
        );
        if (!await _isRunValid(accountId: accountId, generation: generation)) return;
        await _reflectionCache.markCreateSynced(db, localId, remote);
      } catch (_) {
        // 追加型 Reflection 不阻断 Task/Habit 的普通 pull；保留 intent 等下一轮重试。
      }
    }
  }

  Future<void> _ensureTaskBarrier(int entityLocalId, int serverId) async {
    final db = await _cache.database;
    final queued = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM sync_queue '
      'WHERE entity_type = ? AND entity_local_id = ?',
      ['tasks', entityLocalId],
    );
    if ((queued.first['cnt'] as int? ?? 0) > 0) return;
    await SyncService().enqueue(
      entityType: 'tasks',
      entityLocalId: entityLocalId,
      entityServerId: serverId,
      operation: 'update',
    );
  }

  Future<void> _deleteTaskIntent(Database db, int entityLocalId) => db.delete(
        'sync_intents',
        where: 'entity_type = ? AND entity_local_id = ? AND intent = ?',
        whereArgs: ['tasks', entityLocalId, 'completion'],
      );

  Future<void> _deleteReflectionIntent(Database db, int entityLocalId) =>
      db.delete(
        'sync_intents',
        where: 'entity_type = ? AND entity_local_id = ? AND intent = ?',
        whereArgs: ['reflections', entityLocalId, 'create'],
      );

  Future<bool> _isRunValid({
    required int accountId,
    required int generation,
  }) async {
    if (!DataModeManager().isCloud || generation != _generation) return false;
    final user = await AuthService.getUser();
    return user != null && user.id == accountId;
  }

  void stop() {
    _generation++;
    _rerunRequested = false;
    _timer?.cancel();
    _timer = null;
    standalonePendingCount.value = 0;
  }
}
