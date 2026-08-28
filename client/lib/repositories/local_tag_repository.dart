import '../db/local_db.dart';
import '../models/tag.dart';

/// 本地普通标签仓储（内部实现，被 LocalApiService 使用）。
class LocalTagRepository {
  final _db = LocalDb();

  Future<List<Tag>> getAll() async {
    final db = await _db.database;
    final maps = await db.query('tags', orderBy: 'created_at ASC');
    return maps.map(_fromMap).toList();
  }

  Future<Tag> create({required String name, required String color}) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('tags', {
      'name': name,
      'color': color,
      'created_at': now,
      'updated_at': now,
    });
    return Tag(
      id: id,
      name: name,
      color: color,
      createdAt: DateTime.parse(now).toLocal(),
    );
  }

  Future<Tag> update({required int id, String? name, String? color}) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final updates = <String, dynamic>{'updated_at': now};
    if (name != null) updates['name'] = name;
    if (color != null) updates['color'] = color;
    await db.update('tags', updates, where: 'id = ?', whereArgs: [id]);

    final maps = await db.query(
      'tags',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) throw Exception('标签不存在');
    return _fromMap(maps.first);
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<int>> getTaskIdsByTag(int tagId) async {
    final db = await _db.database;
    final maps =
        await db.query('task_tags', where: 'tag_id = ?', whereArgs: [tagId]);
    return maps.map((m) => m['task_id'] as int).toList();
  }

  Tag _fromMap(Map<String, dynamic> map) => Tag(
        id: map['id'] as int,
        name: map['name'] as String,
        color: (map['color'] as String?) ?? '#0075de',
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}
