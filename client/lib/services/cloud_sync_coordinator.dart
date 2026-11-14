import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/cloud_cache_db.dart';
import '../repositories/cloud_reflection_cache_repository.dart';
import 'api/reflection_api.dart';
import 'api/task_api.dart';
import 'auth_service.dart';
import 'data_mode_manager.dart';
import 'network_retry.dart';
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

  /// The count is unknown if Cloud Cache could not be read. Never display
  /// a fabricated zero or accept a sync-success receipt in that state.
  final ValueNotifier<bool> standalonePendingUnknown =
      ValueNotifier<bool>(false);

  // Cover the whole round, including the independent HTTP calls before
  // SyncService starts the ordinary queue and pull phases.
  final isSyncing = ValueNotifier<bool>(false);
  final lastIntentRun = ValueNotifier<SyncQueueRunEvidence?>(null);
  bool _intentNetworkUnreachable = false;
  SyncQueueRunEvidence? _preflightRun;
  bool get networkUnreachable =>
      _intentNetworkUnreachable || SyncService().lastNetworkUnreachable;

  SyncQueueRunEvidence? get lastRunEvidence {
    final parts = [
      if (_preflightRun case final preflight?) preflight,
      if (SyncService().lastQueueRun case final ordinary?) ordinary,
      if (lastIntentRun.value case final intents?) intents,
    ];
    if (parts.isEmpty) return null;
    return SyncQueueRunEvidence(
      attempted: parts.fold(0, (count, run) => count + run.attempted),
      failed: parts.fold(0, (count, run) => count + run.failed),
      unknown: parts.fold(0, (count, run) => count + run.unknown),
    );
  }

  SyncStatusEnum get status {
    if (isSyncing.value) return SyncStatusEnum.syncing;
    final ordinaryStatus = SyncService().status;
    final intents = lastIntentRun.value;
    if (intents != null && (intents.failed > 0 || intents.unknown > 0)) {
      return SyncStatusEnum.error;
    }
    return ordinaryStatus;
  }

  Timer? _timer;
  int _pendingReadVersion = 0;
  bool _rerunRequested = false;
  int? _activeAccountId;
  int _generation = 0;

  Future<void> start() async {
    if (!DataModeManager().isCloud) return;
    final generation = ++_generation;
    final user = await AuthService.getUser();
    final accountId = user?.id;
    if (accountId == null ||
        accountId <= 0 ||
        !await _isRunValid(accountId: accountId, generation: generation)) {
      return;
    }
    if (_activeAccountId != accountId) {
      _activeAccountId = accountId;
      _pendingReadVersion++;
      _intentNetworkUnreachable = false;
      _preflightRun = null;
      lastIntentRun.value = null;
      standalonePendingCount.value = 0;
      standalonePendingUnknown.value = true;
    }
    await SyncService().init(startPeriodic: false);
    if (!await _isRunValid(accountId: accountId, generation: generation))
      return;
    await refreshStandalonePendingCount();
    if (!await _isRunValid(accountId: accountId, generation: generation))
      return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(syncNow());
    });
  }

  Future<void> refreshStandalonePendingCount() async {
    final readVersion = ++_pendingReadVersion;
    if (!DataModeManager().isCloud) {
      standalonePendingCount.value = 0;
      standalonePendingUnknown.value = false;
      return;
    }
    try {
      final generation = _generation;
      final user = await AuthService.getUser();
      final accountId = user?.id;
      if (accountId == null || accountId <= 0) {
        throw StateError('Cloud cache requires an authenticated cloud user');
      }
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
      final valid = await _isRunValid(
        accountId: accountId,
        generation: generation,
      );
      if (readVersion != _pendingReadVersion) return;
      if (!valid) {
        throw StateError('Cloud account changed during queue count');
      }
      standalonePendingCount.value = rows.single['cnt'] as int;
      standalonePendingUnknown.value = false;
    } catch (_) {
      if (readVersion != _pendingReadVersion) return;
      // Never carry a previous account's pending count across a failed read.
      // Zero here is only a placeholder: the separate unknown flag prevents
      // every consumer from mistaking it for a confirmed empty queue.
      standalonePendingCount.value = 0;
      standalonePendingUnknown.value = true;
    }
  }

  /// 同一时间只允许一轮同步执行。
  ///
  /// 如果同步期间又有写入请求触发 syncNow，不丢弃该请求，而是在当前轮结束后
  /// 串行再跑一轮。这样既避免并发 push/pull，也避免新写入被迫等下一个 5 分钟周期。
  Future<bool> syncNow() async {
    if (!DataModeManager().isCloud) return false;
    if (isSyncing.value) {
      _rerunRequested = true;
      return false;
    }

    isSyncing.value = true;
    final generation = _generation;
    var result = false;
    try {
      do {
        _rerunRequested = false;
        lastIntentRun.value = null;
        _intentNetworkUnreachable = false;
        _preflightRun = null;
        result = await _runOnce(generation);
      } while (_rerunRequested &&
          generation == _generation &&
          DataModeManager().isCloud);
      await refreshStandalonePendingCount();
      return result &&
          generation == _generation &&
          !standalonePendingUnknown.value &&
          standalonePendingCount.value == 0 &&
          SyncService().pendingCount == 0;
    } finally {
      isSyncing.value = false;
      // An account can become active while its predecessor unwinds.
      if (_rerunRequested && DataModeManager().isCloud) {
        unawaited(syncNow());
      }
    }
  }

  /// Check sent completion intents without issuing any mutation to the API.
  Future<SyncReconciliationReport> reconcileSentCompletions() async {
    if (!DataModeManager().isCloud || isSyncing.value) {
      throw StateError('同步正在执行，请完成后再核对');
    }
    isSyncing.value = true;
    final generation = _generation;
    var verified = 0;
    var unknown = 0;
    try {
      final accountId = (await AuthService.getUser())?.id;
      if (accountId == null ||
          !await _isRunValid(accountId: accountId, generation: generation)) {
        throw StateError('云端账号不可用，请重新核对');
      }
      final db = await _cache.database;
      final intents = await db.query(
        'sync_intents',
        where: "entity_type = 'tasks' AND intent = 'completion' "
            "AND value IN ('0:sent', '1:sent')",
      );
      for (final intent in intents) {
        if (!await _isRunValid(accountId: accountId, generation: generation)) {
          throw StateError('云端账号已变化，原核对结果已作废');
        }
        try {
          final value = intent['value'] as String;
          final confirmed = await _applyTaskCompletionIntent(
            db: db,
            accountId: accountId,
            generation: generation,
            entityLocalId: intent['entity_local_id'] as int,
            intentValue: value,
            intentUpdatedAt: intent['updated_at'] as String?,
          );
          if (confirmed == true) {
            verified++;
          } else {
            unknown++;
          }
        } catch (_) {
          unknown++;
        }
      }
      if (!await _isRunValid(accountId: accountId, generation: generation)) {
        throw StateError('云端账号已变化，原核对结果已作废');
      }
      return SyncReconciliationReport(
        verified: verified,
        conflicts: 0,
        unknown: unknown,
      );
    } finally {
      isSyncing.value = false;
      if (_rerunRequested && DataModeManager().isCloud) unawaited(syncNow());
    }
  }

  Future<bool> _runOnce(int generation) async {
    final accountId = (await AuthService.getUser())?.id;
    if (accountId == null ||
        accountId <= 0 ||
        !await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }
    final sync = SyncService();
    await sync.init(startPeriodic: false);
    final db = await _cache.database;
    if (!await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }

    var attempted = 0;
    var failed = 0;
    var networkUnreachable = false;
    final taskIntents = await db.query(
      'sync_intents',
      where: 'entity_type = ? AND intent = ?',
      whereArgs: ['tasks', 'completion'],
    );

    if (taskIntents.isNotEmpty) {
      await sync.syncBatch(batchSize: 50);
      for (final intent in taskIntents) {
        if (!await _isRunValid(accountId: accountId, generation: generation)) {
          return false;
        }
        final localId = intent['entity_local_id'] as int;
        try {
          final applied = await _applyTaskCompletionIntent(
            db: db,
            accountId: accountId,
            generation: generation,
            entityLocalId: localId,
            intentValue: intent['value'] as String,
            intentUpdatedAt: intent['updated_at'] as String?,
          );
          if (applied != null) {
            attempted++;
            if (!applied) failed++;
          }
        } catch (error) {
          attempted++;
          failed++;
          networkUnreachable |= error is SocketException;
        }
      }
    }

    final reflection = await _syncReflectionIntents(
      db: db,
      accountId: accountId,
      generation: generation,
    );
    if (!await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }
    attempted += reflection.attempted;
    failed += reflection.failed;
    networkUnreachable |= reflection.networkUnreachable;

    // Never pull a previous task state over an unapplied completion intent.
    final taskPending = (await db.rawQuery(
      "SELECT 1 FROM sync_intents WHERE entity_type = 'tasks' "
      "AND intent = 'completion' LIMIT 1",
    ))
        .isNotEmpty;
    final preflight = taskIntents.isEmpty ? null : sync.lastQueueRun;
    final canPull = !taskPending && (preflight?.failed ?? 0) == 0;
    final unknown = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM sync_intents WHERE entity_type = 'tasks' "
      "AND intent = 'completion' AND value IN ('0:sent', '1:sent')",
    )) ?? 0;
    final ordinarySucceeded = canPull && await sync.manualSync();
    if (!await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }
    _preflightRun = identical(preflight, sync.lastQueueRun) ? null : preflight;
    _intentNetworkUnreachable = networkUnreachable;
    lastIntentRun.value = attempted == 0 && unknown == 0
        ? null
        : SyncQueueRunEvidence(attempted: attempted, failed: failed, unknown: unknown);
    return ordinarySucceeded && failed == 0;
  }

  Future<bool?> _applyTaskCompletionIntent({
    required Database db,
    required int accountId,
    required int generation,
    required int entityLocalId,
    required String intentValue,
    required String? intentUpdatedAt,
  }) async {
    final desiredCompleted = switch (intentValue) {
      '1' || '1:sent' => true,
      '0' || '0:sent' => false,
      _ => throw const FormatException('待同步任务完成状态无效'),
    };
    var expectedIntentValue = intentValue;
    // 普通字段/create 尚未 push 成功时，保留意图等待下次同步。
    final queued = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM sync_queue '
      'WHERE entity_type = ? AND entity_local_id = ?',
      ['tasks', entityLocalId],
    );
    if ((queued.first['cnt'] as int? ?? 0) > 0) return null;
    if (!await _isTaskIntentCurrent(
      db,
      entityLocalId,
      intentValue,
      intentUpdatedAt,
    )) return false;

    final rows = await db.query(
      'tasks',
      columns: ['server_id', 'deleted_at'],
      where: 'id = ?',
      whereArgs: [entityLocalId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['deleted_at'] != null) {
      await _deleteTaskIntent(db, entityLocalId, intentValue, intentUpdatedAt);
      return null;
    }
    final serverId = rows.first['server_id'] as int?;
    if (serverId == null || serverId <= 0) return false;
    if (!await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }

    // A lost PATCH receipt is reconciled by this GET on the next pass.
    // Completion is never re-enqueued as an unrelated ordinary field update.
    final remote = await TaskApi.getTask(serverId);
    if (!await _isRunValid(accountId: accountId, generation: generation) ||
        !await _isTaskIntentCurrent(
          db,
          entityLocalId,
          intentValue,
          intentUpdatedAt,
        )) return false;

    var applied = remote;
    if (remote.id != serverId) return false;
    if (remote.isCompleted != desiredCompleted) {
      // A prior request may have committed and another device may have
      // changed the state afterwards. A differing GET cannot authorize replay.
      if (intentValue.endsWith(':sent')) return false;
      expectedIntentValue = '$intentValue:sent';
      final reserved = await db.update(
        'sync_intents',
        {'value': expectedIntentValue},
        where: _taskIntentSnapshotWhere(intentUpdatedAt),
        whereArgs: _taskIntentSnapshotArgs(
          entityLocalId,
          intentValue,
          intentUpdatedAt,
        ),
      );
      if (reserved != 1 ||
          !await _isRunValid(accountId: accountId, generation: generation)) {
        return false;
      }
      try {
        applied = await TaskApi.setTaskCompletion(
          serverId,
          completed: desiredCompleted,
          expectedCompleted: remote.isCompleted,
          expectedCompletedAt: remote.completedAt,
        );
      } catch (error) {
        if (NetworkRetry.requestNotSent(error) &&
            await _isRunValid(accountId: accountId, generation: generation)) {
          await db.update(
            'sync_intents',
            {'value': intentValue},
            where: _taskIntentSnapshotWhere(intentUpdatedAt),
            whereArgs: _taskIntentSnapshotArgs(
              entityLocalId,
              expectedIntentValue,
              intentUpdatedAt,
            ),
          );
        }
        rethrow;
      }
    }
    if (applied.id != serverId ||
        applied.isCompleted != desiredCompleted ||
        !await _isRunValid(accountId: accountId, generation: generation)) {
      return false;
    }
    return db.transaction((txn) async {
      final removed = await _deleteTaskIntent(
        txn,
        entityLocalId,
        expectedIntentValue,
        intentUpdatedAt,
      );
      if (removed != 1) return false;
      // A newer ordinary edit owns its own queue status. Only replace the
      // optimistic completion timestamp when this exact intent is confirmed.
      await txn.rawUpdate(
        "UPDATE tasks SET completed_at = ?, sync_status = "
        "CASE WHEN NOT EXISTS (SELECT 1 FROM sync_queue q WHERE "
        "q.entity_type = 'tasks' AND q.entity_local_id = tasks.id) "
        "AND sync_status = 'pending' THEN 'synced' ELSE sync_status END "
        "WHERE id = ? AND deleted_at IS NULL",
        [applied.completedAt?.toUtc().toIso8601String(), entityLocalId],
      );
      return true;
    });
  }

  Future<({int attempted, int failed, bool networkUnreachable})>
      _syncReflectionIntents({
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
    var attempted = 0;
    var failed = 0;
    var networkUnreachable = false;
    for (final intent in intents) {
      if (!await _isRunValid(accountId: accountId, generation: generation))
        break;
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

      Map<String, dynamic> context = <String, dynamic>{};
      try {
        final decoded = jsonDecode(row['context_json']?.toString() ?? '{}');
        if (decoded is Map) context = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      // 待提交标签属于同步意图而非用户观察内容；兼容旧版本曾暂存在
      // context_json 中的 _pending_tag_ids，补交时不向服务器发送内部字段。
      dynamic rawTagIds;
      String? pendingRequestId;
      try {
        final value = jsonDecode(intent['value']?.toString() ?? '{}');
        if (value is Map) {
          rawTagIds = value['tag_ids'];
          final id = value['client_request_id'];
          if (id is String && id.isNotEmpty && id.length <= 100) {
            pendingRequestId = id;
          }
        }
      } catch (_) {}
      rawTagIds ??= context.remove('_pending_tag_ids');
      context.remove('_pending_tag_ids');
      final pendingTagIds = (rawTagIds is List ? rawTagIds : const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(growable: false);

      attempted++;
      try {
        final remote = await ReflectionApi.create(
          content: row['content'] as String? ?? '',
          entryType: row['entry_type'] as String? ?? 'reflection',
          questionId: row['question_id'] as String?,
          dimensionKey: row['dimension_key'] as String?,
          context: context,
          tagIds: pendingTagIds,
          // Older pending intents have no stored identity; retain their
          // existing stable fallback. New intents replay the *same* ID used
          // for the initial direct POST, including after a lost ACK.
          clientRequestId: pendingRequestId ??
              ReflectionApi.periodClientRequestId(
                row['question_id'] as String?,
              ) ??
              '${SyncService().deviceId}:reflection:$localId',
        );
        if (!await _isRunValid(accountId: accountId, generation: generation))
          break;
        if (remote.id <= 0) {
          throw const FormatException('观察同步回执缺少有效记录 ID');
        }
        await _reflectionCache.markCreateSynced(db, localId, remote);
      } catch (error) {
        failed++;
        networkUnreachable |= error is SocketException;
        // Keep the same request identity for the next idempotent replay.
      }
    }
    return (
      attempted: attempted,
      failed: failed,
      networkUnreachable: networkUnreachable
    );
  }

  // Match the snapshot in SQL so a late ACK cannot consume a newer intent.
  String _taskIntentSnapshotWhere(String? updatedAt) =>
      'entity_type = ? AND entity_local_id = ? AND intent = ? '
      'AND value = ? AND ${updatedAt == null ? 'updated_at IS NULL' : 'updated_at = ?'}';

  List<Object> _taskIntentSnapshotArgs(
    int localId,
    String value,
    String? updatedAt,
  ) =>
      ['tasks', localId, 'completion', value, if (updatedAt != null) updatedAt];

  Future<bool> _isTaskIntentCurrent(
    Database db,
    int localId,
    String value,
    String? updatedAt,
  ) async {
    final rows = await db.query(
      'sync_intents',
      columns: ['value'],
      where: _taskIntentSnapshotWhere(updatedAt),
      whereArgs: _taskIntentSnapshotArgs(localId, value, updatedAt),
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> _deleteTaskIntent(
    DatabaseExecutor db,
    int localId,
    String value,
    String? updatedAt,
  ) =>
      db.delete(
        'sync_intents',
        where: _taskIntentSnapshotWhere(updatedAt),
        whereArgs: _taskIntentSnapshotArgs(localId, value, updatedAt),
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
    _pendingReadVersion++;
    _rerunRequested = false;
    _activeAccountId = null;
    _preflightRun = null;
    _intentNetworkUnreachable = false;
    lastIntentRun.value = null;
    _timer?.cancel();
    _timer = null;
    standalonePendingCount.value = 0;
    standalonePendingUnknown.value = false;
  }
}
