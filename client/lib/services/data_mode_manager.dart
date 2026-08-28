import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/local_behavior_event_schema.dart';
import '../db/local_product_core_schema.dart';

/// 数据模式枚举
enum DataMode {
  /// 本地数据模式：SQLite 为主，不要求 Slowlight Server。
  local,

  /// 云端数据模式：Slowlight Server / PostgreSQL 为主。
  cloud,
}

/// 数据模式管理器 - 只负责“核心数据在哪里”。
///
/// AI Provider 与 Data Mode 正交，不应在这里出现 AI 开关或 Provider 判断。
class DataModeManager extends ChangeNotifier {
  static final DataModeManager _instance = DataModeManager._internal();
  factory DataModeManager() => _instance;
  DataModeManager._internal();

  static const String _key = 'data_mode';
  DataMode _mode = DataMode.local;
  bool _loaded = false;

  DataMode get mode => _mode;
  bool get isLocal => _mode == DataMode.local;
  bool get isCloud => _mode == DataMode.cloud;

  /// 兼容旧 API（过渡期）。新代码禁止继续使用“offline”描述 Local Data。
  @Deprecated('Use isLocal. Local Data is not the same as offline.')
  bool get isOffline => isLocal;

  /// 加载设置 — 默认本地，云端需手动切换。
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    _mode = value == 'cloud' ? DataMode.cloud : DataMode.local;
    if (_mode == DataMode.local) {
      await _ensureLocalCore();
    }
    _loaded = true;
    notifyListeners();
  }

  /// 切换模式。
  Future<void> setMode(DataMode mode) async {
    _mode = mode;
    if (_mode == DataMode.local) {
      await _ensureLocalCore();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
    notifyListeners();
  }

  Future<void> _ensureLocalCore() async {
    await LocalBehaviorEventSchema.ensureReady();
    await LocalProductCoreSchema.ensureReady();
  }

  /// 切换到本地数据模式
  Future<void> setLocal() => setMode(DataMode.local);

  /// 切换到云端数据模式
  Future<void> setCloud() => setMode(DataMode.cloud);

  /// 切换
  Future<void> toggle() async {
    await setMode(isLocal ? DataMode.cloud : DataMode.local);
  }
}
