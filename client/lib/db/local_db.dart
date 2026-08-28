import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// 本地 SQLite 数据库单例
class LocalDb {
  static final LocalDb _instance = LocalDb._internal();
  factory LocalDb() => _instance;
  LocalDb._internal();

  Database? _db;

  /// 测试隔离用：非 null 时替代默认数据库文件路径。
  /// flutter test 并发套件与真实 App 共享默认路径会互相覆盖，必须各自隔离。
  @visibleForTesting
  static String? debugDatabasePathOverride;

  /// 获取数据库实例（懒初始化）
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (debugDatabasePathOverride != null) {
      return await openDatabase(
        debugDatabasePathOverride!,
        version: 14,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'slowlight_offline.db');

    return await openDatabase(
      path,
      version: 14,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE lists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT NOT NULL,
        icon TEXT DEFAULT '📋',
        color TEXT DEFAULT '#1890ff',
        sort_order INTEGER DEFAULT 0,
        is_inbox INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        list_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT DEFAULT '',
        due_date TEXT,
        due_time TEXT,
        is_completed INTEGER DEFAULT 0,
        completed_at TEXT,
        priority TEXT DEFAULT 'none',
        sort_order INTEGER DEFAULT 0,
        repeat_type TEXT DEFAULT 'none',
        repeat_interval INTEGER DEFAULT 1,
        repeat_days TEXT DEFAULT '',
        reminder_at TEXT,
        reminder_advance_minutes INTEGER DEFAULT 0,
        system_tag_id INTEGER,
        task_type TEXT DEFAULT 'daily',
        mood_before INTEGER DEFAULT 0,
        mood_after INTEGER DEFAULT 0,
        is_milestone INTEGER DEFAULT 0,
        related_quest_id INTEGER,
        obsidian_link TEXT DEFAULT '',
        output_level TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (list_id) REFERENCES lists(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE subtasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        task_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        is_completed INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT NOT NULL,
        color TEXT DEFAULT '#0075de',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE task_tags (
        task_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (task_id, tag_id),
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE system_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT NOT NULL,
        dimension_key TEXT,
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE habits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT NOT NULL,
        icon TEXT DEFAULT '✅',
        color TEXT DEFAULT '#52c41a',
        frequency TEXT DEFAULT 'daily',
        target_days INTEGER DEFAULT 0,
        streak_count INTEGER DEFAULT 0,
        preferred_period TEXT DEFAULT '',
        system_tag_id INTEGER,
        generate_task INTEGER DEFAULT 0,
        duration_min INTEGER DEFAULT 0,
        show_checkin_dialog INTEGER DEFAULT 0,
        specific_time TEXT DEFAULT '',
        reminder_at TEXT DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE habit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        habit_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        period TEXT DEFAULT '',
        duration_min INTEGER DEFAULT 0,
        note TEXT DEFAULT '',
        task_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_tasks_list_id ON tasks(list_id)');
    await db.execute('CREATE INDEX idx_tasks_due_date ON tasks(due_date)');
    await db.execute('CREATE INDEX idx_subtasks_task_id ON subtasks(task_id)');
    await db.execute('CREATE INDEX idx_habit_logs_habit_id ON habit_logs(habit_id)');
    await db.execute('CREATE INDEX idx_habit_logs_date ON habit_logs(date)');

    await db.execute('''
      CREATE TABLE reminder_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        type TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_seconds INTEGER DEFAULT 0,
        skipped INTEGER DEFAULT 0,
        device TEXT DEFAULT '',
        synced INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_reminder_sessions_synced ON reminder_sessions(synced)');
    await db.execute('CREATE INDEX idx_reminder_sessions_date ON reminder_sessions(started_at)');

    await db.execute('''
      CREATE TABLE reminder_config (
        id INTEGER PRIMARY KEY DEFAULT 1,
        work_minutes INTEGER DEFAULT 25,
        micro_rest_seconds INTEGER DEFAULT 20,
        long_rest_minutes INTEGER DEFAULT 5,
        micro_rests_before_long INTEGER DEFAULT 2,
        lock_screen INTEGER DEFAULT 0,
        lock_screen_mode TEXT DEFAULT 'window',
        notify_before_seconds INTEGER DEFAULT 30,
        auto_loop INTEGER DEFAULT 1,
        auto_start_on_launch INTEGER DEFAULT 1,
        micro_rest_strict INTEGER DEFAULT 0,
        long_rest_strict INTEGER DEFAULT 0,
        allow_postpone_micro INTEGER DEFAULT 1,
        allow_postpone_long INTEGER DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE reminder_daily_stats (
        date TEXT PRIMARY KEY,
        total_work_seconds INTEGER DEFAULT 0,
        total_rest_seconds INTEGER DEFAULT 0,
        session_count INTEGER DEFAULT 0,
        skip_count INTEGER DEFAULT 0
      )
    ''');

    for (final table in ['lists', 'tasks', 'subtasks', 'tags', 'system_tags', 'habits', 'habit_logs']) {
      await db.execute('ALTER TABLE $table ADD COLUMN version INTEGER DEFAULT 1');
      await db.execute("ALTER TABLE $table ADD COLUMN sync_status TEXT DEFAULT 'synced'");
      await db.execute("ALTER TABLE $table ADD COLUMN last_modified TEXT DEFAULT ''");
      await db.execute("ALTER TABLE $table ADD COLUMN device_id TEXT DEFAULT ''");
    }

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_local_id INTEGER NOT NULL,
        entity_server_id INTEGER,
        operation TEXT NOT NULL,
        payload TEXT,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_sync_queue_entity ON sync_queue(entity_type, entity_local_id)');
    await db.execute('CREATE INDEX idx_sync_queue_retry ON sync_queue(retry_count)');
    await db.execute('CREATE INDEX idx_tasks_sync_status ON tasks(sync_status)');
    await db.execute('CREATE INDEX idx_habits_sync_status ON habits(sync_status)');

    await _createWorkSessionsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS reminder_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          server_id INTEGER,
          type TEXT NOT NULL,
          started_at TEXT NOT NULL,
          ended_at TEXT,
          duration_seconds INTEGER DEFAULT 0,
          skipped INTEGER DEFAULT 0,
          device TEXT DEFAULT '',
          synced INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_reminder_sessions_synced ON reminder_sessions(synced)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_reminder_sessions_date ON reminder_sessions(started_at)');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS reminder_config (
          id INTEGER PRIMARY KEY DEFAULT 1,
          work_minutes INTEGER DEFAULT 25,
          micro_rest_seconds INTEGER DEFAULT 20,
          long_rest_minutes INTEGER DEFAULT 5,
          micro_rests_before_long INTEGER DEFAULT 2,
          lock_screen INTEGER DEFAULT 0,
          notify_before_seconds INTEGER DEFAULT 10,
          auto_loop INTEGER DEFAULT 1,
          auto_start_on_launch INTEGER DEFAULT 1,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS reminder_daily_stats (
          date TEXT PRIMARY KEY,
          total_work_seconds INTEGER DEFAULT 0,
          total_rest_seconds INTEGER DEFAULT 0,
          session_count INTEGER DEFAULT 0,
          skip_count INTEGER DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 3) {
      final syncTables = ['lists', 'tasks', 'subtasks', 'tags', 'system_tags', 'habits', 'habit_logs'];
      for (final table in syncTables) {
        await db.execute('ALTER TABLE $table ADD COLUMN version INTEGER DEFAULT 1');
        await db.execute("ALTER TABLE $table ADD COLUMN sync_status TEXT DEFAULT 'synced'");
        await db.execute("ALTER TABLE $table ADD COLUMN last_modified TEXT DEFAULT ''");
        await db.execute("ALTER TABLE $table ADD COLUMN device_id TEXT DEFAULT ''");
      }

      await db.execute('''
        CREATE TABLE sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          entity_type TEXT NOT NULL,
          entity_local_id INTEGER NOT NULL,
          entity_server_id INTEGER,
          operation TEXT NOT NULL,
          payload TEXT,
          retry_count INTEGER DEFAULT 0,
          last_error TEXT DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_sync_queue_entity ON sync_queue(entity_type, entity_local_id)');
      await db.execute('CREATE INDEX idx_sync_queue_retry ON sync_queue(retry_count)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tasks_sync_status ON tasks(sync_status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_habits_sync_status ON habits(sync_status)');
    }

    if (oldVersion < 4) {
      await db.execute("ALTER TABLE habits ADD COLUMN specific_time TEXT DEFAULT ''");
      await db.execute("ALTER TABLE habits ADD COLUMN reminder_at TEXT DEFAULT '{}'");
    }

    if (oldVersion < 5) {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='reminder_config'");
      if (tables.isNotEmpty) {
        await db.execute("ALTER TABLE reminder_config ADD COLUMN auto_loop INTEGER DEFAULT 1");
        await db.execute("ALTER TABLE reminder_config ADD COLUMN auto_start_on_launch INTEGER DEFAULT 1");
      } else {
        await db.execute('''
          CREATE TABLE reminder_config (
            id INTEGER PRIMARY KEY DEFAULT 1,
            work_minutes INTEGER DEFAULT 25,
            micro_rest_seconds INTEGER DEFAULT 20,
            long_rest_minutes INTEGER DEFAULT 5,
            micro_rests_before_long INTEGER DEFAULT 2,
            lock_screen INTEGER DEFAULT 0,
            notify_before_seconds INTEGER DEFAULT 10,
            auto_loop INTEGER DEFAULT 1,
            auto_start_on_launch INTEGER DEFAULT 1,
            updated_at TEXT NOT NULL
          )
        ''');
      }
    }

    if (oldVersion < 6) {
      await db.execute('''
        DELETE FROM system_tags WHERE id NOT IN (
          SELECT MIN(id) FROM system_tags GROUP BY name
        )
      ''');
    }

    if (oldVersion < 7) {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='reminder_config'");
      if (tables.isNotEmpty) {
        await db.execute("ALTER TABLE reminder_config ADD COLUMN micro_rest_seconds INTEGER DEFAULT 20");
        await db.execute("ALTER TABLE reminder_config ADD COLUMN long_rest_minutes INTEGER DEFAULT 5");
        await db.execute("ALTER TABLE reminder_config ADD COLUMN micro_rests_before_long INTEGER DEFAULT 2");
        await db.execute("UPDATE reminder_config SET work_minutes = 25 WHERE work_minutes = 50");
        await db.execute("UPDATE reminder_config SET notify_before_seconds = 10 WHERE notify_before_seconds = 60");
      }
    }

    if (oldVersion < 8) {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='reminder_config'");
      if (tables.isNotEmpty) {
        await db.execute("ALTER TABLE reminder_config ADD COLUMN lock_screen_mode TEXT DEFAULT 'window'");
        await db.execute("ALTER TABLE reminder_config ADD COLUMN micro_rest_strict INTEGER DEFAULT 0");
        await db.execute("ALTER TABLE reminder_config ADD COLUMN long_rest_strict INTEGER DEFAULT 0");
        await db.execute("ALTER TABLE reminder_config ADD COLUMN allow_postpone_micro INTEGER DEFAULT 1");
        await db.execute("ALTER TABLE reminder_config ADD COLUMN allow_postpone_long INTEGER DEFAULT 1");
        await db.execute("UPDATE reminder_config SET notify_before_seconds = 30 WHERE notify_before_seconds = 10");
      }
    }

    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS reminder_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          server_id INTEGER,
          type TEXT NOT NULL,
          started_at TEXT NOT NULL,
          ended_at TEXT,
          duration_seconds INTEGER DEFAULT 0,
          skipped INTEGER DEFAULT 0,
          device TEXT DEFAULT '',
          synced INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_reminder_sessions_synced ON reminder_sessions(synced)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_reminder_sessions_date ON reminder_sessions(started_at)');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS reminder_config (
          id INTEGER PRIMARY KEY DEFAULT 1,
          work_minutes INTEGER DEFAULT 25,
          micro_rest_seconds INTEGER DEFAULT 20,
          long_rest_minutes INTEGER DEFAULT 5,
          micro_rests_before_long INTEGER DEFAULT 2,
          lock_screen INTEGER DEFAULT 0,
          notify_before_seconds INTEGER DEFAULT 10,
          auto_loop INTEGER DEFAULT 1,
          auto_start_on_launch INTEGER DEFAULT 1,
          lock_screen_mode TEXT DEFAULT 'window',
          micro_rest_strict INTEGER DEFAULT 0,
          long_rest_strict INTEGER DEFAULT 0,
          allow_postpone_micro INTEGER DEFAULT 1,
          allow_postpone_long INTEGER DEFAULT 1,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS reminder_daily_stats (
          date TEXT PRIMARY KEY,
          total_work_seconds INTEGER DEFAULT 0,
          total_rest_seconds INTEGER DEFAULT 0,
          session_count INTEGER DEFAULT 0,
          skip_count INTEGER DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 11) {
      final columns = await db.rawQuery('PRAGMA table_info(habits)');
      final hasShowCheckinDialog =
          columns.any((column) => column['name'] == 'show_checkin_dialog');
      if (!hasShowCheckinDialog) {
        await db.execute(
            "ALTER TABLE habits ADD COLUMN show_checkin_dialog INTEGER DEFAULT 0");
      }
    }

    if (oldVersion < 12) {
      final columns = await db.rawQuery('PRAGMA table_info(tasks)');
      final names = columns.map((column) => column['name']).toSet();
      if (!names.contains('is_milestone')) {
        await db.execute(
            'ALTER TABLE tasks ADD COLUMN is_milestone INTEGER DEFAULT 0');
      }
      if (!names.contains('related_quest_id')) {
        await db.execute('ALTER TABLE tasks ADD COLUMN related_quest_id INTEGER');
      }
      if (!names.contains('obsidian_link')) {
        await db.execute(
            "ALTER TABLE tasks ADD COLUMN obsidian_link TEXT DEFAULT ''");
      }
      if (!names.contains('output_level')) {
        await db.execute(
            "ALTER TABLE tasks ADD COLUMN output_level TEXT DEFAULT ''");
      }
    }

    if (oldVersion < 13) {
      await _createWorkSessionsTable(db);
    }

    if (oldVersion < 14) {
      final columns = await db.rawQuery('PRAGMA table_info(system_tags)');
      final hasDimensionKey =
          columns.any((column) => column['name'] == 'dimension_key');
      if (!hasDimensionKey) {
        await db.execute('ALTER TABLE system_tags ADD COLUMN dimension_key TEXT');
      }
    }
  }

  Future<void> _createWorkSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_type TEXT NOT NULL,
        task_id INTEGER,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_sec INTEGER DEFAULT 0,
        device TEXT DEFAULT '',
        system_tag_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_sessions_started_at ON work_sessions(started_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_sessions_active ON work_sessions(ended_at)');
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('work_sessions');
    await db.delete('habit_logs');
    await db.delete('task_tags');
    await db.delete('subtasks');
    await db.delete('tasks');
    await db.delete('tags');
    await db.delete('system_tags');
    await db.delete('habits');
    await db.delete('lists');
  }
}