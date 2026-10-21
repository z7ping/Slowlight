import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/local_list_repository.dart';
import 'package:slowlight/services/local_api_service.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('local_list_repository'),
      'slowlight_offline.db',
    );
  });
  setUp(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });
  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('缺失收集箱时补齐一次并保留原有清单', () async {
    final repo = LocalListRepository();
    final work = await repo.create(name: '工作', icon: '💼');
    final inbox = await repo.ensureInbox();
    final repeated = await repo.ensureInbox();

    expect(inbox.isInbox, isTrue);
    expect(inbox.name, '收集箱');
    expect(inbox.id, repeated.id);
    final lists = await repo.getAll();
    expect(lists, hasLength(2));
    expect(lists.first.id, inbox.id);
    expect(lists.last.id, work.id);
    expect(lists.last.name, '工作');
  });

  test('已有收集箱不被重建或覆盖名称', () async {
    final repo = LocalListRepository();
    final customized = await repo.create(
      name: '我的收集箱',
      icon: '🗃',
      isInbox: true,
    );
    final inbox = await repo.ensureInbox();
    expect(inbox.id, customized.id);
    expect(inbox.name, '我的收集箱');
    expect(await repo.getAll(), hasLength(1));
  });

  test('快速添加始终进入真正的收集箱，不误用第一个清单', () async {
    final repo = LocalListRepository();
    await repo.create(name: '工作');
    final task = await LocalApiService().quickAddToInbox('记录想法');
    final inbox = (await repo.getAll()).singleWhere((list) => list.isInbox);
    expect(task.listId, inbox.id);
    expect(task.title, '记录想法');
    final repeated = await LocalApiService().quickAddToInbox('第二条');
    expect(repeated.listId, inbox.id);
    expect((await repo.getAll()).where((list) => list.isInbox), hasLength(1));
  });
}
