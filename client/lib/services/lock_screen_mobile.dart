import 'package:flutter/material.dart';

/// 移动端锁屏：空实现（移动端无窗口管理概念）
class LockScreenManager {
  static final LockScreenManager _instance = LockScreenManager._();
  factory LockScreenManager() => _instance;
  LockScreenManager._();

  bool _isLocked = false;
  bool get isLocked => _isLocked;

  void setNavigatorKey(GlobalKey<NavigatorState> key) {}

  Future<void> lock({String message = '请休息一下'}) async {
  }

  Future<void> unlock() async {}

  /// 更新副屏 overlay 倒计时（移动端空实现）
  void updateOverlayCountdown(int remainingSeconds) {}
}
