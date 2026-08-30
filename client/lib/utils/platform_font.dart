import 'package:flutter/foundation.dart';

/// 检测平台系统字体
///
/// Flutter 默认字体是 Roboto，在 Windows 上看着不原生。
/// 这个工具自动检测系统字体，让界面跟系统一致。
class PlatformFont {
  /// 获取平台默认字体家族
  /// 返回 null 表示用 Flutter 内置默认
  static String? get systemFontFamily {
    if (kIsWeb) return null; // Web 由浏览器控制字体

    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return _windowsFont;
      case TargetPlatform.linux:
        return 'Noto Sans CJK SC'; // Linux 中文环境常见
      case TargetPlatform.macOS:
        return '.AppleSystemUIFont'; // macOS 系统字体
      case TargetPlatform.android:
        // 不显式指定 Roboto。Android 的系统 sans-serif 会按当前语言选择
        // 合适的中文字体，并为拉丁字符提供一致的度量与回退链。
        return null;
      case TargetPlatform.iOS:
        return '.AppleSystemUIFont'; // iOS 系统字体
      default:
        return null;
    }
  }

  /// Windows 系统字体检测
  /// 优先用微软 UI 字体，中文环境下用微软雅黑
  static String get _windowsFont {
    // 微软雅黑是 Windows 中文环境标准字体
    // Segoe UI 是 Windows 英文 UI 字体，中文字符回退到微软雅黑
    // 直接用 Microsoft YaHei UI（Win8+ 的混合字体）效果最好
    return 'Microsoft YaHei UI';
  }

  /// 获取所有可用的 Windows 中文字体选项
  static List<String> get windowsFontOptions {
    return [
      'Microsoft YaHei UI', // 微软雅黑 UI（推荐，Win8+）
      'Microsoft YaHei', // 微软雅黑（经典）
      'Segoe UI', // Windows 默认 UI 字体
      'SimHei', // 黑体
      'Noto Sans SC', // 思源黑体
    ];
  }

  /// 是否是桌面平台
  static bool get isDesktop {
    if (kIsWeb) return false;
    return {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);
  }

  /// 是否使用 Android 的移动端交互与无障碍基线。
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
