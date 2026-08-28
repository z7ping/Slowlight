import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../services/auth_service.dart';

/// Cloud Data Mode 专用的离线缓存数据库。
///
/// 与 Local Data 物理隔离，并按云端用户 ID 分库，避免：
/// - Cloud Pull 数据泄漏到 Local Data Mode；
/// - 不同云端账号复用彼此的 cache / sync_queue / sync_intents。
class CloudCacheDb {
  static final CloudCacheDb _instance = CloudCacheDb._();
  factory CloudCacheDb() => _instance;
  CloudCacheDb._();

  Database? _db;
  int? _accountId;

  /// 测试隔离用：非 null 时替代默认数据库目录（文件名仍按账号生成）。
  @visibleForTesting
  static String? debugDatabasesDirOverride;

  int? get currentAccountId => _accountId;

  Future<Database> get database async {
    final user = await AuthService.getUser();
    if (user == null || user.id <= 0) {
      throw StateError('Cloud cache requires an authenticated cloud user');
    }

    if (_db != null && _accountId == user.id) return _db!;

    await close();
    _accountId = user.id;
    _db = await _open(user.id);
    return _db!;
  }

  Future<Database> _open(int accountId) async {
    final dbPath = debugDatabasesDirOverride ?? await getDatabasesPath();
    final path = join(dbPath, 'slowlight_cloud_cache_user_$accountId.db');
    return openDatabase(
      path,
      version: 3,
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
        deleted_at TEXT,
        version INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'synced',
        last_modified TEXT DEFAULT '',
        device_id TEXT DEFAULT ''
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
        version INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'synced',
        last_modified TEXT DEFAULT '',
        device_id TEXT DEFAULT '',
        FOREIGN KEY (list_id) REFERENCES lists(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        name TEXT NOT NULL,
        color TEXT DEFAULT '#0075de',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'synced',
        last_modified TEXT DEFAULT '',
        device_id TEXT DEFAULT ''
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
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        dimension_key TEXT DEFAULT '',
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'synced',
        last_modified TEXT DEFAULT '',
        device_id TEXT DEFAULT ''
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
        deleted_at TEXT,
        version INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'synced',
        last_modified TEXT DEFAULT '',
        device_id TEXT DEFAULT ''
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
        version INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'synced',
        last_modified TEXT DEFAULT '',
        device_id TEXT DEFAULT '',
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
      )
    ''');

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

    await _createSyncIntents(db);
    await _createReflections(db);

    await db.execute(
        'CREATE INDEX idx_cloud_tasks_list_id ON tasks(list_id)');
    await db.execute(
        'CREATE INDEX idx_cloud_tasks_sync_status ON tasks(sync_status)');
    await db.execute(
        'CREATE INDEX idx_cloud_habits_sync_status ON habits(sync_status)');
    await db.execute(
        'CREATE INDEX idx_cloud_habit_logs_habit_id ON habit_logs(habit_id)');
    await db.execute(
        'CREATE INDEX idx_cloud_sync_queue_entity ON sync_queue(entity_type, entity_local_id)');
    await db.execute(
        'CREATE INDEX idx_cloud_sync_queue_retry ON sync_queue(retry_count)');
    await db.execute(
        'CREATE UNIQUE INDEX idx_cloud_lists_server_id ON lists(server_id) WHERE server_id IS NOT NULL');
    await db.execute(
        'CREATE UNIQUE INDEX idx_cloud_tasks_server_id ON tasks(server_id) WHERE server_id IS NOT NULL');
    await db.execute(
        'CREATE UNIQUE INDEX idx_cloud_tags_server_id ON tags(server_id) WHERE server_id IS NOT NULL');
    await db.execute(
        'CREATE UNIQUE INDEX idx_cloud_system_tags_server_id ON system_tags(server_id) WHERE server_id IS NOT NULL');
    await db.execute(
        'CREATE UNIQUE INDEX idx_cloud_habits_server_id ON habits(server_id) WHERE server_id IS NOT NULL');
    await db.execute(
        'CREATE UNIQUE INDEX idx_cloud_habit_logs_server_id ON habit_logs(server_id) WHERE server_id IS NOT NULL');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSyncIntents(db);
    }
    if (oldVersion < 3) {
      await _createReflections(db);
    }
  }

  Future<void> _createSyncIntents(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_intents (
        entity_type TEXT NOT NULL,
        entity_local_id INTEGER NOT NULL,
        intent TEXT NOT NULL,
        value TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, entity_local_id, intent)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_sync_intents_entity '
      'ON sync_intents(entity_type, entity_local_id)',
    );
  }

  Future<void> _createReflections(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reflections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        entry_type TEXT NOT NULL DEFAULT 'reflection',
        question_id TEXT,
        dimension_key TEXT,
        content TEXT NOT NULL,
        context_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cloud_reflections_server_id '
      'ON reflections(server_id) WHERE server_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_reflections_created_at '
      'ON reflections(created_at DESC)',
    );
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _accountId = null;
  }
}
