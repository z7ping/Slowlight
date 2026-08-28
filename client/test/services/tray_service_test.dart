import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/tray_service.dart';
import 'package:system_tray/system_tray.dart';

void main() {
  test('托盘单击和双击都打开主窗口', () {
    expect(
      trayActionForEvent(kSystemTrayEventClick),
      TrayEventAction.showWindow,
    );
    expect(
      trayActionForEvent(kSystemTrayEventDoubleClick),
      TrayEventAction.showWindow,
    );
  });

  test('托盘右键显示原生系统菜单', () {
    expect(
      trayActionForEvent(kSystemTrayEventRightClick),
      TrayEventAction.showContextMenu,
    );
  });

  test('未知托盘事件不会触发操作', () {
    expect(trayActionForEvent('unknown'), TrayEventAction.ignore);
  });
}
