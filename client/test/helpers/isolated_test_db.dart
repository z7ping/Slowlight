import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:slowlight/db/cloud_cache_db.dart';
import 'package:slowlight/db/local_db.dart';

/// 为当前测试套件分配独立临时目录，并重定向 LocalDb / CloudCacheDb 的落盘位置。
///
/// sqflite_ffi 的 getDatabasesPath() 固定解析到 `<cwd>/.dart_tool/...`，
/// flutter test 并发套件与真实 App 会共享同一批数据库文件并互相覆盖，
/// 因此每个套件必须通过本助手隔离。返回值是该套件专属的数据库目录。
Future<String> useIsolatedTestDb(String suiteName) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // Widget Test 使用虚拟时钟；独立 worker 的查询会等待真实事件循环。
  // 同线程 FFI 仍执行真实 SQLite，避免查询锁超时残留到宿主销毁之后。
  databaseFactory = databaseFactoryFfiNoIsolate;

  final dir = Directory(
    p.join(Directory.systemTemp.path, 'slowlight_test_db', suiteName),
  );
  await dir.create(recursive: true);

  LocalDb.debugDatabasePathOverride = p.join(dir.path, 'slowlight_offline.db');
  CloudCacheDb.debugDatabasesDirOverride = dir.path;
  return dir.path;
}
