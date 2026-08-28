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
    await _applyObservationTagDimensions(db, changes['system_tags']);

    final deleted = changes['deleted'];
    if (deleted is Map) {
      for (final entry in deleted.entries) {
        final table = entry.key.toString();
        final ids = entry.value;
        if (ids is! List) continue;
        for (final rawId in ids) {
          final serverId = rawId is int ? rawId : int.tryParse(rawId.toString());
          if (serverId != null) {
            await _applyDelete(db, table, serverId);
          }
        }
      }
    }

    // 只有整批变化全部成功应用后才推进 cursor。中途任何数据库异常都会直接抛出，
    // 保留旧 cursor，下一轮重新获取同一批变化，避免漏 tombstone。
    final serverTime = changes['server_time']?.toString();
    if (serverTime != null && serverTime.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cursorKey, serverTime);
    }
  }

  Future<void> _applyObservationTagDimensions(Database db, dynamic rawTags) async {
    if (rawTags is! List ||
        !await _hasColumn(db, 'system_tags', 'dimension_key')) {
      return;
    }
    final hasSyncStatus = await _hasColumn(db, 'system_tags', 'sync_status');
    for (final raw in rawTags) {
      if (raw is! Map) continue;
      final serverId = raw['id'] is int
          ? raw['id'] as int
          : int.tryParse(raw['id']?.toString() ?? '');
      if (serverId == null) continue;
      final dimensionKey = raw['dimension_key']?.toString() ?? '';

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

  Future<void> _applyDelete(Database db, String table, int serverId) async {
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

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }
}
