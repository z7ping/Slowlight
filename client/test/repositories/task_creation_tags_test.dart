import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/db/local_product_core_schema.dart';
import 'package:slowlight/repositories/local_task_repository.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(await useIsolatedTestDb('task_creation_tags'), 'slowlight_offline.db');
  });

  setUp(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('创建任务的 canonical 多标签与历史 system_tag_id 独立持久化', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '工作', 'created_at': now, 'updated_at': now,
    });
    final tagIds = <int>[];
    for (final label in ['工作', '复盘']) {
      tagIds.add(await db.insert('tags', {
        'name': label, 'created_at': now, 'updated_at': now,
      }));
    }
    final legacyId = await db.insert('system_tags', {
      'name': '历史分类', 'icon': '旧', 'color': '#888888',
      'created_at': now, 'updated_at': now,
    });
    final repo = LocalTaskRepository();
    final created = await repo.create(
      listId: listId, title: '整理迭代', tagIds: tagIds, systemTagId: legacyId,
    );
    expect(created.systemTagId, legacyId);
    expect(created.tags.map((tag) => tag.id).toSet(), tagIds.toSet());

    final reopened = await repo.getById(created.id);
    expect(reopened?.systemTagId, legacyId);
    expect(reopened?.tags.map((tag) => tag.id).toSet(), tagIds.toSet());

    final cleared = await repo.update(
      id: created.id, listId: listId, title: '整理迭代',
      tagIds: const [], systemTagId: legacyId,
    );
    expect(cleared.tags, isEmpty);
    expect(cleared.systemTagId, legacyId);
  });
}
