import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_behavior_event_schema.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/models/dimension.dart';
import 'package:slowlight/repositories/observation_tag_repository.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/local_dimension_analytics.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String dbPath;

  setUpAll(() async {
    final root = await useIsolatedTestDb('product_core');
    dbPath = p.join(root, 'slowlight_offline.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalBehaviorEventSchema.resetForTest();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    await DataModeManager().setLocal();
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    LocalBehaviorEventSchema.resetForTest();
  });

  test('自定义观察标签归属固定维度，不会生成额外人生维度', () async {
    final tags = ObservationTagRepository();
    final running = await tags.create(
      name: '跑步',
      icon: '🏃',
      color: '#52C41A',
      dimensionKey: DimensionKey.body.name,
    );
    final reading = await tags.create(
      name: '阅读',
      icon: '📚',
      color: '#1890FF',
      dimensionKey: DimensionKey.cognition.name,
    );

    await LocalBehaviorEventSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('behavior_events', {
      'event_type': 'task_completed',
      'entity_type': 'task',
      'entity_id': 1001,
      'system_tag_id': running.id,
      'duration_min': 0,
      'occurred_at': now,
      'metadata': '{}',
      'is_deleted': 0,
      'created_at': now,
    });
    await db.insert('behavior_events', {
      'event_type': 'session_ended',
      'entity_type': 'session',
      'entity_id': 1002,
      'system_tag_id': running.id,
      'duration_min': 25,
      'occurred_at': now,
      'metadata': '{}',
      'is_deleted': 0,
      'created_at': now,
    });
    await db.insert('behavior_events', {
      'event_type': 'habit_checked',
      'entity_type': 'habit',
      'entity_id': 1003,
      'system_tag_id': reading.id,
      'duration_min': 0,
      'occurred_at': now,
      'metadata': '{}',
      'is_deleted': 0,
      'created_at': now,
    });

    final summary = await LocalDimensionAnalytics().getSummary();
    final dimensions = summary['dimensions'] as List<dynamic>;
    expect(dimensions, hasLength(4));

    final body = dimensions
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['key'] == DimensionKey.body.name);
    final cognition = dimensions
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['key'] == DimensionKey.cognition.name);
    expect(body['value'], 2);
    expect(cognition['value'], 1);
  });

  test('Observation / Reflection 是独立第一方数据，可被后续 Review 读取', () async {
    final repository = ReflectionRepository();
    await repository.create(
      entryType: 'observation',
      dimensionKey: DimensionKey.body.name,
      content: '今天睡得不够，下午明显容易走神。',
      context: {'source': 'test'},
    );
    await repository.create(
      questionId: 'focus_imbalance_body',
      content: '这周少运动主要是因为晚上都在处理临时事情。',
    );

    final recent = await repository.recent(limit: 10);
    expect(recent, hasLength(2));
    expect(recent.first.questionId, 'focus_imbalance_body');
    expect(recent.last.dimensionKey, DimensionKey.body.name);
    expect(recent.last.entryType, 'observation');
  });
}
