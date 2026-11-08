import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'sync_remote_api.dart';

/// 应用服务端权威增量变化，并维护 Pull 游标。
///
/// 普通多实体 Pull 负责完整实体 upsert；这里负责两类必须具有权威语义的变化：
/// - tombstone：远端显式删除；
/// - ObservationTag.dimension_key：产品核心维度映射，不能在旧同步链路中丢失。
class SyncIncrementalPull {
  static const cursorKey = 'slowlight_sync_pull_cursor';
  static const _entityCollections = <String>{
    'lists', 'tags', 'system_tags', 'habits', 'tasks', 'habit_logs',
  };
  static const _deletedCollections = <String>{
    'lists', 'tags', 'system_tags', 'habits', 'tasks', 'habit_logs',
  };

  final int? accountId;

  const SyncIncrementalPull({this.accountId});

  String get _cursorKey =>
      accountId == null ? cursorKey : '${cursorKey}_user_$accountId';

  Future<void> applyDeleted(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    final since = prefs.getString(_cursorKey);
    final changes = await SyncRemoteApi.getChanges(since: since);
    await applyChanges(db, changes);
  }

  Future<void> applyChanges(
    Database db,
    Map<String, dynamic> changes,
  ) async {
    // The server guarantees a complete window. Missing collections and
    // malformed tombstones are NOT empty changes: advancing the cursor would
    // skip those remote deletes forever.
    final rawTime = changes['server_time'];
    final nextTime = rawTime is String && 
            RegExp(r'(Z|[+-]\\d{2}:\\d{2})$').hasMatch(rawTime)
        ? DateTime.tryParse(rawTime)?.toUtc()
        : null;
    if (nextTime == null) {
      throw const FormatException('同步变更缺少有效 server_time');
    }
    for (final name in _entityCollections) {
      if (changes[name] is! List) {
        throw FormatException('同步变更缺少完整 $name 列表');
      }
    }
    final rawTags = changes['system_tags'] as List;
    for (final raw in rawTags) {
      if (raw is! Map ||
          raw['id'] is! int ||
          (raw['id'] as int) <= 0 ||
          raw['dimension_key'] is! String) {
        throw const FormatException('同步观察标签增量格式错误');
      }
    }

    final deleted = changes['deleted'];
    if (deleted is! Map) {
      throw const FormatException('同步变更缺少删除清单');
    }
    for (final name in _deletedCollections) {
      final ids = deleted[name];
      if (ids is! List ||
          ids.any((id) => id is! int || id <= 0)) {
        throw FormatException('同步删除清单 $name 格式错误');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final priorCursor = prefs.getString(_cursorKey);
    if (priorCursor != null) {
      final previous = DateTime.tryParse(priorCursor)?.toUtc();
      if (previous == null || nextTime.isBefore(previous)) {
        throw const FormatException('同步变更游标无效或发生回退');
      }
    }

    // Apply tags and tombstones atomically: partial SQLite changes without a
    // cursor update must not leak into an otherwise successful Cloud Pull.
    await db.transaction((txn) async {
      await _applyObservationTagDimensions(txn, rawTags);
      for (final name in _deletedCollections) {
        for (final id in deleted[name] as List) {
          await _applyDelete(txn, name, id as int);
        }
      }
    });

    // Only after a complete, validated and committed batch may we move the
    // account-scoped cursor. A failed preferences write leaves the old cursor
    // and safely replays idempotent local changes on the next pull.
    await prefs.setString(_cursorKey, rawTime);
  }

  Future<void> _applyObservationTagDimensions(DatabaseExecutor db, List rawTags) async {
    if (!await _hasColumn(db, 'system_tags', 'dimension_key')) {
      return;
    }
    final hasSyncStatus = await _hasColumn(db, 'system_tags', 'sync_status');
    for (final raw in rawTags) {
      final serverId = raw['id'] as int;
      final dimensionKey = raw['dimension_key'] as String;

      final localRows = await db.query(
        'system_tags',
        columns: [
          'id',
          'dimension_key',
          if (hasSyncStatus) 'sync_status',
        ],
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1,
      );
      if (localRows.isEmpty) continue;

      final local = localRows.first;
      final localValue = local['dimension_key']?.toString() ?? '';
      final status = hasSyncStatus
          ? local['sync_status']?.toString() ?? 'synced'
          : 'synced';

      // 本地有尚未同步的修改时，远端增量不能静默覆盖用户动作。
      if (status == 'pending' || status == 'conflict') {
        if (hasSyncStatus && localValue != dimensionKey) {
          await db.update(
            'system_tags',
            {'sync_status': 'conflict'},
            where: 'id = ?',
            whereArgs: [local['id']],
          );
        }
        continue;
      }

      await db.update(
        'system_tags',
        {'dimension_key': dimensionKey},
        where: 'server_id = ?',
        whereArgs: [serverId],
      );
    }
  }

  Future<void> _applyDelete(DatabaseExecutor db, String table, int serverId) async {
    const supported = {
      'lists',
      'tags',
      'system_tags',
      'habits',
      'tasks',
      'habit_logs',
    };
    if (!supported.contains(table)) return;

    final rows = await db.query(
      table,
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final localId = row['id'] as int;
    final status = row['sync_status'] as String? ?? 'synced';

    if (status == 'pending' || status == 'conflict') {
      if (await _hasColumn(db, table, 'sync_status')) {
        await db.update(
          table,
          {'sync_status': 'conflict'},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
      return;
    }

    switch (table) {
      case 'tasks':
      case 'lists':
      case 'habits':
        await db.update(
          table,
          {
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            if (await _hasColumn(db, table, 'sync_status'))
              'sync_status': 'synced',
          },
          where: 'id = ?',
          whereArgs: [localId],
        );
        break;
      case 'tags':
        await db.delete('task_tags', where: 'tag_id = ?', whereArgs: [localId]);
        await db.delete('tags', where: 'id = ?', whereArgs: [localId]);
        break;
      case 'system_tags':
        await db.update(
          'tasks',
          {'system_tag_id': null},
          where: 'system_tag_id = ?',
          whereArgs: [localId],
        );
        await db.update(
          'habits',
          {'system_tag_id': null},
          where: 'system_tag_id = ?',
          whereArgs: [localId],
        );
        await db.delete('system_tags', where: 'id = ?', whereArgs: [localId]);
        break;
      case 'habit_logs':
        await db.delete('habit_logs', where: 'id = ?', whereArgs: [localId]);
        break;
    }
  }

  Future<bool> _hasColumn(DatabaseExecutor db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }
}
