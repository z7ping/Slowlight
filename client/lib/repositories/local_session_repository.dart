import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';

/// Local Data Mode 下的工作/休息会话仓储。
///
/// 会话数据完全保存在本地 SQLite，不依赖 Slowlight Server。
/// work_sessions schema 由 LocalDb 统一维护。
class LocalSessionRepository {
  final LocalDb _localDb = LocalDb();

  Future<Database> _db() => _localDb.database;

  Future<Map<String, dynamic>> startSession(
    String sessionType, {
    int? taskId,
    String device = 'desktop',
  }) async {
    if (!const {'work', 'break', 'long_break'}.contains(sessionType)) {
      throw ArgumentError.value(sessionType, 'sessionType', '不支持的会话类型');
    }

    final db = await _db();
    final now = DateTime.now().toUtc();
    late int id;

    await db.transaction((txn) async {
      // 与服务端保持一致：启动新会话时自动结束已有活跃会话。
      final active = await txn.query(
        'work_sessions',
        where: 'ended_at IS NULL',
        orderBy: 'started_at DESC',
        limit: 1,
      );
      if (active.isNotEmpty) {
        final row = active.first;
        final startedAt = DateTime.parse(row['started_at'] as String);
        final durationSec = _durationSeconds(startedAt, now);
        final resolvedSystemTagId = await _resolveSystemTagId(
          txn,
          currentSystemTagId: row['system_tag_id'] as int?,
          taskId: row['task_id'] as int?,
        );
        await txn.update(
          'work_sessions',
          {
            'ended_at': now.toIso8601String(),
            'duration_sec': durationSec,
            'system_tag_id': resolvedSystemTagId,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }

      id = await txn.insert('work_sessions', {
        'session_type': sessionType,
        'task_id': taskId,
        'started_at': now.toIso8601String(),
        'ended_at': null,
        'duration_sec': 0,
        'device': device,
        'system_tag_id': null,
        'created_at': now.toIso8601String(),
      });
    });

    final session = await _getById(db, id);
    return {'message': '会话已开始', 'session': session};
  }

  Future<Map<String, dynamic>> endSession({int? systemTagId}) async {
    final db = await _db();
    final now = DateTime.now().toUtc();
    late int sessionId;
    late int durationSec;

    await db.transaction((txn) async {
      final active = await txn.query(
        'work_sessions',
        where: 'ended_at IS NULL',
        orderBy: 'started_at DESC',
        limit: 1,
      );
      if (active.isEmpty) {
        throw StateError('没有进行中的会话');
      }

      final row = active.first;
      sessionId = row['id'] as int;
      final startedAt = DateTime.parse(row['started_at'] as String);
      durationSec = _durationSeconds(startedAt, now);
      final resolvedSystemTagId = await _resolveSystemTagId(
        txn,
        currentSystemTagId: row['system_tag_id'] as int?,
        taskId: row['task_id'] as int?,
        fallbackSystemTagId: systemTagId,
      );

      await txn.update(
        'work_sessions',
        {
          'ended_at': now.toIso8601String(),
          'duration_sec': durationSec,
          'system_tag_id': resolvedSystemTagId,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });

    final session = await _getById(db, sessionId);
    return {
      'message': '会话已结束',
      'session': session,
      'duration': durationSec,
    };
  }

  Future<Map<String, dynamic>> getActiveSession() async {
    final db = await _db();
    final rows = await db.query(
      'work_sessions',
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return {'active': false, 'config': _defaultConfig()};
    }
    return {
      'active': true,
      'session': _toJson(rows.first),
      'config': _defaultConfig(),
    };
  }

  Future<Map<String, dynamic>> getSessionStats({String period = 'week'}) async {
    final db = await _db();
    final rows = await db.query(
      'work_sessions',
      where: 'ended_at IS NOT NULL',
      orderBy: 'started_at ASC',
    );

    final now = DateTime.now();
    DateTime? since;
    switch (period) {
      case 'month':
        since = DateTime(now.year, now.month - 1, now.day, now.hour, now.minute);
        break;
      case 'all':
        since = null;
        break;
      default:
        since = now.subtract(const Duration(days: 7));
    }
    final cutoff = since;

    return _buildStats(
      rows.where((row) {
        if (cutoff == null) return true;
        final started = DateTime.parse(row['started_at'] as String).toLocal();
        return !started.isBefore(cutoff);
      }).toList(),
    );
  }

  Future<Map<String, dynamic>> getTodaySessionStats() async {
    final db = await _db();
    final rows = await db.query(
      'work_sessions',
      where: 'ended_at IS NOT NULL',
      orderBy: 'started_at ASC',
    );
    final now = DateTime.now();
    final todayRows = rows.where((row) {
      final started = DateTime.parse(row['started_at'] as String).toLocal();
      return started.year == now.year &&
          started.month == now.month &&
          started.day == now.day;
    }).toList();
    return _buildStats(todayRows);
  }

  Future<int?> _resolveSystemTagId(
    DatabaseExecutor db, {
    int? currentSystemTagId,
    int? taskId,
    int? fallbackSystemTagId,
  }) async {
    // 与服务端 resolveSessionSystemTag + EndSession 的优先级一致：
    // 会话已有标签 > 关联任务标签 > 本次结束时显式选择。
    if (currentSystemTagId != null) return currentSystemTagId;
    if (taskId != null) {
      final tasks = await db.query(
        'tasks',
        columns: ['system_tag_id'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [taskId],
        limit: 1,
      );
      if (tasks.isNotEmpty && tasks.first['system_tag_id'] != null) {
        return tasks.first['system_tag_id'] as int?;
      }
    }
    return fallbackSystemTagId;
  }

  int _durationSeconds(DateTime startedAt, DateTime endedAt) =>
      endedAt.difference(startedAt).inSeconds.clamp(0, 1 << 31).toInt();

  Map<String, dynamic> _buildStats(List<Map<String, Object?>> rows) {
    var totalWorkSeconds = 0;
    var totalBreakSeconds = 0;
    var workCount = 0;
    var breakCount = 0;
    final daily = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final type = row['session_type'] as String? ?? 'work';
      final duration = row['duration_sec'] as int? ?? 0;
      final started = DateTime.parse(row['started_at'] as String).toLocal();
      final date = '${started.year.toString().padLeft(4, '0')}-'
          '${started.month.toString().padLeft(2, '0')}-'
          '${started.day.toString().padLeft(2, '0')}';
      final day = daily.putIfAbsent(
        date,
        () => {
          'date': date,
          'work_seconds': 0,
          'break_seconds': 0,
          'work_count': 0,
          'break_count': 0,
        },
      );

      if (type == 'work') {
        totalWorkSeconds += duration;
        workCount++;
        day['work_seconds'] = (day['work_seconds'] as int) + duration;
        day['work_count'] = (day['work_count'] as int) + 1;
      } else {
        totalBreakSeconds += duration;
        breakCount++;
        day['break_seconds'] = (day['break_seconds'] as int) + duration;
        day['break_count'] = (day['break_count'] as int) + 1;
      }
    }

    return {
      'total_work_seconds': totalWorkSeconds,
      'total_break_seconds': totalBreakSeconds,
      'work_count': workCount,
      'break_count': breakCount,
      'daily': daily.values.toList(),
    };
  }

  Future<Map<String, dynamic>> _getById(Database db, int id) async {
    final rows = await db.query(
      'work_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('会话不存在');
    return _toJson(rows.first);
  }

  Map<String, dynamic> _toJson(Map<String, Object?> row) => {
        'id': row['id'],
        'session_type': row['session_type'],
        'task_id': row['task_id'],
        'started_at': row['started_at'],
        'ended_at': row['ended_at'],
        'duration_seconds': row['duration_sec'] ?? 0,
        'device': row['device'] ?? '',
        'system_tag_id': row['system_tag_id'],
        'created_at': row['created_at'],
      };

  Map<String, dynamic> _defaultConfig() => {
        'work_minutes': 25,
        'break_minutes': 5,
        'long_break_minutes': 15,
        'sessions_before_long': 4,
        'lock_screen': false,
      };
}
