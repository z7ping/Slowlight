import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../brand.dart';
import '../services/auto_start_service.dart';
import '../services/app_error_logger.dart';
import '../services/reminder_service.dart';

enum TrayEventAction { showWindow, showContextMenu, ignore }

@visibleForTesting
TrayEventAction trayActionForEvent(String eventName) {
  if (eventName == kSystemTrayEventClick ||
      eventName == kSystemTrayEventDoubleClick) {
    return TrayEventAction.showWindow;
  }
  if (eventName == kSystemTrayEventRightClick) {
    return TrayEventAction.showContextMenu;
  }
  return TrayEventAction.ignore;
}

/// 系统托盘服务。
///
/// Windows 左键或双击直接打开主窗口；右键显示原生系统菜单。
class TrayService {
  static final TrayService _instance = TrayService._();
  factory TrayService() => _instance;
  TrayService._();

  bool _initialized = false;
  bool _autoStartEnabled = false;
  // 菜单重建节流：ReminderService 每秒 tick 都会 notify，
  // 若每次都重建原生菜单，右键弹出的 HMENU 会在 1s 内被销毁，
  // 表现为“右键菜单弹不出来”。只在状态迁移或 30s 到期时重建。
  String _lastMenuKey = '';
  DateTime _lastMenuBuildAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _poppingMenu = false;
  bool _quitting = false;
  final _reminder = ReminderService();
  final _systemTray = SystemTray();
  final _menu = Menu();

  Future<bool> init() async {
    if (_initialized) return true;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return false;
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final String iconAsset;
      if (Platform.isWindows) {
        iconAsset = 'app_icon.ico';
      } else if (Platform.isMacOS) {
        iconAsset = 'tray_icon_macos.png';
      } else {
        iconAsset = 'tray_icon_linux.png';
      }
      final iconPath = '$exeDir/data/flutter_assets/assets/$iconAsset';

      final trayCreated = await _systemTray.initSystemTray(iconPath: iconPath);
      await _trace('init.icon', 'created=$trayCreated path=$iconPath');
      if (!trayCreated) return false;
      await _systemTray.setToolTip(kBrandFullName);

      _autoStartEnabled = await AutoStartService().isEnabled();

      _systemTray.registerSystemTrayEventHandler((eventName) {
        _trace('event', eventName);
        switch (trayActionForEvent(eventName)) {
          case TrayEventAction.showWindow:
            unawaited(_showWindow());
          case TrayEventAction.showContextMenu:
            unawaited(_onRightClick());
          case TrayEventAction.ignore:
            break;
        }
      });

      final menuOk = await _buildNativeMenu();
      await _trace('init.menu', 'ok=$menuOk id=${_menu.menuId}');
      if (!menuOk) return false;
      _initialized = true;
      return true;
    } catch (error, stackTrace) {
      await _log('Tray.init', error, stackTrace);
      return false;
    }
  }

  /// 关键路径跟踪：写入 slowlight-error.log，便于排查托盘事件链路。
  Future<void> _trace(String step, String detail) async {
    try {
      await AppErrorLogger.instance.write(source: 'Tray.$step', error: detail);
    } catch (_) {}
  }

  Future<void> loadAfterLogin() async {
    if (!_initialized) return;
    try {
      if (!_reminder.isLoaded) {
        await _reminder.loadAll();
      }
      // 防止重复登录导致监听器累积（菜单重建风暴）
      _reminder.removeListener(_onReminderChanged);
      _reminder.addListener(_onReminderChanged);
      await _buildNativeMenu();
    } catch (_) {}
  }

  void _onReminderChanged() {
    unawaited(_updateTooltip());
    if (_poppingMenu) return;
    final key = _menuStateKey();
    final changed = key != _lastMenuKey;
    final stale =
        DateTime.now().difference(_lastMenuBuildAt).inSeconds >= 30;
    if (changed || stale) {
      _buildNativeMenu();
    }
  }

  String _menuStateKey() =>
      '${_reminder.state}|${_reminder.paused}|${_reminder.pauseRemainingText ?? ''}';

  Future<void> _onRightClick() async {
    // 菜单在初始化和状态变化时已经构建完成。右键事件里先重建菜单会阻塞
    // Windows 的上下文菜单弹出时机，因此这里只直接显示现有原生菜单。
    await _trace('rightClick.enter', 'menuId=${_menu.menuId}');
    _poppingMenu = true;
    try {
      await _systemTray.popUpContextMenu();
      await _trace('rightClick.done', 'menuId=${_menu.menuId}');
    } catch (error, stackTrace) {
      await _log('Tray.contextMenu', error, stackTrace);
    } finally {
      _poppingMenu = false;
      // 菜单打开期间可能发生状态迁移（如倒计时归零），强制下次 notify 重建
      _lastMenuBuildAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<bool> _buildNativeMenu() async {
    final state = _reminder.state;
    final paused = _reminder.paused;

    String statusText;
    if (state == 'working') {
      statusText = '工作中 ${_formatTime(_reminder.remainingSeconds)}';
    } else if (state == 'micro_rest') {
      statusText = '小憩中 ${_reminder.remainingSeconds}秒';
    } else if (state == 'long_rest') {
      statusText = '休息中 ${_formatTime(_reminder.remainingSeconds)}';
    } else if (paused) {
      statusText = '已暂停（${_reminder.pauseRemainingText ?? "无限期"}）';
    } else {
      statusText = '待机中';
    }

    final menuCreated = await _menu.buildFrom([
      MenuItemLabel(label: '打开主窗口', onClicked: (_) => _showWindow()),
      MenuSeparator(),
      MenuItemLabel(label: statusText, enabled: false),
      MenuSeparator(),
      SubMenu(label: '跳到下一次', children: [
        MenuItemLabel(
          label: '小憩',
          onClicked: (_) {
            _reminder.skipToNextRest();
            _buildNativeMenu();
          },
        ),
        MenuItemLabel(
          label: '休息',
          onClicked: (_) {
            _reminder.skipToNextLongRest();
            _buildNativeMenu();
          },
        ),
      ]),
      SubMenu(label: '暂停休息', children: [
        MenuItemLabel(
          label: '30 分钟',
          onClicked: (_) {
            _reminder.pauseRestUntil(
              DateTime.now().add(const Duration(minutes: 30)),
            );
            _buildNativeMenu();
          },
        ),
        MenuItemLabel(
          label: '1 小时',
          onClicked: (_) {
            _reminder.pauseRestUntil(
              DateTime.now().add(const Duration(hours: 1)),
            );
            _buildNativeMenu();
          },
        ),
        MenuItemLabel(
          label: '2 小时',
          onClicked: (_) {
            _reminder.pauseRestUntil(
              DateTime.now().add(const Duration(hours: 2)),
            );
            _buildNativeMenu();
          },
        ),
        MenuItemLabel(
          label: '5 小时',
          onClicked: (_) {
            _reminder.pauseRestUntil(
              DateTime.now().add(const Duration(hours: 5)),
            );
            _buildNativeMenu();
          },
        ),
        MenuItemLabel(
          label: '直至早晨',
          onClicked: (_) {
            _pauseUntilMorning();
            _buildNativeMenu();
          },
        ),
        MenuItemLabel(
          label: '无限期',
          onClicked: (_) {
            _reminder.pauseIndefinitely();
            _buildNativeMenu();
          },
        ),
      ]),
      if (paused)
        MenuItemLabel(
          label: '恢复休息',
          onClicked: (_) {
            _reminder.resume();
            _buildNativeMenu();
          },
        ),
      MenuItemLabel(
        label: '重置休息',
        onClicked: (_) {
          _reminder.resetReminder();
          _buildNativeMenu();
        },
      ),
      MenuSeparator(),
      MenuItemCheckbox(
        label: '开机自启',
        checked: _autoStartEnabled,
        onClicked: (_) => _toggleAutoStart(),
      ),
      MenuSeparator(),
      MenuItemLabel(label: '退出', onClicked: (_) => _quitApp()),
    ]);

    if (!menuCreated) {
      await _trace('menu.build', 'buildFrom=false');
      return false;
    }
    try {
      await _systemTray.setContextMenu(_menu);
      _lastMenuKey = _menuStateKey();
      _lastMenuBuildAt = DateTime.now();
      await _trace('menu.build', 'attached id=${_menu.menuId}');
      return true;
    } catch (error, stackTrace) {
      await _log('Tray.buildMenu', error, stackTrace);
      return false;
    }
  }

  Future<void> rebuildAfterRestore() async {
    await _updateTooltip();
    await _buildNativeMenu();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _updateTooltip() async {
    final state = _reminder.state;
    final paused = _reminder.paused;
    String tip = kBrandDisplayName;
    if (paused) {
      tip = _reminder.pauseRemainingText ?? '已暂停';
    } else if (state == 'working') {
      tip = '工作中 ${_formatTime(_reminder.remainingSeconds)}';
    } else if (state == 'micro_rest') {
      tip = '小憩中 ${_reminder.remainingSeconds}秒';
    } else if (state == 'long_rest') {
      tip = '休息中 ${_formatTime(_reminder.remainingSeconds)}';
    }
    try {
      await _systemTray.setToolTip(tip);
    } catch (_) {}
  }

  Future<void> refreshMenu() async {
    if (!_initialized) return;
    await _buildNativeMenu();
  }

  void _pauseUntilMorning() {
    final now = DateTime.now();
    var morning = DateTime(now.year, now.month, now.day, 8, 0);
    if (now.isAfter(morning)) {
      morning = morning.add(const Duration(days: 1));
    }
    _reminder.pauseRestUntil(morning);
  }

  Future<void> _toggleAutoStart() async {
    bool success;
    if (_autoStartEnabled) {
      success = await AutoStartService().disable();
    } else {
      success = await AutoStartService().enable();
    }
    if (success) {
      _autoStartEnabled = !_autoStartEnabled;
      await _buildNativeMenu();
    }
  }

  Future<void> _showWindow() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (error, stackTrace) {
      await _log('Tray.showWindow', error, stackTrace);
    }
  }

  Future<void> _quitApp() async {
    if (_quitting) return;
    _quitting = true;

    // Explicit "退出" must mean process termination, not another hide-to-tray.
    // Start the fallback before plugin cleanup so a stuck native call cannot
    // leave the old executable locked during an update.
    Timer(const Duration(seconds: 3), () => exit(0));
    await _trace('quit.begin', 'platform=${Platform.operatingSystem}');
    _reminder.stopAll();

    try {
      await _systemTray.destroy();
    } catch (error, stackTrace) {
      await _log('Tray.quit.destroyTray', error, stackTrace);
    } finally {
      _initialized = false;
    }

    try {
      // Normal window-close behavior remains "hide to tray". Only the explicit
      // tray Exit action disables that interception before asking the native
      // window to close.
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (error, stackTrace) {
      await _log('Tray.quit.closeWindow', error, stackTrace);
      exit(0);
    }
  }

  Future<void> dispose() async {
    _initialized = false;
  }

  Future<void> _log(
    String source,
    Object error,
    StackTrace stackTrace,
  ) async {
    await AppErrorLogger.instance.write(
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
