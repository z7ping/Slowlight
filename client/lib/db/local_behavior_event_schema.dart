import 'package:sqflite/sqflite.dart';

import 'local_db.dart';

/// Local Data Mode 的统一 BehaviorEvent schema 与 SQLite triggers。
///
/// 事件由数据库 trigger 从 Task / HabitLog / WorkSession 状态变化派生，
/// 保证领域写入与事件写入处于同一 SQLite 事务中，避免调用方漏记事件。
class LocalBehaviorEventSchema {
  static bool _ready = false;

  static Future<void> ensureReady() async {
    if (_ready) return;
    final db = await LocalDb().database;
    await ensureOn(db);
    _ready = true;
  }

  static Future<void> ensureOn(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS behavior_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER DEFAULT 0,
        event_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        system_tag_id INTEGER,
        duration_min INTEGER DEFAULT 0,
        occurred_at TEXT NOT NULL,
        metadata TEXT DEFAULT '{}',
        is_deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_behavior_events_occurred ON behavior_events(occurred_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_behavior_events_type_occurred ON behavior_events(event_type, occurred_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_behavior_events_tag_occurred ON behavior_events(system_tag_id, occurred_at)',
    );

    // 先回填历史数据，保证升级后 Review/Analytics 不只看到“今天以后”的行为。
    await db.execute('''
      INSERT INTO behavior_events (
        event_type, entity_type, entity_id, system_tag_id,
        duration_min, occurred_at, metadata, is_deleted, created_at
      )
      SELECT
        'task_completed', 'task', t.id, t.system_tag_id,
        0, t.completed_at, '{}',
        CASE WHEN t.deleted_at IS NULL THEN 0 ELSE 1 END,
        t.completed_at
      FROM tasks t
      WHERE t.is_completed = 1
        AND t.completed_at IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM behavior_events e
          WHERE e.event_type = 'task_completed'
            AND e.entity_type = 'task'
            AND e.entity_id = t.id
        )
    ''');
    await db.execute('''
      INSERT INTO behavior_events (
        event_type, entity_type, entity_id, system_tag_id,
        duration_min, occurred_at, metadata, is_deleted, created_at
      )
      SELECT
        'habit_checked', 'habit', hl.habit_id, h.system_tag_id,
        COALESCE(hl.duration_min, 0), hl.created_at,
        '{"date":"' || hl.date || '"}',
        CASE WHEN h.deleted_at IS NULL THEN 0 ELSE 1 END,
        hl.created_at
      FROM habit_logs hl
      INNER JOIN habits h ON h.id = hl.habit_id
      WHERE NOT EXISTS (
        SELECT 1 FROM behavior_events e
        WHERE e.event_type = 'habit_checked'
          AND e.entity_type = 'habit'
          AND e.entity_id = hl.habit_id
          AND e.metadata = '{"date":"' || hl.date || '"}'
      )
    ''');
    await db.execute('''
      INSERT INTO behavior_events (
        event_type, entity_type, entity_id, system_tag_id,
        duration_min, occurred_at, metadata, created_at
      )
      SELECT
        'session_ended', 'session', s.id, s.system_tag_id,
        CASE WHEN s.duration_sec / 60 < 1 THEN 1 ELSE s.duration_sec / 60 END,
        s.ended_at, '{}', s.ended_at
      FROM work_sessions s
      WHERE s.session_type = 'work'
        AND s.ended_at IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM behavior_events e
          WHERE e.event_type = 'session_ended'
            AND e.entity_type = 'session'
            AND e.entity_id = s.id
        )
    ''');

    // Task：完成时产生事件；取消完成时撤销对应完成事件。
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_task_completed_event
      AFTER UPDATE OF is_completed ON tasks
      WHEN NEW.is_completed = 1 AND OLD.is_completed = 0
      BEGIN
        INSERT INTO behavior_events (
          event_type, entity_type, entity_id, system_tag_id,
          duration_min, occurred_at, metadata, created_at
        ) VALUES (
          'task_completed', 'task', NEW.id, NEW.system_tag_id,
          0, COALESCE(NEW.completed_at, CURRENT_TIMESTAMP), '{}',
          COALESCE(NEW.completed_at, CURRENT_TIMESTAMP)
        );
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_task_uncompleted_event
      AFTER UPDATE OF is_completed ON tasks
      WHEN NEW.is_completed = 0 AND OLD.is_completed = 1
      BEGIN
        DELETE FROM behavior_events
        WHERE event_type = 'task_completed'
          AND entity_type = 'task'
          AND entity_id = NEW.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_task_deleted_event
      AFTER UPDATE OF deleted_at ON tasks
      WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
      BEGIN
        UPDATE behavior_events SET is_deleted = 1
        WHERE entity_type = 'task' AND entity_id = NEW.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_task_hard_deleted_event
      AFTER DELETE ON tasks
      BEGIN
        DELETE FROM behavior_events
        WHERE entity_type = 'task' AND entity_id = OLD.id;
      END
    ''');

    // Habit：每次打卡对应一个 habit_checked；取消某日打卡只撤销该日事件。
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_habit_checked_event
      AFTER INSERT ON habit_logs
      BEGIN
        INSERT INTO behavior_events (
          event_type, entity_type, entity_id, system_tag_id,
          duration_min, occurred_at, metadata, created_at
        ) VALUES (
          'habit_checked', 'habit', NEW.habit_id,
          (SELECT system_tag_id FROM habits WHERE id = NEW.habit_id),
          COALESCE(NEW.duration_min, 0), NEW.created_at,
          '{"date":"' || NEW.date || '"}', NEW.created_at
        );
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_habit_unchecked_event
      AFTER DELETE ON habit_logs
      BEGIN
        DELETE FROM behavior_events
        WHERE event_type = 'habit_checked'
          AND entity_type = 'habit'
          AND entity_id = OLD.habit_id
          AND metadata = '{"date":"' || OLD.date || '"}';
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_habit_deleted_event
      AFTER UPDATE OF deleted_at ON habits
      WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
      BEGIN
        UPDATE behavior_events SET is_deleted = 1
        WHERE entity_type = 'habit' AND entity_id = NEW.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_habit_hard_deleted_event
      AFTER DELETE ON habits
      BEGIN
        DELETE FROM behavior_events
        WHERE entity_type = 'habit' AND entity_id = OLD.id;
      END
    ''');

    // WorkSession：无论手动结束还是启动新会话自动结束，只要 ended_at 从空变为有值，
    // work session 就产生一个 session_ended 事件。
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_work_session_ended_event
      AFTER UPDATE OF ended_at ON work_sessions
      WHEN OLD.ended_at IS NULL
        AND NEW.ended_at IS NOT NULL
        AND NEW.session_type = 'work'
      BEGIN
        INSERT INTO behavior_events (
          event_type, entity_type, entity_id, system_tag_id,
          duration_min, occurred_at, metadata, created_at
        ) VALUES (
          'session_ended', 'session', NEW.id, NEW.system_tag_id,
          CASE WHEN NEW.duration_sec / 60 < 1 THEN 1 ELSE NEW.duration_sec / 60 END,
          NEW.ended_at, '{}', NEW.ended_at
        );
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_work_session_deleted_event
      AFTER DELETE ON work_sessions
      BEGIN
        DELETE FROM behavior_events
        WHERE entity_type = 'session' AND entity_id = OLD.id;
      END
    ''');
  }

  /// 测试/数据库重建后允许重新执行 ensure。
  static void resetForTest() {
    _ready = false;
  }
}
