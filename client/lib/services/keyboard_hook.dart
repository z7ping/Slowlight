// keyboard_hook.dart
// 条件导出：桌面端用 FFI，Web 端用 stub
export 'keyboard_hook_stub.dart'
    if (dart.library.io) 'keyboard_hook_ffi.dart';
