import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/cloud_cache_db.dart';
import '../models/tag.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import 'api/task_api.dart';
import 'api_service.dart';
import 'data_mode_manager.dart';
import 'sync_incremental_pull.dart';
import 'sync_remote_api.dart';

enum SyncStatusEnum { idle, syncing, error }

class ConflictInfo {
  final dynamic local;
  final dynamic remote;
  final String table;
  final int recordId;

  ConflictInfo({
    required this.local,
    required this.remote,
    required this.table,
    required this.recordId,
  });

  factory ConflictInfo.localWins(
    dynamic local,
    dynamic remote,
    String table,
    int recordId,
  ) => ConflictInfo(
        local: local,
        remote: remote,
        table: table,
        recordId: recordId,
      );

  factory ConflictInfo.remoteWins(
    dynamic local,
    dynamic remote,
    String table,
    int recordId,
  ) => ConflictInfo(
        local: local,
        remote: remote,
        table: table,
        recordId: recordId,
      );

  factory ConflictInfo.noConflict(
    dynamic local,
    String table,
    int recordId,
  ) => ConflictInfo(
        local: local,
        remote: null,
        table: table,
        recordId: recordId,
      );
}

enum ConflictStrategy { localWins, remoteWins, merge, askUser }

class SyncConflictPolicy {
  const SyncConflictPolicy._();

  static ConflictStrategy requestedStrategy({
    bool? keepLocal,
    ConflictStrategy strategy = ConflictStrategy.merge,
  }) {
    if (keepLocal == true) return ConflictStrategy.localWins;
    if (keepLocal == false) return ConflictStrategy.remoteWins;
    return strategy;
  }
}

class SyncOperation {
  final String table;
  final int recordId;
  final String action;
  final dynamic data;
  final int priority;
  final DateTime createdAt;
  int retryCount;

  SyncOperation({
    required this.table,
    required this.recordId,
    required this.action,
    this.data,
    this.priority = 0,
    DateTime? createdAt,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'table': table,
        'record_id': recordId,
        'action': action,
        'data': data,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
      };
}

/// Cloud Data Mode 的离线缓存 / 同步可靠性层。
///
/// Local Data 的普通 CRUD 不进入本队列；Local → Cloud 属于显式迁移能力。
class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._();
  factory SyncService() => _instance;
  SyncService._();

  static const _deviceIdKey = 'slowlight_sync_device_id';

  final CloudCacheDb _db = CloudCacheDb();
  Timer? _periodicTimer;
  SyncStatusEnum _status = SyncStatusEnum.idle;
  String? _lastError;
  int _pendingCount = 0;
  String _deviceId = '';
  bool _initialized = false;
  int? _initializedAccountId;

  SyncStatusEnum get status => _status;
  String? get lastError => _lastError;
  int get pendingCount => _pendingCount;
  bool get isSyncing => _status == SyncStatusEnum.syncing;
  String get deviceId => _deviceId;

  Future<void> init({bool startPeriodic = true}) async {
    await _db.database;
    final accountId = _db.currentAccountId;
    if (!_initialized || _initializedAccountId != accountId) {
      _deviceId = await _getOrCreateDeviceId();
      _pendingCount = await _getQueueCount();
      _initialized = true;
      _initializedAccountId = accountId;
    }
    _periodicTimer?.cancel();
    if (startPeriodic && DataModeManager().isCloud) _startPeriodicSync();
  }

  Future<void> enqueue({
    required String entityType,
    required int entityLocalId,
    int? entityServerId,
    required String operation,
    Map<String, dynamic>? payload,
  }) async {
    _requireCloudMode();
    await init(startPeriodic: false);
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final existing = await db.query(
      'sync_queue',
      where: 'entity_type = ? AND entity_local_id = ?',
      whereArgs: [entityType, entityLocalId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (existing.isNotEmpty && operation != 'create') {
      await db.update(
        'sync_queue',
        {
          'entity_server_id': entityServerId,
          'operation': operation,
          'payload': payload == null ? null : jsonEncode(payload),
          'retry_count': 0,
          'last_error': '',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('sync_queue', {
        'entity_type': entityType,
        'entity_local_id': entityLocalId,
        'entity_server_id': entityServerId,
        'operation': operation,
        'payload': payload == null ? null : jsonEncode(payload),
        'retry_count': 0,
        'last_error': '',
        'created_at': now,
        'updated_at': now,
      });
    }

    if (await _hasColumn(db, entityType, 'sync_status')) {
      await db.update(
        entityType,
        {
          'sync_status': 'pending',
          'version': await _currentVersion(db, entityType, entityLocalId) + 1,
          'last_modified': now,
          'device_id': _deviceId,
        },
        where: 'id = ?',
        whereArgs: [entityLocalId],
      );
    }
    _pendingCount = await _getQueueCount();
    notifyListeners();
  }

  Future<bool> manualSync() =>
      DataModeManager().isCloud ? _doSync() : Future.value(false);

  Future<bool> _doSync() async {
    if (!DataModeManager().isCloud || _status == SyncStatusEnum.syncing) {
      return false;
    }
    await init(startPeriodic: false);
    _status = SyncStatusEnum.syncing;
    _lastError = null;
    notifyListeners();
    try {
      final db = await _db.database;
      for (final item in await _orderedQueue(db, 50)) {
        await _processQueueItem(db, item);
      }
      _pendingCount = await _getQueueCount();
      await pullFromServer();
      _status = SyncStatusEnum.idle;
      notifyListeners();
      return true;
    } catch (e) {
      _status = SyncStatusEnum.error;
      _lastError = e.toString();
      _pendingCount = await _getQueueCount();
      notifyListeners();
      return false;
    }
  }

  Future<List<Map<String, Object?>>> _orderedQueue(Database db, int limit) =>
      db.rawQuery(
        '''SELECT * FROM sync_queue
           ORDER BY CASE entity_type
             WHEN 'lists' THEN 0 WHEN 'system_tags' THEN 1 WHEN 'tags' THEN 2
             WHEN 'habits' THEN 3 WHEN 'tasks' THEN 4 WHEN 'habit_logs' THEN 5
             ELSE 9 END ASC, created_at ASC LIMIT ?''',
        [limit],
      );

  Future<void> _processQueueItem(
    Database db,
    Map<String, Object?> item,
  ) async {
    try {
      await _syncItem(db, Map<String, dynamic>.from(item));
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [item['id']]);
      final table = item['entity_type'] as String;
      if (await _hasColumn(db, table, 'sync_status')) {
        await db.update(
          table,
          {'sync_status': 'synced'},
          where: 'id = ?',
          whereArgs: [item['entity_local_id']],
        );
      }
    } catch (e) {
      final retries = (item['retry_count'] as int? ?? 0) + 1;
      final text = e.toString();
      await db.update(
        'sync_queue',
        {
          'retry_count': retries,
          'last_error': text.substring(0, min(200, text.length)),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [item['id']],
      );
      if (retries >= 3) {
        await _markConflict(
          db,
          item['entity_type'] as String,
          item['entity_local_id'] as int,
        );
      }
    }
  }

  Future<void> _syncItem(Database db, Map<String, dynamic> item) async {
    _requireCloudMode();
    final table = item['entity_type'] as String;
    final op = item['operation'] as String;
    final localId = item['entity_local_id'] as int;
    final serverId = item['entity_server_id'] as int?;
    switch (table) {
      case 'tasks':
        return _pushTask(db, op, localId, serverId);
      case 'lists':
        return _pushList(db, op, localId, serverId);
      case 'tags':
        return _pushTag(db, op, localId, serverId);
      case 'system_tags':
        return _pushSystemTag(db, op, localId, serverId);
      case 'habits':
        return _pushHabit(db, op, localId, serverId);
      case 'habit_logs':
        return _pushHabitLog(db, op, localId, serverId);
      default:
        throw StateError('Unsupported sync entity: $table');
    }
  }

  Future<void> _pushTask(
    Database db,
    String op,
    int localId,
    int? queuedServerId,
  ) async {
    if (op == 'delete') {
      if (queuedServerId != null && queuedServerId > 0) {
        await ApiService.deleteTask(queuedServerId)
            .timeout(const Duration(seconds: 10));
      }
      return;
    }
    final row = await _row(db, 'tasks', localId);
    final listId = await _serverId(db, 'lists', row['list_id'] as int? ?? 0);
    if (listId <= 0) throw StateError('Task list has not been synced');
    final systemTagId = await _mapSystemTag(db, row['system_tag_id'] as int?);
    final relatedLocalId = row['related_quest_id'] as int?;
    final relatedServerId = relatedLocalId == null
        ? null
        : await _serverId(db, 'tasks', relatedLocalId);
    final tagIds = await _remoteTagIds(db, localId);

    Future<Task> create() => TaskApi.createTask(
          listId: listId,
          title: row['title'] as String,
          description: row['description'] as String?,
          priority: row['priority'] as String? ?? 'none',
          dueDate: _parseDate(row['due_date']),
          dueTime: row['due_time'] as String?,
          repeatType: row['repeat_type'] as String? ?? 'none',
          repeatInterval: row['repeat_interval'] as int? ?? 1,
          repeatDays: row['repeat_days'] as String? ?? '',
          reminderAt: _parseDate(row['reminder_at']),
          reminderAdvanceMinutes:
              row['reminder_advance_minutes'] as int? ?? 0,
          tagIds: tagIds,
          systemTagId: systemTagId,
          taskType: row['task_type'] as String? ?? 'daily',
          moodBefore: row['mood_before'] as int? ?? 0,
          moodAfter: row['mood_after'] as int? ?? 0,
          isMilestone: (row['is_milestone'] as int? ?? 0) == 1,
          relatedQuestId: relatedServerId != null && relatedServerId > 0
              ? relatedServerId
              : null,
          obsidianLink: row['obsidian_link'] as String? ?? '',
          outputLevel: row['output_level'] as String? ?? '',
        );

    if (op == 'create') {
      final remote = await create().timeout(const Duration(seconds: 10));
      await db.update('tasks', {'server_id': remote.id},
          where: 'id = ?', whereArgs: [localId]);
      return;
    }

    final sid = queuedServerId ?? row['server_id'] as int?;
    if (sid == null || sid <= 0) throw StateError('Task has no server id');
    await TaskApi.updateTask(
      taskId: sid,
      listId: listId,
      title: row['title'] as String,
      description: row['description'] as String?,
      priority: row['priority'] as String? ?? 'none',
      dueDate: _parseDate(row['due_date']),
      dueTime: row['due_time'] as String?,
      repeatType: row['repeat_type'] as String? ?? 'none',
      repeatInterval: row['repeat_interval'] as int? ?? 1,
      repeatDays: row['repeat_days'] as String? ?? '',
      reminderAt: _parseDate(row['reminder_at']),
      reminderAdvanceMinutes: row['reminder_advance_minutes'] as int? ?? 0,
      tagIds: tagIds,
      systemTagId: systemTagId,
      taskType: row['task_type'] as String? ?? 'daily',
      moodBefore: row['mood_before'] as int? ?? 0,
      moodAfter: row['mood_after'] as int? ?? 0,
      isMilestone: (row['is_milestone'] as int? ?? 0) == 1,
      relatedQuestId:
          relatedServerId != null && relatedServerId > 0 ? relatedServerId : null,
      obsidianLink: row['obsidian_link'] as String? ?? '',
      outputLevel: row['output_level'] as String? ?? '',
    ).timeout(const Duration(seconds: 10));
  }

  Future<void> _pushList(
    Database db,
    String op,
    int localId,
    int? queuedServerId,
  ) async {
    if (op == 'delete') {
      if (queuedServerId != null && queuedServerId > 0) {
        await ApiService.deleteList(queuedServerId)
            .timeout(const Duration(seconds: 10));
      }
      return;
    }
    final row = await _row(db, 'lists', localId);
    if (op == 'create') {
      final remote = await ApiService.createList(
        name: row['name'] as String,
        icon: row['icon'] as String? ?? '📋',
        color: row['color'] as String? ?? '#1890ff',
        isInbox: (row['is_inbox'] as int? ?? 0) == 1,
      ).timeout(const Duration(seconds: 10));
      await db.update('lists', {'server_id': remote.id},
          where: 'id = ?', whereArgs: [localId]);
      return;
    }
    final sid = queuedServerId ?? row['server_id'] as int?;
    if (sid == null || sid <= 0) throw StateError('List has no server id');
    await ApiService.updateList(
      id: sid,
      name: row['name'] as String?,
      icon: row['icon'] as String?,
      color: row['color'] as String?,
    ).timeout(const Duration(seconds: 10));
  }

  Future<void> _pushTag(
    Database db,
    String op,
    int localId,
    int? queuedServerId,
  ) async {
    if (op == 'delete') {
      if (queuedServerId != null && queuedServerId > 0) {
        await ApiService.deleteTag(queuedServerId)
            .timeout(const Duration(seconds: 10));
      }
      return;
    }
    final row = await _row(db, 'tags', localId);
    if (op == 'create') {
      final remote = await ApiService.createTag(
        name: row['name'] as String,
        color: row['color'] as String? ?? '#0075de',
      ).timeout(const Duration(seconds: 10));
      await db.update('tags', {'server_id': remote.id},
          where: 'id = ?', whereArgs: [localId]);
      return;
    }
    final sid = queuedServerId ?? row['server_id'] as int?;
    if (sid == null || sid <= 0) throw StateError('Tag has no server id');
    await ApiService.updateTag(
      id: sid,
      name: row['name'] as String?,
      color: row['color'] as String?,
    ).timeout(const Duration(seconds: 10));
  }

  Future<void> _pushSystemTag(
    Database db,
    String op,
    int localId,
    int? queuedServerId,
  ) async {
    if (op == 'delete') {
      if (queuedServerId != null && queuedServerId > 0) {
        await ApiService.deleteSystemTag(queuedServerId)
            .timeout(const Duration(seconds: 10));
      }
      return;
    }
    final row = await _row(db, 'system_tags', localId);
    final dimensionKey = row['dimension_key'] as String? ?? '';
    if (op == 'create') {
      final remote = await SyncRemoteApi.createSystemTag(
        name: row['name'] as String,
        icon: row['icon'] as String? ?? '🏷️',
        color: row['color'] as String? ?? '#1890ff',
        dimensionKey: dimensionKey,
      ).timeout(const Duration(seconds: 10));
      await db.update('system_tags', {'server_id': remote['id']},
          where: 'id = ?', whereArgs: [localId]);
      return;
    }
    final sid = queuedServerId ?? row['server_id'] as int?;
    if (sid == null || sid <= 0) {
      throw StateError('SystemTag has no server id');
    }
    await SyncRemoteApi.updateSystemTag(
      sid,
      name: row['name'] as String?,
      icon: row['icon'] as String?,
      color: row['color'] as String?,
      dimensionKey: dimensionKey,
    );
  }

  Future<void> _pushHabit(
    Database db,
    String op,
    int localId,
    int? queuedServerId,
  ) async {
    if (op == 'delete') {
      if (queuedServerId != null && queuedServerId > 0) {
        await ApiService.deleteHabit(queuedServerId)
            .timeout(const Duration(seconds: 10));
      }
      return;
    }
    final row = await _row(db, 'habits', localId);
    final systemTagId = await _mapSystemTag(db, row['system_tag_id'] as int?);
    final reminderAt = _jsonMap(row['reminder_at']);
    if (op == 'create') {
      final remote = await ApiService.createHabit(
        name: row['name'] as String,
        icon: row['icon'] as String? ?? '✅',
        color: row['color'] as String? ?? '#52c41a',
        frequency: row['frequency'] as String? ?? 'daily',
        targetDays: row['target_days'] as int? ?? 0,
        systemTagId: systemTagId,
        preferredPeriod: row['preferred_period'] as String? ?? '',
        durationMin: row['duration_min'] as int? ?? 0,
        generateTask: (row['generate_task'] as int? ?? 0) == 1,
        showCheckinDialog: (row['show_checkin_dialog'] as int? ?? 0) == 1,
        specificTime: row['specific_time'] as String? ?? '',
        reminderAt: reminderAt,
      ).timeout(const Duration(seconds: 10));
      await db.update('habits', {'server_id': remote['id']},
          where: 'id = ?', whereArgs: [localId]);
      return;
    }
    final sid = queuedServerId ?? row['server_id'] as int?;
    if (sid == null || sid <= 0) throw StateError('Habit has no server id');
    await ApiService.updateHabit(sid, {
      'name': row['name'],
      'icon': row['icon'],
      'color': row['color'],
      'frequency': row['frequency'],
      'target_days': row['target_days'],
      'system_tag_id': systemTagId,
      'preferred_period': row['preferred_period'],
      'duration_min': row['duration_min'],
      'generate_task': (row['generate_task'] as int? ?? 0) == 1,
      'show_checkin_dialog': (row['show_checkin_dialog'] as int? ?? 0) == 1,
      'specific_time': row['specific_time'],
      'reminder_at': reminderAt,
    }).timeout(const Duration(seconds: 10));
  }

  Future<void> _pushHabitLog(
    Database db,
    String op,
    int localId,
    int? queuedServerId,
  ) async {
    if (op == 'delete') {
      throw StateError('Remote arbitrary HabitLog delete is not supported');
    }
    if (op != 'create') return;
    final row = await _row(db, 'habit_logs', localId);
    final habitServerId =
        await _serverId(db, 'habits', row['habit_id'] as int? ?? 0);
    if (habitServerId <= 0) throw StateError('Habit has not been synced');
    final result = await ApiService.checkInHabit(
      habitServerId,
      note: row['note'] as String? ?? '',
      date: row['date'] as String?,
      durationMin: row['duration_min'] as int?,
      period: row['period'] as String?,
    ).timeout(const Duration(seconds: 10));
    final log = result['log'];
    final remoteId = log is Map ? log['id'] as int? : result['id'] as int?;
    if (remoteId != null) {
      await db.update('habit_logs', {'server_id': remoteId},
          where: 'id = ?', whereArgs: [localId]);
    }
  }

  void _startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (DataModeManager().isCloud) _doSync();
    });
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final host = Platform.localHostname.trim().isEmpty
        ? 'device'
        : Platform.localHostname.trim();
    final random = Random.secure()
        .nextInt(0x7fffffff)
        .toRadixString(16)
        .padLeft(8, '0');
    final created = '${host}_$random';
    await prefs.setString(_deviceIdKey, created);
    return created;
  }

  Future<int> _getQueueCount() async {
    final db = await _db.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM sync_queue');
    return rows.first['cnt'] as int? ?? 0;
  }

  Future<int> _currentVersion(Database db, String table, int id) async {
    if (!await _hasColumn(db, table, 'version')) return 0;
    final rows = await db.query(
      table,
      columns: ['version'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['version'] as int? ?? 0);
  }

  Future<void> cleanupFailedItems() async {
    final db = await _db.database;
    for (final item in await db.query('sync_queue', where: 'retry_count >= 3')) {
      await _markConflict(
        db,
        item['entity_type'] as String,
        item['entity_local_id'] as int,
      );
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [item['id']]);
    }
    _pendingCount = await _getQueueCount();
    notifyListeners();
  }

  Future<void> syncBatch({int batchSize = 10}) async {
    if (!DataModeManager().isCloud || _status == SyncStatusEnum.syncing) return;
    await init(startPeriodic: false);
    _status = SyncStatusEnum.syncing;
    _lastError = null;
    notifyListeners();
    try {
      final db = await _db.database;
      for (final item in await _orderedQueue(db, batchSize)) {
        await _processQueueItem(db, item);
      }
      _pendingCount = await _getQueueCount();
      _status = SyncStatusEnum.idle;
    } catch (e) {
      _status = SyncStatusEnum.error;
      _lastError = e.toString();
    }
    notifyListeners();
  }

  Future<void> retryFailed({int maxRetries = 3}) async {
    if (!DataModeManager().isCloud || _status == SyncStatusEnum.syncing) return;
    final db = await _db.database;
    final exceeded = await db.query(
      'sync_queue',
      where: 'retry_count >= ?',
      whereArgs: [maxRetries],
    );
    for (final item in exceeded) {
      await _markConflict(
        db,
        item['entity_type'] as String,
        item['entity_local_id'] as int,
      );
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [item['id']]);
    }
    await syncBatch(batchSize: 50);
  }

  Future<void> markSynced({
    required String entityType,
    required int entityLocalId,
    int? entityServerId,
  }) async {
    final db = await _db.database;
    await db.update(
      entityType,
      {
        'sync_status': 'synced',
        'last_modified': DateTime.now().toUtc().toIso8601String(),
        if (entityServerId != null) 'server_id': entityServerId,
      },
      where: 'id = ?',
      whereArgs: [entityLocalId],
    );
  }

  Future<ConflictInfo> detectConflict(int recordId, String table) async {
    _requireCloudMode();
    final db = await _db.database;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [recordId]);
    if (rows.isEmpty) {
      throw StateError('Local record not found in $table with id=$recordId');
    }
    final local = rows.first;
    final sid = local['server_id'] as int?;
    if (sid == null || sid <= 0 ||
        (local['sync_status'] as String? ?? 'synced') == 'synced') {
      return ConflictInfo.noConflict(local, table, recordId);
    }
    final remote = await _fetchRemote(db, table, sid, local);
    return remote == null
        ? ConflictInfo.noConflict(local, table, recordId)
        : ConflictInfo(
            local: local,
            remote: remote,
            table: table,
            recordId: recordId,
          );
  }

  Future<bool> resolveConflict(
    int entityLocalId, {
    bool? keepLocal,
    Map<String, dynamic>? serverVersion,
    ConflictStrategy strategy = ConflictStrategy.merge,
    String entityType = 'tasks',
  }) async {
    _requireCloudMode();
    await init(startPeriodic: false);
    final selected = SyncConflictPolicy.requestedStrategy(
      keepLocal: keepLocal,
      strategy: strategy,
    );
    if (selected == ConflictStrategy.askUser) {
      throw StateError('Conflict requires explicit user choice');
    }

    final db = await _db.database;
    final rows = await db.query(
      entityType,
      where: 'id = ?',
      whereArgs: [entityLocalId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final local = rows.first;
    final sid = local['server_id'] as int?;
    if (sid == null || sid <= 0) return false;

    try {
      if (selected == ConflictStrategy.localWins) {
        await _removeQueue(db, entityType, entityLocalId);
        await enqueue(
          entityType: entityType,
          entityLocalId: entityLocalId,
          entityServerId: sid,
          operation: 'update',
        );
        return true;
      }

      final rawRemote =
          serverVersion ?? await _fetchRemote(db, entityType, sid, local);
      if (rawRemote == null) return false;
      final remote = await _normalizeRemote(db, entityType, rawRemote);

      if (selected == ConflictStrategy.remoteWins) {
        await _applyRemote(db, entityType, entityLocalId, remote);
        await _removeQueue(db, entityType, entityLocalId);
        notifyListeners();
        return true;
      }

      final merged = _merge(entityType, local, remote);
      await db.update(
        entityType,
        {
          ...merged,
          'sync_status': 'pending',
          'version': (local['version'] as int? ?? 0) + 1,
          'last_modified': DateTime.now().toUtc().toIso8601String(),
          'device_id': _deviceId,
        },
        where: 'id = ?',
        whereArgs: [entityLocalId],
      );
      await _removeQueue(db, entityType, entityLocalId);
      await enqueue(
        entityType: entityType,
        entityLocalId: entityLocalId,
        entityServerId: sid,
        operation: 'update',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getConflicts(String entityType) async {
    final db = await _db.database;
    final rows = await db.query(
      entityType,
      where: 'sync_status = ?',
      whereArgs: ['conflict'],
    );
    return rows.map(Map<String, dynamic>.from).toList();
  }

  Future<int> getServerId(String entityType, int localId) async {
    final db = await _db.database;
    return _serverId(db, entityType, localId);
  }

  Future<void> pullFromServer() async {
    _requireCloudMode();
    final db = await _db.database;
    await _pullLists(db);
    await _pullSystemTags(db);
    await _pullTags(db);
    await _pullHabits(db);
    await _pullTasks(db);
    await _pullHabitLogs(db);
    // 仅在普通多实体 Pull 全部成功后应用权威删除并推进 cursor。
    await SyncIncrementalPull(accountId: _db.currentAccountId).applyDeleted(db);
  }

  Future<void> _pullLists(Database db) async {
    final items =
        await ApiService.getLists().timeout(const Duration(seconds: 15));
    for (final item in items) {
      await _upsert(db, 'lists', item.id, {
        'name': item.name,
        'icon': item.icon,
        'color': item.color,
        'is_inbox': item.isInbox ? 1 : 0,
        'created_at': item.createdAt.toIso8601String(),
        'updated_at': _now(),
        'deleted_at': null,
      });
    }
  }

  Future<void> _pullSystemTags(Database db) async {
    final items =
        await ApiService.getSystemTags().timeout(const Duration(seconds: 15));
    for (final item in items) {
      final id = item['id'] as int?;
      if (id == null) continue;
      await _upsert(db, 'system_tags', id, {
        'name': item['name'] ?? '',
        'icon': item['icon'] ?? '🏷️',
        'color': item['color'] ?? '#1890ff',
        'dimension_key': item['dimension_key'] ?? '',
        'created_at': _dateString(item['created_at']),
        'updated_at': _dateString(item['updated_at']),
      });
    }
  }

  Future<void> _pullTags(Database db) async {
    final items =
        await ApiService.getTags().timeout(const Duration(seconds: 15));
    for (final item in items) {
      await _upsert(db, 'tags', item.id, {
        'name': item.name,
        'color': item.color,
        'created_at': item.createdAt.toIso8601String(),
        'updated_at': _now(),
      });
    }
  }

  Future<void> _pullHabits(Database db) async {
    final items =
        await ApiService.getHabits().timeout(const Duration(seconds: 15));
    for (final item in items) {
      final id = item['id'] as int?;
      if (id == null) continue;
      await _upsert(db, 'habits', id, {
        'name': item['name'] ?? '',
        'icon': item['icon'] ?? '✅',
        'color': item['color'] ?? '#52c41a',
        'frequency': item['frequency'] ?? 'daily',
        'target_days': item['target_days'] ?? 0,
        'streak_count': item['streak_count'] ?? 0,
        'preferred_period': item['preferred_period'] ?? '',
        'system_tag_id':
            await _localId(db, 'system_tags', item['system_tag_id']),
        'generate_task': _boolInt(item['generate_task']),
        'duration_min': item['duration_min'] ?? 0,
        'show_checkin_dialog': _boolInt(item['show_checkin_dialog']),
        'specific_time': item['specific_time'] ?? '',
        'reminder_at': jsonEncode(item['reminder_at'] ?? {}),
        'created_at': _dateString(item['created_at']),
        'updated_at': _dateString(item['updated_at']),
        'deleted_at': null,
      });
    }
  }

  Future<void> _pullTasks(Database db) async {
    final items =
        await TaskApi.getAllTasks().timeout(const Duration(seconds: 15));
    final localIds = <int, int>{};

    // 第一遍先建立所有 server_id → local id，避免 relatedQuest 前向引用丢失。
    for (final item in items) {
      final listId = await _localId(db, 'lists', item.listId);
      if (listId == null) continue;
      final localId = await _upsert(db, 'tasks', item.id, {
        'list_id': listId,
        'title': item.title,
        'description': item.description ?? '',
        'due_date': item.dueDate == null ? null : _day(item.dueDate!),
        'due_time': item.dueTime,
        'is_completed': item.isCompleted ? 1 : 0,
        'completed_at': item.completedAt?.toUtc().toIso8601String(),
        'priority': item.priority,
        'repeat_type': item.repeatType,
        'repeat_interval': item.repeatInterval,
        'repeat_days': item.repeatDays,
        'reminder_at': item.reminderAt?.toUtc().toIso8601String(),
        'reminder_advance_minutes': item.reminderAdvanceMinutes,
        'system_tag_id': await _localId(db, 'system_tags', item.systemTagId),
        'task_type': item.taskType,
        'mood_before': item.moodBefore,
        'mood_after': item.moodAfter,
        'is_milestone': item.isMilestone ? 1 : 0,
        'related_quest_id': null,
        'obsidian_link': item.obsidianLink,
        'output_level': item.outputLevel,
        'created_at': item.createdAt.toIso8601String(),
        'updated_at': _now(),
        'deleted_at': null,
      });
      if (localId != null) localIds[item.id] = localId;
    }

    // 第二遍补任务关系和 tag many-to-many。
    for (final item in items) {
      final localId = localIds[item.id];
      if (localId == null) continue;
      final statusRows = await db.query(
        'tasks',
        columns: ['sync_status'],
        where: 'id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (statusRows.isNotEmpty &&
          (statusRows.first['sync_status'] as String? ?? 'synced') == 'synced') {
        final related = item.relatedQuestId == null
            ? null
            : (localIds[item.relatedQuestId!] ??
                await _localId(db, 'tasks', item.relatedQuestId));
        await db.update('tasks', {'related_quest_id': related},
            where: 'id = ?', whereArgs: [localId]);
        await db.delete('task_tags', where: 'task_id = ?', whereArgs: [localId]);
        for (final tag in item.tags) {
          final tagId = await _localId(db, 'tags', tag.id);
          if (tagId != null) {
            await db.insert(
              'task_tags',
              {'task_id': localId, 'tag_id': tagId},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      }
    }
  }

  Future<void> _pullHabitLogs(Database db) async {
    final habits = await db.query(
      'habits',
      columns: ['id', 'server_id'],
      where: 'server_id IS NOT NULL AND deleted_at IS NULL',
    );
    for (final habit in habits) {
      final localHabitId = habit['id'] as int;
      final remoteHabitId = habit['server_id'] as int;
      final response = await ApiService.getHabitLogs(remoteHabitId)
          .timeout(const Duration(seconds: 15));
      final logs = response['logs'];
      if (logs is! List) continue;
      for (final raw in logs) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = item['id'] as int?;
        if (id == null) continue;
        await _upsert(db, 'habit_logs', id, {
          'habit_id': localHabitId,
          'date': item['date'] ?? '',
          'period': item['period'] ?? '',
          'duration_min': item['duration_min'] ?? 0,
          'note': item['note'] ?? '',
          'task_id': await _localId(db, 'tasks', item['task_id']),
          'created_at': _dateString(item['created_at']),
        });
      }
    }
  }

  /// 更新 synced 缓存；pending/conflict 不覆盖；remote-only 插入。
  Future<int?> _upsert(
    Database db,
    String table,
    int serverId,
    Map<String, Object?> values,
  ) async {
    final rows = await db.query(
      table,
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final local = rows.first;
      final status = local['sync_status'] as String? ?? 'synced';
      if (status == 'pending' || status == 'conflict') {
        await _markConflict(db, table, local['id'] as int);
        return local['id'] as int;
      }
      await db.update(
        table,
        {
          ...values,
          'server_id': serverId,
          if (await _hasColumn(db, table, 'sync_status'))
            'sync_status': 'synced',
          if (await _hasColumn(db, table, 'last_modified'))
            'last_modified': _now(),
        },
        where: 'id = ?',
        whereArgs: [local['id']],
      );
      return local['id'] as int;
    }

    return db.insert(table, {
      ...values,
      'server_id': serverId,
      if (await _hasColumn(db, table, 'sync_status')) 'sync_status': 'synced',
      if (await _hasColumn(db, table, 'version')) 'version': 1,
      if (await _hasColumn(db, table, 'last_modified'))
        'last_modified': _now(),
      if (await _hasColumn(db, table, 'device_id')) 'device_id': '',
    });
  }

  Future<Map<String, dynamic>?> _fetchRemote(
    Database db,
    String table,
    int serverId,
    Map<String, Object?> local,
  ) async {
    switch (table) {
      case 'tasks':
        return _taskMap(await TaskApi.getTask(serverId));
      case 'lists':
        final item =
            _first<TodoList>(await ApiService.getLists(), (e) => e.id == serverId);
        return item == null ? null : _listMap(item);
      case 'tags':
        final item =
            _first<Tag>(await ApiService.getTags(), (e) => e.id == serverId);
        return item == null ? null : _tagMap(item);
      case 'system_tags':
        return _mapById(await ApiService.getSystemTags(), serverId);
      case 'habits':
        return _mapById(await ApiService.getHabits(), serverId);
      case 'habit_logs':
        final localHabit = local['habit_id'] as int?;
        if (localHabit == null) return null;
        final remoteHabit = await _serverId(db, 'habits', localHabit);
        if (remoteHabit <= 0) return null;
        final logs = (await ApiService.getHabitLogs(remoteHabit))['logs'];
        if (logs is List) {
          for (final raw in logs) {
            if (raw is Map && raw['id'] == serverId) {
              return Map<String, dynamic>.from(raw);
            }
          }
        }
        return null;
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _normalizeRemote(
    Database db,
    String table,
    Map<String, dynamic> remote,
  ) async {
    final result = Map<String, dynamic>.from(
      _pick(remote, _fields[table] ?? const <String>[]),
    );
    if (table == 'tasks') {
      result['list_id'] = await _localId(db, 'lists', remote['list_id']);
      result['system_tag_id'] =
          await _localId(db, 'system_tags', remote['system_tag_id']);
      result['related_quest_id'] =
          await _localId(db, 'tasks', remote['related_quest_id']);
      result['is_completed'] = _boolInt(remote['is_completed']);
      result['is_milestone'] = _boolInt(remote['is_milestone']);
    } else if (table == 'habits') {
      result['system_tag_id'] =
          await _localId(db, 'system_tags', remote['system_tag_id']);
      result['generate_task'] = _boolInt(remote['generate_task']);
      result['show_checkin_dialog'] = _boolInt(remote['show_checkin_dialog']);
      result['reminder_at'] = jsonEncode(remote['reminder_at'] ?? {});
    } else if (table == 'lists') {
      result['is_inbox'] = _boolInt(remote['is_inbox']);
    } else if (table == 'habit_logs') {
      result['habit_id'] = await _localId(db, 'habits', remote['habit_id']);
      result['task_id'] = await _localId(db, 'tasks', remote['task_id']);
    }
    return result;
  }

  Future<void> _applyRemote(
    Database db,
    String table,
    int localId,
    Map<String, dynamic> remote,
  ) async {
    await db.update(
      table,
      {
        ...remote,
        'sync_status': 'synced',
        'last_modified': _now(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Map<String, Object?> _merge(
    String table,
    Map<String, Object?> local,
    Map<String, dynamic> remote,
  ) {
    final result = <String, Object?>{};
    for (final field in _fields[table] ?? const <String>[]) {
      final localValue = local[field];
      result[field] = _empty(localValue) ? remote[field] : localValue;
    }
    return result;
  }

  static const _fields = <String, List<String>>{
    'lists': ['name', 'icon', 'color', 'is_inbox'],
    'tags': ['name', 'color'],
    'system_tags': ['name', 'icon', 'color', 'dimension_key'],
    'habits': [
      'name',
      'icon',
      'color',
      'frequency',
      'target_days',
      'streak_count',
      'preferred_period',
      'system_tag_id',
      'generate_task',
      'duration_min',
      'show_checkin_dialog',
      'specific_time',
      'reminder_at',
    ],
    'tasks': [
      'list_id',
      'title',
      'description',
      'due_date',
      'due_time',
      'is_completed',
      'completed_at',
      'priority',
      'repeat_type',
      'repeat_interval',
      'repeat_days',
      'reminder_at',
      'reminder_advance_minutes',
      'system_tag_id',
      'task_type',
      'mood_before',
      'mood_after',
      'is_milestone',
      'related_quest_id',
      'obsidian_link',
      'output_level',
    ],
    'habit_logs': [
      'habit_id',
      'date',
      'period',
      'duration_min',
      'note',
      'task_id'
    ],
  };

  Future<void> _markConflict(Database db, String table, int id) async {
    if (await _hasColumn(db, table, 'sync_status')) {
      await db.update(table, {'sync_status': 'conflict'},
          where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> _removeQueue(Database db, String table, int id) => db.delete(
        'sync_queue',
        where: 'entity_type = ? AND entity_local_id = ?',
        whereArgs: [table, id],
      );

  Future<Map<String, Object?>> _row(Database db, String table, int id) async {
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('$table record not found: $id');
    return rows.first;
  }

  Future<int> _serverId(Database db, String table, int localId) async {
    if (localId <= 0) return 0;
    final rows = await db.query(
      table,
      columns: ['server_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['server_id'] as int? ?? 0);
  }

  Future<int?> _localId(Database db, String table, Object? serverId) async {
    final id = serverId is int
        ? serverId
        : int.tryParse(serverId?.toString() ?? '');
    if (id == null || id <= 0) return null;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'server_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<int?> _mapSystemTag(Database db, int? localId) async {
    if (localId == null) return null;
    final id = await _serverId(db, 'system_tags', localId);
    return id > 0 ? id : null;
  }

  Future<List<int>> _remoteTagIds(Database db, int taskId) async {
    final rows = await db.rawQuery(
      '''SELECT tags.server_id FROM task_tags
         INNER JOIN tags ON tags.id = task_tags.tag_id
         WHERE task_tags.task_id = ? AND tags.server_id IS NOT NULL''',
      [taskId],
    );
    return rows
        .map((e) => e['server_id'] as int?)
        .whereType<int>()
        .where((id) => id > 0)
        .toList();
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  void _requireCloudMode() {
    if (!DataModeManager().isCloud) {
      throw StateError(
        'SyncService only supports Cloud Data offline/sync. '
        'Local Data CRUD must not enter sync_queue.',
      );
    }
  }

  DateTime? _parseDate(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    try {
      final decoded = jsonDecode(value?.toString() ?? '{}');
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _dateString(Object? value) =>
      value?.toString().isNotEmpty == true ? value.toString() : _now();
  String _now() => DateTime.now().toUtc().toIso8601String();
  String _day(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  int _boolInt(Object? value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value == 0 ? 0 : 1;
    return 0;
  }

  bool _empty(Object? value) =>
      value == null || (value is String && value.isEmpty);

  Map<String, Object?> _pick(
          Map<String, dynamic> source, List<String> fields) =>
      {
        for (final field in fields)
          if (source.containsKey(field)) field: source[field],
      };

  T? _first<T>(Iterable<T> values, bool Function(T) match) {
    for (final value in values) {
      if (match(value)) return value;
    }
    return null;
  }

  Map<String, dynamic>? _mapById(
      Iterable<Map<String, dynamic>> values, int id) {
    for (final value in values) {
      if (value['id'] == id) return value;
    }
    return null;
  }

  Map<String, dynamic> _taskMap(Task item) => {
        'id': item.id,
        'list_id': item.listId,
        'title': item.title,
        'description': item.description,
        'due_date': item.dueDate == null ? null : _day(item.dueDate!),
        'due_time': item.dueTime,
        'is_completed': item.isCompleted,
        'completed_at': item.completedAt?.toUtc().toIso8601String(),
        'priority': item.priority,
        'repeat_type': item.repeatType,
        'repeat_interval': item.repeatInterval,
        'repeat_days': item.repeatDays,
        'reminder_at': item.reminderAt?.toUtc().toIso8601String(),
        'reminder_advance_minutes': item.reminderAdvanceMinutes,
        'system_tag_id': item.systemTagId,
        'task_type': item.taskType,
        'mood_before': item.moodBefore,
        'mood_after': item.moodAfter,
        'is_milestone': item.isMilestone,
        'related_quest_id': item.relatedQuestId,
        'obsidian_link': item.obsidianLink,
        'output_level': item.outputLevel,
      };

  Map<String, dynamic> _listMap(TodoList item) => {
        'id': item.id,
        'name': item.name,
        'icon': item.icon,
        'color': item.color,
        'is_inbox': item.isInbox,
      };

  Map<String, dynamic> _tagMap(Tag item) => {
        'id': item.id,
        'name': item.name,
        'color': item.color,
      };

  void dispose2() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
