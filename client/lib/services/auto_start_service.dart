import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brand.dart';

/// 开机自启服务
///
/// 使用 launch_at_startup 包，支持 Windows/macOS/Linux
/// 设置存储在 shared_preferences 中，方便设置页面读取
class AutoStartService {
  static final AutoStartService _instance = AutoStartService._();
  factory AutoStartService() => _instance;
  AutoStartService._();

  static const _key = 'auto_start_enabled';
  bool _initialized = false;

  /// 初始化（在 main() 中调用）
  Future<void> init() async {
    if (_initialized) return;
    LaunchAtStartup.instance.setup(
      appName: kTechnicalAppName,
      appPath: '',
    );
    _initialized = true;
  }

  /// 获取当前自启状态
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// 开启开机自启
  Future<bool> enable() async {
    try {
      await init();
      await LaunchAtStartup.instance.enable();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 关闭开机自启
  Future<bool> disable() async {
    try {
      await init();
      await LaunchAtStartup.instance.disable();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, false);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 切换自启状态
  Future<bool> toggle() async {
    final enabled = await isEnabled();
    if (enabled) {
      return disable();
    } else {
      return enable();
    }
  }
}
