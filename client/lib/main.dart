import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:window_manager/window_manager.dart';
import 'brand.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/auto_start_service.dart';
import 'services/tray_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'theme/app_theme.dart';
import 'ui/app_theme.dart' as fx_theme;
import 'services/theme_settings.dart';
import 'services/lock_screen.dart';
import 'services/data_mode_manager.dart';
import 'services/reminder_service.dart';
import 'services/app_error_logger.dart';
import 'services/cloud_sync_coordinator.dart';
import 'widgets/app_error_view.dart';
import 'widgets/rest_overlay.dart';
import 'ui/widgets/slowlight_logo.dart';
import 'package:slowlight/ui/fx.dart';

/// 全局 NavigatorKey — 用于通知点击等外部事件驱动导航
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerGlobalErrorHandlers();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await initializeDateFormatting('zh_CN');
  await initializeDateFormatting('en_US');

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(1024, 700));
    await windowManager.setSize(const Size(1200, 800));
    await windowManager.center();
    await windowManager.setTitle(kBrandFullName);
    if (Platform.isWindows) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    await windowManager.setPreventClose(true);
  }

  try {
    await NotificationService().init();
  } catch (_) {}

  // Data Mode 只决定数据来源，不决定 AI 能力。
  // Local Mode 无需 Slowlight Server；Cloud Mode 在认证通过后启用独立 Cloud Cache。
  await DataModeManager().load();
  if (DataModeManager().isLocal) {
    await AuthService.initLocalUser();
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await ReminderService().loadAll();
    } catch (_) {}
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    _registerRestOverlay();
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await AutoStartService().init();
    } catch (_) {}
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await TrayService().init();
    // Windows Runner 不默认展示首帧，由这里统一弹出主窗口；
    // 托盘图标仅作为运行期间的常驻快捷入口，不再承担首次可见性。
    await windowManager.show();
    await windowManager.focus();
  }

  LockScreenManager().setNavigatorKey(navigatorKey);
  runApp(const MyApp());
}

void _registerGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppErrorLogger.instance.write(
      source: 'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppErrorLogger.instance.write(
      source: 'PlatformDispatcher',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  ErrorWidget.builder =
      (_) =>
          AppErrorView(logPath: kIsWeb ? null : AppErrorLogger.defaultLogPath);
}

bool _restOverlayShown = false;

void _registerRestOverlay() {
  ReminderService().addListener(() {
    final service = ReminderService();
    final state = service.state;

    if ((state == 'micro_rest' || state == 'long_rest') && !_restOverlayShown) {
      _restOverlayShown = true;
      if (!(Platform.isWindows &&
          ReminderService().lockScreenMode == 'fullscreen')) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          showRestOverlay(ctx);
        }
      }
    }
    if (state == 'idle' || state == 'working') {
      _restOverlayShown = false;
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  final _themeSettings = ThemeSettings();
  bool _themeListenerAdded = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.addListener(this);
    }
    _themeSettings.load().then((_) {
      fx_theme.setActivePalette(_themeSettings.palette);
      if (!mounted) return;
      _themeSettings.addListener(_onThemeChanged);
      _themeListenerAdded = true;
    });
  }

  void _onThemeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (_themeListenerAdded) {
      _themeSettings.removeListener(_onThemeChanged);
    }
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final isPrevented = await windowManager.isPreventClose();
      if (isPrevented) {
        await windowManager.hide();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily =
        _themeSettings.resolvedFontFamily.isEmpty
            ? null
            : _themeSettings.resolvedFontFamily;
    final isDark =
        _themeSettings.themeMode == ThemeMode.dark ||
        (_themeSettings.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return ShadTheme(
      data:
          isDark
              ? fx_theme.shadDarkTheme(fontFamily)
              : fx_theme.shadLightTheme(fontFamily),
      child: MaterialApp(
        title: kBrandDisplayName,
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.lightTheme(fontFamily: fontFamily),
        darkTheme: AppTheme.darkTheme(fontFamily: fontFamily),
        themeMode: _themeSettings.themeMode,
        builder: (context, child) {
          final appScale = _themeSettings.fontScale;
          final systemScale = MediaQuery.textScalerOf(context).scale(1);
          final effectiveScale =
              (systemScale * appScale).clamp(0.85, 2.0).toDouble();
          Widget content = child!;
          if (effectiveScale != systemScale) {
            content = MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(effectiveScale)),
              child: content,
            );
          }
          if (!kIsWeb && Platform.isWindows) {
            content = Column(
              children: [
                SizedBox(
                  height: kWindowCaptionHeight,
                  child: WindowCaption(
                    brightness: Theme.of(context).brightness,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    title: SizedBox(
                      width: 216,
                      child: Row(
                        children: [
                          const SlowlightLogo(size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '所行映我 · Slowlight',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(child: content),
              ],
            );
          }
          return FxNoticeHost(child: content);
        },
        home: const AuthGate(),
      ),
    );
  }
}

/// 全局认证状态广播 — login/logout 后触发 AuthGate 重新检查。
/// Data Mode 决定 Local 是否需要服务端认证；这个 notifier 只负责触发刷新。
final ValueNotifier<bool> authStateNotifier = ValueNotifier<bool>(false);

/// 认证网关：Local Mode 直接进入本地产品；Cloud Mode 才要求服务端登录。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  bool _hasAccess = false;

  @override
  void initState() {
    super.initState();
    authStateNotifier.addListener(_onAuthChanged);
    _checkAuth();
  }

  @override
  void dispose() {
    authStateNotifier.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() => _checkAuth();

  Future<void> _checkAuth() async {
    var hasAccess = false;
    if (DataModeManager().isLocal) {
      CloudSyncCoordinator().stop();
      await AuthService.initLocalUser();
      hasAccess = true;
    } else {
      hasAccess = await AuthService.isLoggedIn();
      if (hasAccess) {
        try {
          await CloudSyncCoordinator().start();
          // 首次进入 Cloud 不阻塞页面；先处理离线意图，再 push/pull。
          unawaited(CloudSyncCoordinator().syncNow());
        } catch (_) {
          // Cloud Cache 初始化失败不应让一个有效的在线登录失效。
        }
      } else {
        CloudSyncCoordinator().stop();
      }
    }
    if (!mounted) return;
    setState(() {
      _hasAccess = hasAccess;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: FxCircularProgress()));
    }
    return _hasAccess ? const HomeScreen() : const LoginScreen();
  }
}
