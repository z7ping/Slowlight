import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/services/data_mode_manager.dart';

void main() {
  setUp(() {
    DataModeManager().resetForTesting();
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
  });

  tearDown(() {
    DataModeManager().resetForTesting();
  });

  test('首次显式切到云端必须持久化，不可因默认值相同而跳过', () async {
    final manager = DataModeManager();
    // 内存默认 cloud，但历史偏好仍是 local；登录成功显式选择云端须覆盖历史值。
    await manager.setCloud();

    final prefs = await SharedPreferences.getInstance();
    expect(manager.mode, DataMode.cloud);
    expect(prefs.getString('data_mode'), 'cloud');

    // 下次读取保存值，不能被旧 local 配置覆盖。
    manager.resetForTesting();
    await manager.load();
    expect(manager.mode, DataMode.cloud);
  });
}
