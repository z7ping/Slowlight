// keyboard_hook_stub.dart
// Web 平台 stub — dart:ffi 不可用，所有操作返回空/失败码

/// 键盘钩子 stub（Web 平台不支持）
class KeyboardHookFFI {
  static String? get loadError => 'Web 平台不支持键盘钩子';

  /// 返回 -1 表示不支持
  static int start() => -1;
  static void stop() {}
  static void setBlock(bool enabled) {}
}
