import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/platform_font.dart';
import '../ui/app_theme.dart' show setActivePalette;

/// 主题/字体设置服务
/// 持久化: 字号倍率、主题模式、字体家族
class ThemeSettings extends ChangeNotifier {
  static final ThemeSettings _instance = ThemeSettings._();
  factory ThemeSettings() => _instance;
  ThemeSettings._();

  static const _keyFontSize = 'theme_font_scale';
  static const _keyThemeMode = 'theme_mode';
  static const _keyFontFamily = 'theme_font_family';
  static const _keyPalette = 'theme_palette';

  double _fontScale = 1.0;
  ThemeMode _themeMode = ThemeMode.system;
  String _fontFamily = ''; // 加载后由 _resolveFontFamily 处理
  String _palette = 'zinc'; // 当前配色方案

  double get fontScale => _fontScale;
  ThemeMode get themeMode => _themeMode;
  String get fontFamily => _fontFamily;
  String get palette => _palette;

  /// 字号选项
  static final fontScaleOptions = <double, String>{
    0.85: '小',
    0.92: '较小',
    1.0: '默认',
    1.08: '较大',
    1.16: '大',
    1.25: '特大',
  };

  /// 主题模式选项
  static final themeModeOptions = <ThemeMode, String>{
    ThemeMode.system: '跟随系统',
    ThemeMode.light: '浅色',
    ThemeMode.dark: '深色',
  };

  /// 字体选项（动态生成，按平台适配）
  static Map<String, String> get fontFamilyOptions {
    final options = <String, String>{
      '': '跟随系统',
    };

    if (PlatformFont.isDesktop) {
      // 桌面端显示平台原生字体
      for (final font in PlatformFont.windowsFontOptions) {
        options[font] = font;
      }
    }

    options['Inter'] = 'Inter';
    options['SimSun'] = '宋体';
    options['SimHei'] = '黑体';
    return options;
  }

  /// 解析字体：空字符串 → 系统字体
  String get resolvedFontFamily {
    if (_fontFamily.isEmpty) {
      return PlatformFont.systemFontFamily ?? '';
    }
    return _fontFamily;
  }

  /// 加载设置
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _fontScale = prefs.getDouble(_keyFontSize) ?? 1.0;
    _fontFamily = prefs.getString(_keyFontFamily) ?? '';
    final modeStr = prefs.getString(_keyThemeMode) ?? 'system';
    _themeMode = switch (modeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _palette = prefs.getString(_keyPalette) ?? 'zinc';
    notifyListeners();
  }

  /// 设置字号倍率
  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, scale);
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }

  /// 设置字体
  Future<void> setFontFamily(String family) async {
    _fontFamily = family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFontFamily, family);
  }

  /// 设置配色方案
  Future<void> setPalette(String palette) async {
    _palette = palette;
    setActivePalette(palette);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPalette, palette);
  }

  /// 恢复显示设置为默认值
  Future<void> resetToDefaults() async {
    _fontScale = 1.0;
    _themeMode = ThemeMode.system;
    _fontFamily = '';
    _palette = 'zinc';
    setActivePalette('zinc');
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, 1.0);
    await prefs.setString(_keyThemeMode, 'system');
    await prefs.setString(_keyFontFamily, '');
    await prefs.setString(_keyPalette, 'zinc');
  }
}
