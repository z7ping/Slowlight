import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/db/local_product_core_schema.dart';
import 'package:slowlight/repositories/tag_links_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('tag_links_repository'),
      'slowlight_offline.db',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
    FlutterSecureStorage.setMockInitialValues({});
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    await DataModeManager().setLocal();
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('四类记录共用 canonical tags，添加、去重、清空均可读回', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '工作',
      'created_at': now,
      'updated_at': now,
    });
    final tags = <int>[];
    for (final name in ['阅读', '工作']) {
      tags.add(await db.insert('tags', {
        'name': name,
        'created_at': now,
        'updated_at': now,
      }));
    }
    final taskId = await db.insert('tasks', {
      'list_id': listId, 'title': '整理资料',
      'created_at': now, 'updated_at': now,
    });
    final habitId = await db.insert('habits', {
      'name': '读书', 'created_at': now, 'updated_at': now,
    });
    final sessionId = await db.insert('work_sessions', {
      'session_type': 'work', 'started_at': now, 'created_at': now,
    });
    final reflectionId = await db.insert('reflections', {
      'entry_type': 'observation', 'content': '今天记录',
      'created_at': now, 'updated_at': now,
    });

    final repo = TagLinksRepository();
    for (final (entity, id) in [
      (TagLinkedEntity.task, taskId),
      (TagLinkedEntity.habit, habitId),
      (TagLinkedEntity.session, sessionId),
      (TagLinkedEntity.observation, reflectionId),
    ]) {
      expect(await repo.getFor(entity, id), isEmpty);
      final saved = await repo.replaceFor(entity, id, [tags[0], tags[1], tags[0]]);
      expect(saved.map((tag) => tag.id).toSet(), tags.toSet());
      final read = await repo.getFor(entity, id);
      expect(read.map((tag) => tag.id).toSet(), tags.toSet());
      expect(await repo.replaceFor(entity, id, []), isEmpty);
      expect(await repo.getFor(entity, id), isEmpty);
    }
  });

  test('无效标签或不存在记录不会破坏已有关系', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final tagId = await db.insert('tags', {
      'name': '观察', 'created_at': now, 'updated_at': now,
    });
    final habitId = await db.insert('habits', {
      'name': '晨读', 'created_at': now, 'updated_at': now,
    });
    final repo = TagLinksRepository();
    await repo.replaceFor(TagLinkedEntity.habit, habitId, [tagId]);
    await expectLater(
      repo.replaceFor(TagLinkedEntity.habit, habitId, [999999]),
      throwsStateError,
    );
    await expectLater(
      repo.replaceFor(TagLinkedEntity.habit, 999999, []),
      throwsStateError,
    );
    await expectLater(
      repo.replaceFor(TagLinkedEntity.habit, habitId, [0]),
      throwsArgumentError,
    );
    await expectLater(
      repo.replaceFor(TagLinkedEntity.habit, habitId, List.filled(65, tagId)),
      throwsArgumentError,
    );
    expect(
      (await repo.getFor(TagLinkedEntity.habit, habitId)).single.id,
      tagId,
    );

    await db.update('habits', {'deleted_at': now},
        where: 'id = ?', whereArgs: [habitId]);
    await expectLater(
      repo.getFor(TagLinkedEntity.habit, habitId),
      throwsStateError,
    );
  });

  test('观察与反思共用关系表', () async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('reflections', {
      'entry_type': 'reflection', 'content': '反思',
      'created_at': now, 'updated_at': now,
    });
    final tagId = await db.insert('tags', {
      'name': '复盘', 'created_at': now, 'updated_at': now,
    });
    final repo = TagLinksRepository();
    await repo.replaceFor(TagLinkedEntity.reflection, id, [tagId]);
    expect((await repo.getFor(TagLinkedEntity.observation, id)).single.id, tagId);
  });
}
