import '../db/local_db.dart';
import '../models/todo_list.dart';

/// 本地清单仓储（内部实现，被 LocalApiService 使用）。
/// Exact transaction receipt for the original list and its live task IDs.
/// An expired toast cannot invent a restoration by creating replacement IDs.
class LocalListDeletionReceipt {
  final int listId;
  final String deletedAt;
  final List<int> taskIds;

  const LocalListDeletionReceipt({
    required this.listId,
    required this.deletedAt,
    required this.taskIds,
  });
}

class LocalListRepository {
  final _db = LocalDb();

  Future<List<TodoList>> getAll() async {
    final db = await _db.database;
    final maps = await db.query(
      'lists',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, created_at ASC, id ASC',
    );
    return maps.map(_fromMap).toList();
  }

  /// 首次进入或升级时补齐唯一的默认收集箱，不修改已有清单。
  Future<TodoList> ensureInbox() async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'lists',
        where: 'is_inbox = 1 AND deleted_at IS NULL',
        limit: 1,
      );
      if (existing.isNotEmpty) return _fromMap(existing.first);

      final now = DateTime.now().toUtc().toIso8601String();
      final values = <String, dynamic>{
        'name': '收集箱',
        'icon': '📥',
        'color': '#909399',
        'sort_order': -1,
        'is_inbox': 1,
        'created_at': now,
        'updated_at': now,
      };
      final id = await txn.insert('lists', values);
      return _fromMap({...values, 'id': id});
    });
  }

  Future<TodoList?> getById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'lists',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _fromMap(maps.first);
  }

  Future<TodoList> create({
    required String name,
    String icon = '📋',
    String color = '#1890ff',
    bool isInbox = false,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('lists', {
      'name': name,
      'icon': icon,
      'color': color,
      'is_inbox': isInbox ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
    return TodoList(
      id: id,
      name: name,
      icon: icon,
      color: color,
      isInbox: isInbox,
      createdAt: DateTime.parse(now).toLocal(),
    );
  }

  Future<TodoList> update({
    required int id,
    String? name,
    String? icon,
    String? color,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final updates = <String, dynamic>{'updated_at': now};
    if (name != null) updates['name'] = name;
    if (icon != null) updates['icon'] = icon;
    if (color != null) updates['color'] = color;

    await db.update('lists', updates, where: 'id = ?', whereArgs: [id]);
    final result = await getById(id);
    if (result == null) throw Exception('清单不存在');
    return result;
  }

  Future<void> delete(int id, {
    bool deleteTasks = false,
    int? expectedTaskCount,
  }) async {
    await _deleteInternal(id,
      deleteTasks: deleteTasks,
      expectedTaskCount: expectedTaskCount,
      undoable: false);
  }

  Future<LocalListDeletionReceipt> deleteWithUndo(
    int id, {required int expectedTaskCount}
  ) async {
    final receipt = await _deleteInternal(id,
      deleteTasks: true,
      expectedTaskCount: expectedTaskCount,
      undoable: true);
    return receipt!;
  }

  Future<LocalListDeletionReceipt?> _deleteInternal(int id, {
    required bool deleteTasks,
    required int? expectedTaskCount,
    required bool undoable,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction<LocalListDeletionReceipt?>((txn) async {
      final rows = await txn.query(
        'lists',
        columns: ['id', 'is_inbox'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id], limit: 1,
      );
      if (rows.isEmpty) throw StateError('清单不存在，请刷新后重试');
      if (rows.single['is_inbox'] == 1) {
        throw StateError('默认收集箱不可删除');
      }
      final active = await txn.query(
        'tasks', columns: ['id'],
        where: 'list_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
        orderBy: 'id ASC',
      );
      final count = active.length;
      if (expectedTaskCount != null && expectedTaskCount != count) {
        throw StateError('清单任务范围已变化，请重新核对删除范围');
      }
      if (count > 0 && !deleteTasks) {
        throw StateError('清单下有任务，删除任务须明确确认');
      }
      if (deleteTasks) {
        final changed = await txn.update('tasks',
          {'deleted_at': now, 'updated_at': now},
          where: 'list_id = ? AND deleted_at IS NULL',
          whereArgs: [id]);
        if (changed != count) throw StateError('清单任务范围已变化');
      }
      final deleted = await txn.update('lists',
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ? AND deleted_at IS NULL AND is_inbox = 0',
        whereArgs: [id]);
      if (deleted != 1) throw StateError('清单状态已变化，删除未确认');
      return undoable ? LocalListDeletionReceipt(
        listId: id, deletedAt: now,
        taskIds: active.map((row) => row['id'] as int).toList(growable: false),
      ) : null;
    });
  }

  /// Restore the very same IDs, only while their tombstone still matches
  /// this deletion. A changed task/list causes full rollback, not partial undo.
  Future<void> undoDelete(LocalListDeletionReceipt receipt) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final restoredList = await txn.update('lists',
        {'deleted_at': null, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ? AND deleted_at = ?',
        whereArgs: [receipt.listId, receipt.deletedAt]);
      if (restoredList != 1) {
        throw StateError('清单已发生变化，原删除不能撤销');
      }
      for (var start = 0; start < receipt.taskIds.length; start += 400) {
        final stop = start + 400 > receipt.taskIds.length
            ? receipt.taskIds.length : start + 400;
        final chunk = receipt.taskIds.sublist(start, stop);
        final slots = List.filled(chunk.length, '?').join(',');
        final restored = await txn.update('tasks',
          {'deleted_at': null,
           'updated_at': DateTime.now().toUtc().toIso8601String()},
          where: 'id IN ($slots) AND list_id = ? AND deleted_at = ?',
          whereArgs: [...chunk, receipt.listId, receipt.deletedAt]);
        if (restored != chunk.length) {
          throw StateError('部分任务已变化，原删除不能撤销');
        }
      }
    });
  }

  TodoList _fromMap(Map<String, dynamic> map) {
    return TodoList(
      id: map['id'] as int,
      serverId: map['server_id'] as int?,
      name: map['name'] as String,
      icon: (map['icon'] as String?) ?? '📋',
      color: (map['color'] as String?) ?? '#1890ff',
      isInbox: (map['is_inbox'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}
