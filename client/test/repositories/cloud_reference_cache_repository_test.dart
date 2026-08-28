import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/cloud_cache_db.dart';
import 'package:slowlight/repositories/cloud_reference_cache_repository.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String cloudDbPath;

  const userId = 42;
  final userJson = jsonEncode({
    'id': userId,
    'username': 'reference_test',
    'email': 'reference@example.com',
    'nickname': 'Reference Test',
    'avatar': null,
    'created_at': '2026-08-21T00:00:00.000Z',
  });

  setUpAll(() async {
    final root = await useIsolatedTestDb('reference_cache');
    cloudDbPath = p.join(root, 'slowlight_cloud_cache_user_$userId.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_data': userJson});
    await CloudCacheDb().close();
    await databaseFactory.deleteDatabase(cloudDbPath);
    await DataModeManager().setCloud();
  });

  tearDown(() async {
    await CloudCacheDb().close();
    await databaseFactory.deleteDatabase(cloudDbPath);
  });

  test('Tag cache 对外暴露 server id', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('tags', {
      'server_id': 301,
      'name': 'Deep Work',
      'color': '#123456',
      'created_at': now,
      'updated_at': now,
    });

    final tags = await CloudReferenceCacheRepository().getTags();
    expect(tags, hasLength(1));
    expect(tags.single.id, 301);
    expect(tags.single.name, 'Deep Work');
  });

  test('ObservationTag cache 保留 dimension_key 与默认标记', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('system_tags', {
      'server_id': 401,
      'name': '认知',
      'icon': '🧠',
      'color': '#abcdef',
      'dimension_key': 'cognition',
      'is_default': 1,
      'created_at': now,
      'updated_at': now,
    });

    final tags = await CloudReferenceCacheRepository().getObservationTags();
    expect(tags, hasLength(1));
    expect(tags.single.id, 401);
    expect(tags.single.dimensionKey, 'cognition');
    expect(tags.single.isDefault, isTrue);
  });
}
