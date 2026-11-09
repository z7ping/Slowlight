import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/services/local_feishu_config_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('修改凭据不丢表格映射，修改飞书目标必须清除旧映射', () async {
    final store = LocalFeishuConfigStore();
    await store.save(
      appId: 'cli_old',
      appSecret: 'secret1',
      tableUrl: 'https://feishu.cn/base/old',
    );
    await store.saveTables(
      {'任务表': 'table_old'},
      tableUrl: 'https://feishu.cn/base/old',
    );

    await store.save(
      appId: 'cli_old',
      appSecret: 'secret2',
      tableUrl: 'https://feishu.cn/base/old',
    );
    expect((await store.load())['tables'], {'任务表': 'table_old'});

    await store.save(
      appId: 'cli_old',
      appSecret: 'secret3',
      tableUrl: 'https://feishu.cn/base/new',
    );
    expect((await store.load())['tables'], isEmpty);

    await store.saveTables(
      {'任务表': 'table_new'},
      tableUrl: 'https://feishu.cn/base/new',
    );
    await store.save(
      appId: 'cli_different',
      appSecret: 'secret4',
      tableUrl: 'https://feishu.cn/base/new',
    );
    expect((await store.load())['tables'], isEmpty);
  });
}
