// keyboard_hook_ffi.dart
// 通过 dart:ffi 直接加载 keyhook.dll，绕过 Flutter 插件机制
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';

// 函数签名
typedef KeyhookStartNative = Int32 Function();
typedef KeyhookStart = int Function();
typedef KeyhookStopNative = Void Function();
typedef KeyhookStop = void Function();
typedef KeyhookSetBlockNative = Void Function(Int32 enabled);
typedef KeyhookSetBlock = void Function(int enabled);

/// 键盘钩子 FFI 封装（仅 Windows）
class KeyboardHookFFI {
  static DynamicLibrary? _lib;
  static String? _loadError;

  static DynamicLibrary? _tryLoad() {
    if (_lib != null) return _lib;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final dllPath = '$exeDir\\keyhook.dll';

      if (!File(dllPath).existsSync()) {
        _loadError = 'DLL 不存在: $dllPath';
        return null;
      }

      _lib = DynamicLibrary.open(dllPath);
      _loadError = null;
      return _lib;
    } catch (e) {
      _loadError = 'DLL 加载失败: $e';
      return null;
    }
  }

  /// 获取加载错误信息（用于 UI 显示）
  static String? get loadError => _loadError;

  static int start() {
    final lib = _tryLoad();
    if (lib == null) return -1;
    try {
      final fn = lib
          .lookupFunction<KeyhookStartNative, KeyhookStart>('keyhook_start');
      final result = fn();
      // 0=成功, 1=已启动(也成功), -1=失败
      return result;
    } catch (e) {
      return -1;
    }
  }

  static void stop() {
    final lib = _tryLoad();
    if (lib == null) return;
    try {
      final fn = lib
          .lookupFunction<KeyhookStopNative, KeyhookStop>('keyhook_stop');
      fn();
    } catch (e) {
    }
  }

  static void setBlock(bool enabled) {
    final lib = _tryLoad();
    if (lib == null) return;
    try {
      final fn = lib.lookupFunction<KeyhookSetBlockNative, KeyhookSetBlock>(
          'keyhook_set_block');
      fn(enabled ? 1 : 0);
    } catch (e) {
    }
  }
}
