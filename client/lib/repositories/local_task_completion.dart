import '../models/task.dart';
import '../db/local_db.dart';
import 'local_task_repository.dart';

/// LocalTaskRepository 的“取消完成”语义。
extension LocalTaskCompletion on LocalTaskRepository {
  Future<Task> uncomplete(int id) async {
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'tasks',
      {
        'is_completed': 0,
        'completed_at': null,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    final result = await getById(id);
    if (result == null) throw Exception('取消完成任务失败');
    return result;
  }
}
