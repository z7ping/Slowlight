import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import 'local_feishu_config_store.dart';

/// 本机模式飞书适配器：只读 SQLite，直接调用飞书开放平台，不访问 Slowlight Server。
class LocalFeishuIntegrationService {
  static const _api = 'https://open.feishu.cn/open-apis/bitable/v1';

  Future<Map<String, dynamic>> createTemplate() async {
    final token = await _token();
    final app = await _request('POST', '$_api/apps', token,
        body: {'name': 'Slowlight 本机数据'});
    final appToken = (app['app'] as Map?)?['app_token']?.toString() ?? '';
    if (appToken.isEmpty) throw StateError('飞书未返回多维表格标识');
    final tables = <String, String>{};
    for (final definition in _definitions) {
      final data =
          await _request('POST', '$_api/apps/$appToken/tables', token, body: {
        'table': {'name': definition.name, 'fields': definition.fields}
      });
      final tableID = (data['table'] as Map?)?['table_id']?.toString() ?? '';
      if (tableID.isEmpty) throw StateError('创建${definition.name}时飞书未返回表 ID');
      tables[definition.name] = tableID;
    }
    final tableUrl = 'https://feishu.cn/base/$appToken?table=${tables['任务表']}';
    await LocalFeishuConfigStore().saveTables(tables, tableUrl: tableUrl);
    return {'message': '已创建本机飞书模板', 'bitable_url': tableUrl, 'tables': tables};
  }

  Future<Map<String, dynamic>> connect(String tableUrl) async {
    final token = await _token();
    final appToken = _appToken(tableUrl);
    if (appToken.isEmpty) throw StateError('请输入有效的飞书多维表格链接');
    final data = await _request(
        'GET', '$_api/apps/$appToken/tables?page_size=100', token);
    final remoteTables = List<Map<String, dynamic>>.from(
        ((data['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)));
    final expected = _definitions.map((item) => item.name).toSet();
    final tables = <String, String>{
      for (final table in remoteTables)
        if (expected.contains(table['name']))
          table['name'].toString(): table['table_id'].toString(),
    };
    final selected = Uri.tryParse(tableUrl)?.queryParameters['table'];
    if (!tables.containsKey('任务表') && selected != null && selected.isNotEmpty)
      tables['任务表'] = selected;
    if (tables['任务表'] == null) throw StateError('未找到任务表；请先创建本机飞书模板或选择包含任务表的链接');
    await LocalFeishuConfigStore().saveTables(tables, tableUrl: tableUrl);
    return {
      'message': '已绑定本机飞书表格',
      'tables': tables,
      'all_tables': remoteTables
    };
  }

  Future<Map<String, dynamic>> syncAll() async {
    final results = <String, int>{};
    final errors = <String>[];
    for (final definition in _definitions) {
      try {
        results[definition.name] = await _sync(definition);
      } catch (error) {
        errors.add('${definition.name}: $error');
      }
    }
    return {
      'message': errors.isEmpty ? '本机数据已同步到飞书' : '本机数据已部分同步到飞书',
      'results': results,
      'errors': errors
    };
  }

  Future<Map<String, dynamic>> syncTasks() => _single('任务表');
  Future<Map<String, dynamic>> syncSessions() => _single('番茄钟表');
  Future<Map<String, dynamic>> syncTags() => _single('标签表');
  Future<Map<String, dynamic>> syncReminders() => _single('休息提醒表');

  Future<Map<String, dynamic>> _single(String name) async {
    final count =
        await _sync(_definitions.firstWhere((item) => item.name == name));
    return {'message': '$name已同步到飞书', 'synced': count};
  }

  Future<int> _sync(_TableDefinition definition) async {
    final context = await _context(definition.name);
    final rows = await definition.rows(await LocalDb().database);
    for (final row in rows) {
      final id = row['id'];
      if (id is int) {
        await _upsert(
            token: context.token,
            appToken: context.appToken,
            tableID: context.tables[definition.name]!,
            entityType: definition.entityType,
            entityID: id,
            fields: definition.toFields(row));
      }
    }
    return rows.length;
  }

  Future<_Context> _context(String requiredTable) async {
    final config = await LocalFeishuConfigStore().load();
    final tables = <String, String>{
      for (final entry in ((config['tables'] as Map?) ?? const {}).entries)
        '${entry.key}': '${entry.value}',
    };
    final appToken = _appToken(config['table_url']?.toString() ?? '');
    if (appToken.isEmpty || tables[requiredTable] == null)
      throw StateError('请先创建或绑定包含$requiredTable的本机飞书模板');
    return _Context(await _token(), appToken, tables);
  }

  Future<String> _token() async {
    final store = LocalFeishuConfigStore();
    final config = await store.load();
    final secret = await store.readSecret();
    final appID = config['app_id']?.toString() ?? '';
    if (appID.isEmpty || secret == null || secret.isEmpty)
      throw StateError('请先保存本机飞书应用标识和应用密钥');
    final response = await http.post(
        Uri.parse(
            'https://open.feishu.cn/open-apis/auth/v3/app_access_token/internal'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'app_id': appID, 'app_secret': secret}));
    final data = _body(response);
    final token = data['app_access_token']?.toString() ?? '';
    if (response.statusCode != 200 || token.isEmpty)
      throw StateError('获取飞书访问令牌失败：${data['msg'] ?? '未知错误'}');
    return token;
  }

  Future<void> _upsert(
      {required String token,
      required String appToken,
      required String tableID,
      required String entityType,
      required int entityID,
      required Map<String, dynamic> fields}) async {
    final db = await LocalDb().database;
    await _ensureMappings(db);
    final existing = await db.query('feishu_record_mappings',
        where: 'entity_type = ? AND entity_id = ? AND table_id = ?',
        whereArgs: [entityType, entityID, tableID],
        limit: 1);
    final recordID =
        existing.isEmpty ? null : existing.first['record_id']?.toString();
    final method = recordID == null ? 'POST' : 'PUT';
    final url = recordID == null
        ? '$_api/apps/$appToken/tables/$tableID/records'
        : '$_api/apps/$appToken/tables/$tableID/records/$recordID';
    try {
      final data = await _request(method, url, token, body: {'fields': fields});
      final returnedID =
          recordID ?? (data['record'] as Map?)?['record_id']?.toString();
      if (returnedID == null || returnedID.isEmpty)
        throw StateError('飞书未返回记录 ID');
      await db.insert(
          'feishu_record_mappings',
          {
            'entity_type': entityType,
            'entity_id': entityID,
            'table_id': tableID,
            'record_id': returnedID,
            'updated_at': DateTime.now().toUtc().toIso8601String()
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    } on StateError catch (error) {
      if (recordID == null || !error.toString().contains('404')) rethrow;
      await db.delete('feishu_record_mappings',
          where: 'entity_type = ? AND entity_id = ? AND table_id = ?',
          whereArgs: [entityType, entityID, tableID]);
      await _upsert(
          token: token,
          appToken: appToken,
          tableID: tableID,
          entityType: entityType,
          entityID: entityID,
          fields: fields);
    }
  }

  Future<void> _ensureMappings(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS feishu_record_mappings (
      entity_type TEXT NOT NULL, entity_id INTEGER NOT NULL, table_id TEXT NOT NULL,
      record_id TEXT NOT NULL, updated_at TEXT NOT NULL,
      PRIMARY KEY (entity_type, entity_id, table_id)
    )
  ''');

  Future<Map<String, dynamic>> _request(String method, String url, String token,
      {Map<String, dynamic>? body}) async {
    final request = http.Request(method, Uri.parse(url))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await request.send());
    final data = _body(response);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (data['code'] != null && data['code'] != 0))
      throw StateError('${response.statusCode} ${data['msg'] ?? '飞书请求失败'}');
    final payload = data['data'];
    return payload is Map ? Map<String, dynamic>.from(payload) : data;
  }

  Map<String, dynamic> _body(http.Response response) =>
      Map<String, dynamic>.from(response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map);

  String _appToken(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    final index = segments.indexOf('base');
    return index >= 0 && segments.length > index + 1 ? segments[index + 1] : '';
  }
}

class _Context {
  const _Context(this.token, this.appToken, this.tables);
  final String token;
  final String appToken;
  final Map<String, String> tables;
}

class _TableDefinition {
  const _TableDefinition(
      this.name, this.entityType, this.fields, this.rows, this.toFields);
  final String name;
  final String entityType;
  final List<Map<String, dynamic>> fields;
  final Future<List<Map<String, Object?>>> Function(Database db) rows;
  final Map<String, dynamic> Function(Map<String, Object?> row) toFields;
}

final _definitions = <_TableDefinition>[
  _TableDefinition(
      '任务表',
      'task',
      _fields(['标题', '描述', '清单', '完成', '优先级', '截止日期', 'Slowlight本地ID']),
      (db) => db.rawQuery(
          'SELECT t.*, l.name AS list_name FROM tasks t LEFT JOIN lists l ON l.id = t.list_id WHERE t.deleted_at IS NULL'),
      (row) => _withID(row, {
            '标题': row['title'],
            '描述': row['description'] ?? '',
            '清单': row['list_name'] ?? '',
            '完成': row['is_completed'] == 1,
            '优先级': row['priority'] ?? 'none',
            '截止日期': row['due_date'] ?? ''
          })),
  _TableDefinition(
      '子任务表',
      'subtask',
      _fields(['标题', '任务ID', '完成', '排序', 'Slowlight本地ID']),
      (db) => db.query('subtasks'),
      (row) => _withID(row, {
            '标题': row['title'],
            '任务ID': row['task_id'],
            '完成': row['is_completed'] == 1,
            '排序': row['sort_order'] ?? 0
          })),
  _TableDefinition(
      '清单表',
      'list',
      _fields(['名称', '颜色', '图标', '排序', 'Slowlight本地ID']),
      (db) => db.query('lists', where: 'deleted_at IS NULL'),
      (row) => _withID(row, {
            '名称': row['name'],
            '颜色': row['color'] ?? '',
            '图标': row['icon'] ?? '',
            '排序': row['sort_order'] ?? 0
          })),
  _TableDefinition(
      '习惯表',
      'habit',
      _fields(['名称', '图标', '颜色', '频率', '目标天数', '连续天数', 'Slowlight本地ID']),
      (db) => db.query('habits', where: 'deleted_at IS NULL'),
      (row) => _withID(row, {
            '名称': row['name'],
            '图标': row['icon'] ?? '',
            '颜色': row['color'] ?? '',
            '频率': row['frequency'] ?? '',
            '目标天数': row['target_days'] ?? 0,
            '连续天数': row['streak_count'] ?? 0
          })),
  _TableDefinition(
      '习惯记录表',
      'habit_log',
      _fields(['习惯ID', '日期', '时段', '时长(分钟)', '备注', 'Slowlight本地ID']),
      (db) => db.query('habit_logs'),
      (row) => _withID(row, {
            '习惯ID': row['habit_id'],
            '日期': row['date'] ?? '',
            '时段': row['period'] ?? '',
            '时长(分钟)': row['duration_min'] ?? 0,
            '备注': row['note'] ?? ''
          })),
  _TableDefinition(
      '番茄钟表',
      'session',
      _fields(['类型', '开始时间', '结束时间', '时长(秒)', '设备', '关联任务ID', 'Slowlight本地ID']),
      (db) => db.query('work_sessions'),
      (row) => _withID(row, {
            '类型': row['session_type'] ?? 'work',
            '开始时间': row['started_at'] ?? '',
            '结束时间': row['ended_at'] ?? '',
            '时长(秒)': row['duration_sec'] ?? 0,
            '设备': row['device'] ?? '',
            '关联任务ID': row['task_id'] ?? 0
          })),
  _TableDefinition(
      '休息提醒表',
      'reminder_session',
      _fields(['类型', '开始时间', '结束时间', '时长(秒)', '跳过休息', '设备', 'Slowlight本地ID']),
      (db) => db.query('reminder_sessions'),
      (row) => _withID(row, {
            '类型': row['type'],
            '开始时间': row['started_at'],
            '结束时间': row['ended_at'] ?? '',
            '时长(秒)': row['duration_seconds'] ?? 0,
            '跳过休息': row['skipped'] == 1,
            '设备': row['device'] ?? ''
          })),
  _TableDefinition(
      '标签表',
      'tag',
      _fields(['名称', '颜色', 'Slowlight本地ID']),
      (db) => db.query('tags'),
      (row) => _withID(row, {'名称': row['name'], '颜色': row['color'] ?? ''})),
];

List<Map<String, dynamic>> _fields(List<String> names) => [
      for (final name in names)
        {
          'field_name': name,
          'type': name == '完成' || name == '跳过休息'
              ? 7
              : name.contains('ID') ||
                      name == '排序' ||
                      name.contains('时长') ||
                      name.contains('天数')
                  ? 2
                  : 1,
        }
    ];
Map<String, dynamic> _withID(
        Map<String, Object?> row, Map<String, dynamic> fields) =>
    {...fields, 'Slowlight本地ID': row['id']};
