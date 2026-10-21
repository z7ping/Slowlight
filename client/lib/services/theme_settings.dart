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
  static Map<double, String> get fontScaleOptions => PlatformFont.isAndroid
      ? {
          1.0: '默认',
          1.08: '较大',
          1.16: '大',
          1.25: '特大',
        }
      : {
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
      options['Inter'] = 'Inter';
      options['SimSun'] = '宋体';
      options['SimHei'] = '黑体';
    }

    return options;
  }

  /// 解析字体：空字符串 → 系统字体
  String get resolvedFontFamily {
    if (PlatformFont.isAndroid) return '';
    if (_fontFamily.isEmpty) {
      return PlatformFont.systemFontFamily ?? '';
    }
    return _fontFamily;
  }

  /// 加载设置
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFontScale = prefs.getDouble(_keyFontSize) ?? 1.0;
    _fontScale = PlatformFont.isAndroid
        ? savedFontScale.clamp(1.0, 1.25).toDouble()
        : savedFontScale.clamp(0.85, 1.25).toDouble();
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

  Future<void> _persist(
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await write(prefs)) {
      throw StateError('设置未能保存到本机');
    }
  }

  /// 即时生效；本机写入失败时恢复先前的可见状态。
  Future<void> setFontScale(double scale) async {
    final previous = _fontScale;
    _fontScale = PlatformFont.isAndroid
        ? scale.clamp(1.0, 1.25).toDouble()
        : scale.clamp(0.85, 1.25).toDouble();
    notifyListeners();
    try {
      await _persist((prefs) => prefs.setDouble(_keyFontSize, _fontScale));
    } catch (_) {
      _fontScale = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final previous = _themeMode;
    _themeMode = mode;
    notifyListeners();
    try {
      await _persist((prefs) => prefs.setString(
            _keyThemeMode,
            switch (mode) {
              ThemeMode.light => 'light',
              ThemeMode.dark => 'dark',
              _ => 'system',
            },
          ));
    } catch (_) {
      _themeMode = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setFontFamily(String family) async {
    final previous = _fontFamily;
    _fontFamily = family;
    notifyListeners();
    try {
      await _persist((prefs) => prefs.setString(_keyFontFamily, family));
    } catch (_) {
      _fontFamily = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setPalette(String palette) async {
    final previous = _palette;
    _palette = palette;
    setActivePalette(palette);
    notifyListeners();
    try {
      await _persist((prefs) => prefs.setString(_keyPalette, palette));
    } catch (_) {
      _palette = previous;
      setActivePalette(previous);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resetToDefaults() async {
    final previousScale = _fontScale;
    final previousMode = _themeMode;
    final previousFamily = _fontFamily;
    final previousPalette = _palette;
    _fontScale = 1.0;
    _themeMode = ThemeMode.system;
    _fontFamily = '';
    _palette = 'zinc';
    setActivePalette('zinc');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setDouble(_keyFontSize, 1.0) ||
          !await prefs.setString(_keyThemeMode, 'system') ||
          !await prefs.setString(_keyFontFamily, '') ||
          !await prefs.setString(_keyPalette, 'zinc')) {
        throw StateError('恢复默认设置未能保存到本机');
      }
    } catch (_) {
      _fontScale = previousScale;
      _themeMode = previousMode;
      _fontFamily = previousFamily;
      _palette = previousPalette;
      setActivePalette(previousPalette);
      notifyListeners();
      // 多个本机偏好写入跨 key 非原子操作，尽力恢复先前配置。
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_keyFontSize, previousScale);
        await prefs.setString(_keyThemeMode, switch (previousMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          _ => 'system',
        });
        await prefs.setString(_keyFontFamily, previousFamily);
        await prefs.setString(_keyPalette, previousPalette);
      } catch (_) {}
      rethrow;
    }
  }

}
