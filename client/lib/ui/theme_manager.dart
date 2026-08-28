import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../ui/app_theme.dart' as app;

/// 统一主题管理器
/// 提供对 Material 和 Shad 两套主题的统一访问入口
class ThemeManager {
  ThemeManager._();

  /// 获取 Material 亮色主题
  static ThemeData get lightTheme => app.AppTheme.lightTheme();

  /// 获取 Material 暗色主题
  static ThemeData get darkTheme => app.AppTheme.darkTheme();

  /// 获取 Shad 亮色主题
  static ShadThemeData get shadLight => app.shadLightTheme();

  /// 获取 Shad 暗色主题
  static ShadThemeData get shadDark => app.shadDarkTheme();

  /// 获取当前激活的配色方案
  static app.ThemePalette get currentPalette => app.activePalette;

  /// 获取主颜色
  static Color get primary => app.AppTheme.primary;

  /// 获取背景颜色
  static Color get background => app.AppTheme.warmWhite;

  /// 获取前景/文字颜色
  static Color get foreground => app.AppTheme.primary;
}
