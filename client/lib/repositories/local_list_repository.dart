import '../db/local_db.dart';
import '../models/todo_list.dart';

/// 本地清单仓储（内部实现，被 LocalApiService 使用）。
class LocalListRepository {
  final _db = LocalDb();

  Future<List<TodoList>> getAll() async {
    final db = await _db.database;
    final maps = await db.query(
      'lists',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, created_at ASC',
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

  Future<void> delete(int id) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'lists',
      {'deleted_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
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
