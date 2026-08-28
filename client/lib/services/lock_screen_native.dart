import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'keyboard_hook_ffi.dart';
import 'reminder_service.dart';
import 'tray_service.dart';

// FFI signatures for lock_overlay.dll
typedef OverlayStartNative = Int32 Function();
typedef OverlayStart = int Function();
typedef OverlayStopNative = Void Function();
typedef OverlayStop = void Function();
typedef OverlaySetRemainingNative = Void Function(Int32 seconds);
typedef OverlaySetRemaining = void Function(int seconds);
typedef OverlayConsumeActionNative = Int32 Function();
typedef OverlayConsumeAction = int Function();
typedef OverlaySetStrictNative = Void Function(Int32 strict);
typedef OverlaySetStrict = void Function(int strict);
/// Multi-monitor lock screen overlay via FFI.
class _OverlayFFI {
  static DynamicLibrary? _lib;
  static String? _error;

  static DynamicLibrary? _tryLoad() {
    if (_lib != null) return _lib;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final dllPath = '$exeDir\\lock_overlay.dll';

      if (!File(dllPath).existsSync()) {
        _error = 'lock_overlay.dll not found: $dllPath';
        return null;
      }

      _lib = DynamicLibrary.open(dllPath);
      _error = null;
      return _lib;
    } catch (e) {
      _error = 'Failed to load lock_overlay.dll: $e';
      return null;
    }
  }

  static int start() {
    final lib = _tryLoad();
    if (lib == null) return -1;
    try {
      final fn =
          lib.lookupFunction<OverlayStartNative, OverlayStart>('overlay_start');
      return fn();
    } catch (e) {
      return -1;
    }
  }

  static void stop() {
    final lib = _tryLoad();
    if (lib == null) return;
    try {
      final fn =
          lib.lookupFunction<OverlayStopNative, OverlayStop>('overlay_stop');
      fn();
    } catch (e) {
    }
  }

  static void setRemaining(int seconds) {
    final lib = _tryLoad();
    if (lib == null) return;
    try {
      final fn = lib.lookupFunction<OverlaySetRemainingNative,
          OverlaySetRemaining>('overlay_set_remaining');
      fn(seconds);
    } catch (e) {
      // silent
    }
  }

  static int consumeAction() {
    final lib = _tryLoad();
    if (lib == null) return 0;
    try {
      final fn = lib.lookupFunction<OverlayConsumeActionNative,
          OverlayConsumeAction>('overlay_consume_action');
      return fn();
    } catch (e) {
      return 0;
    }
  }

  static void setStrict(int strict) {
    final lib = _tryLoad();
    if (lib == null) return;
    try {
      final fn = lib.lookupFunction<OverlaySetStrictNative,
          OverlaySetStrict>('overlay_set_strict');
      fn(strict);
    } catch (e) {
      // silent
    }
  }

}

/// Desktop lock screen using native overlay windows on ALL monitors.
/// - Flutter window is hidden during lock.
/// - Native overlay DLL covers every monitor with black bg + countdown.
/// - Primary monitor also gets clickable skip/postpone buttons.
/// - Keyboard is blocked via keyhook.dll.
class LockScreenManager {
  static final LockScreenManager _instance = LockScreenManager._();
  factory LockScreenManager() => _instance;
  LockScreenManager._();

  bool _isLocked = false;
  bool _isLocking = false;
  bool get isLocked => _isLocked;

  Timer? _actionPollTimer;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void setNavigatorKey(GlobalKey<NavigatorState> key) {}

  void updateOverlayCountdown(int remainingSeconds) {
    if (Platform.isWindows) {
      _OverlayFFI.setRemaining(remainingSeconds);
    }
  }

  Future<void> lock({String message = '请休息一下'}) async {
    if (_isLocked || _isLocking) {
      return;
    }
    _isLocking = true;

    if (!_isDesktop) {
      _isLocking = false;
      return;
    }

    try {
      _isLocked = true;

      if (Platform.isWindows) {
        // Windows: 隐藏 Flutter 主窗口，native overlay 覆盖全部显示器
        await windowManager.hide();

        // 通知 DLL 严格模式状态
        final strict = ReminderService().isCurrentRestStrict ? 1 : 0;
        _OverlayFFI.setStrict(strict);

        // 启动 native overlay（覆盖所有显示器，主屏带按钮）
        try {
          _OverlayFFI.start();
        } catch (e) {
        }

        // 键盘拦截
        try {
          KeyboardHookFFI.start();
        } catch (e) {
        }
      } else {
        // Linux/macOS: 窗口全屏化，由 RestOverlay 处理 UI
        await windowManager.setFullScreen(true);
      }

      // 开始轮询 native 按钮点击
      _startActionPolling();
    } catch (e) {
      _isLocked = false;
      await _cleanup();
    } finally {
      _isLocking = false;
    }
  }

  Future<void> unlock() async {
    if (!_isLocked && !_isLocking) return;
    _isLocked = false;

    if (!_isDesktop) return;
    if (_isLocking) {
      while (_isLocking) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    await _cleanup();
  }

  Future<void> _cleanup() async {
    _stopActionPolling();

    if (Platform.isWindows) {
      try { KeyboardHookFFI.stop(); } catch (_) {}
      try { _OverlayFFI.stop(); } catch (_) {}
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {}
    } else {
      // Linux/macOS: 退出全屏
      try {
        await windowManager.setFullScreen(false);
      } catch (e) {}
      try {
        await windowManager.focus();
      } catch (e) {}
    }

    try {
      await TrayService().rebuildAfterRestore();
    } catch (_) {}
  }

  void _startActionPolling() {
    _stopActionPolling();
    _actionPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isLocked) { _stopActionPolling(); return; }
      final action = _OverlayFFI.consumeAction();
      if (action == 1) {
        ReminderService().skipRest();
      } else if (action == 2) {
        ReminderService().postponeRest();
      }
    });
  }

  void _stopActionPolling() {
    _actionPollTimer?.cancel();
    _actionPollTimer = null;
  }
}
