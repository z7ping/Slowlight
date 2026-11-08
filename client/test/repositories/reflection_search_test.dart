import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/db/local_product_core_schema.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('p09_reflection_search');
  });
  setUp(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(LocalDb.debugDatabasePathOverride!);
    await DataModeManager().setLocal();
    await LocalProductCoreSchema.ensureReady();
  });
  tearDown(() async => LocalDb().close());

  test('P09 Local 可找出 recent(100) 以外的完整历史记录', () async {
    final db = await LocalDb().database;
    for (var i=1; i<=125; i++) {
      await db.insert('reflections', {
        'entry_type': 'observation',
        'content': '早期原始观察 找到我 $i',
        'context_json': '{}',
        'created_at': '2023-01-01T00:00:00.000Z',
        'updated_at': '2023-01-01T00:00:00.000Z',
      });
    }
    for (var i=1; i<=115; i++) {
      await db.insert('reflections', {
        'entry_type': 'observation',
        'content': '不匹配的较新记录 $i',
        'context_json': '{}',
        'created_at': '2026-11-08T00:00:00.000Z',
        'updated_at': '2026-11-08T00:00:00.000Z',
      });
    }
    final result = await ReflectionRepository().searchContent('找到我');
    expect(result.complete, isTrue);
    expect(result.entries, hasLength(125));
    expect(result.entries.every((e) => e.content.contains('找到我')),
        isTrue);
  });

  test('P09 关键词特殊字符字面匹配而非 SQL 通配', () async {
    final db = await LocalDb().database;
    for (final term in ['100%', '100x', 'a_b', 'aXb']) {
      await db.insert('reflections', {
        'entry_type': 'observation',
        'content': '搜索字面 $term',
        'context_json': '{}',
        'created_at': '2026-11-08T00:00:00.000Z',
        'updated_at': '2026-11-08T00:00:00.000Z',
      });
    }
    expect((await ReflectionRepository().searchContent('100%'))
        .entries.single.content, '搜索字面 100%');
    expect((await ReflectionRepository().searchContent('a_b'))
        .entries.single.content, '搜索字面 a_b');
  });
}
