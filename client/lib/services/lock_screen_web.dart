import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../ui/app_theme.dart';

/// Web 端锁屏：全屏路由覆盖（不涉及窗口管理）
class LockScreenManager {
  static final LockScreenManager _instance = LockScreenManager._();
  factory LockScreenManager() => _instance;
  LockScreenManager._();

  bool _isLocked = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  bool get isLocked => _isLocked;

  /// 设置 navigatorKey（在 main.dart 中调用）
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 启动锁屏：推全屏路由
  Future<void> lock({String message = '请休息一下'}) async {
    if (_isLocked) return;
    _isLocked = true;

    final context = _navigatorKey?.currentContext;
    if (context == null) {
      return;
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (ctx, _, __) => _LockScreenPage(message: message),
        transitionsBuilder: (ctx, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// 解除锁屏
  Future<void> unlock() async {
    if (!_isLocked) return;
    _isLocked = false;

    final context = _navigatorKey?.currentContext;
    if (context != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// 更新副屏 overlay 倒计时（Web 端空实现）
  void updateOverlayCountdown(int remainingSeconds) {}
}

/// 全屏锁屏界面
class _LockScreenPage extends StatelessWidget {
  final String message;
  const _LockScreenPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppTheme.white54),
              const SizedBox(height: 24),
              Text(
                message,
                style: const TextStyle(
                  fontSize: AppTheme.textXl, height: 1.2,
                  fontWeight: FontWeight.w300,
                  color: AppTheme.white,
                ),
              ),
              const SizedBox(height: 48),
              ShadButton.outline(
                onPressed: () => LockScreenManager().unlock(),
                foregroundColor: AppTheme.white70,
                // border: Border.all(color: AppTheme.white24), // ShadButton.outline doesn't support border
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock_open, color: AppTheme.white70),
                    SizedBox(width: 4),
                    Text(
                      '提前结束休息',
                      style: TextStyle(color: AppTheme.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
