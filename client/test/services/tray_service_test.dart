import 'dart:io';

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

  test('托盘退出解除关闭拦截并保证进程最终结束', () {
    final source = File('lib/services/tray_service.dart').readAsStringSync();

    expect(source, contains('bool _quitting = false;'));
    expect(source, contains('if (_quitting) return;'));
    expect(source, contains('await _systemTray.destroy();'));
    expect(source, contains('await windowManager.setPreventClose(false);'));
    expect(source, contains('await windowManager.close();'));
    expect(
      source,
      contains('Timer(const Duration(seconds: 3), () => exit(0));'),
    );
    expect(
      source.indexOf('windowManager.setPreventClose(false)'),
      lessThan(source.indexOf('windowManager.close()')),
    );
  });
}
