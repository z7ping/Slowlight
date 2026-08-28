import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 统一主题 — Zinc 中性表面 + 可切换品牌强调色。
/// 高保真原型中 palette 只改变 primary / accent，不改变页面基础表面。

class ThemePalette {
  final String name;
  final String label;
  final String icon;
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color bg;
  final Color bgCard;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color divider;
  final Color accent;
  final Color primaryBtnBg;
  final Color primaryBtnFg;
  final Color darkBg;
  final Color darkCard;
  final Color darkBorder;
  final Color darkDivider;
  final Color darkPrimaryBtnBg;
  final Color darkPrimaryBtnFg;

  const ThemePalette({
    required this.name,
    required this.label,
    required this.icon,
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.bg,
    required this.bgCard,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.divider,
    required this.accent,
    required this.primaryBtnBg,
    required this.primaryBtnFg,
    required this.darkBg,
    required this.darkCard,
    required this.darkBorder,
    required this.darkDivider,
    required this.darkPrimaryBtnBg,
    required this.darkPrimaryBtnFg,
  });
}

const _surfaceBg = Color(0xFFFAFAFA);
const _surfaceCard = Color(0xFFFFFFFF);
const _surfaceText = Color(0xFF18181B);
const _surfaceText2 = Color(0xFF71717A);
const _surfaceBorder = Color(0xFFE4E4E7);
const _surfaceDivider = Color(0xFFF4F4F5);
const _darkBg = Color(0xFF09090B);
const _darkCard = Color(0xFF111113);
const _darkBorder = Color(0xFF27272A);
const _darkDivider = Color(0xFF1F1F23);

const _palettes = <String, ThemePalette>{
  'zinc': ThemePalette(
    name: 'zinc', label: '锌灰', icon: '⚪',
    primary: Color(0xFF18181B), primaryDark: Color(0xFF27272A), primaryLight: Color(0xFFF4F4F5),
    bg: _surfaceBg, bgCard: _surfaceCard,
    textPrimary: _surfaceText, textSecondary: _surfaceText2,
    border: _surfaceBorder, divider: _surfaceDivider, accent: Color(0xFF3B82F6),
    primaryBtnBg: Color(0xFF18181B), primaryBtnFg: Color(0xFFFAFAFA),
    darkBg: _darkBg, darkCard: _darkCard,
    darkBorder: _darkBorder, darkDivider: _darkDivider,
    darkPrimaryBtnBg: Color(0xFFFAFAFA), darkPrimaryBtnFg: Color(0xFF18181B),
  ),
  'slate': ThemePalette(
    name: 'slate', label: '石板灰', icon: '🔵',
    primary: Color(0xFF0F172A), primaryDark: Color(0xFF1E293B), primaryLight: Color(0xFFF1F5F9),
    bg: _surfaceBg, bgCard: _surfaceCard,
    textPrimary: _surfaceText, textSecondary: _surfaceText2,
    border: _surfaceBorder, divider: _surfaceDivider, accent: Color(0xFF3B82F6),
    primaryBtnBg: Color(0xFF0F172A), primaryBtnFg: Color(0xFFFAFAFA),
    darkBg: _darkBg, darkCard: _darkCard,
    darkBorder: _darkBorder, darkDivider: _darkDivider,
    darkPrimaryBtnBg: Color(0xFF0F172A), darkPrimaryBtnFg: Color(0xFFFAFAFA),
  ),
  'stone': ThemePalette(
    name: 'stone', label: '石色', icon: '🟤',
    primary: Color(0xFF1C1917), primaryDark: Color(0xFF292524), primaryLight: Color(0xFFF5F5F4),
    bg: _surfaceBg, bgCard: _surfaceCard,
    textPrimary: _surfaceText, textSecondary: _surfaceText2,
    border: _surfaceBorder, divider: _surfaceDivider, accent: Color(0xFF78716C),
    primaryBtnBg: Color(0xFF1C1917), primaryBtnFg: Color(0xFFFAFAFA),
    darkBg: _darkBg, darkCard: _darkCard,
    darkBorder: _darkBorder, darkDivider: _darkDivider,
    darkPrimaryBtnBg: Color(0xFF1C1917), darkPrimaryBtnFg: Color(0xFFFAFAFA),
  ),
  'rose': ThemePalette(
    name: 'rose', label: '玫瑰', icon: '🔴',
    primary: Color(0xFF9F1239), primaryDark: Color(0xFF881337), primaryLight: Color(0xFFFFF1F2),
    bg: _surfaceBg, bgCard: _surfaceCard,
    textPrimary: _surfaceText, textSecondary: _surfaceText2,
    border: _surfaceBorder, divider: _surfaceDivider, accent: Color(0xFFE11D48),
    primaryBtnBg: Color(0xFF9F1239), primaryBtnFg: Color(0xFFFFFFFF),
    darkBg: _darkBg, darkCard: _darkCard,
    darkBorder: _darkBorder, darkDivider: _darkDivider,
    darkPrimaryBtnBg: Color(0xFF9F1239), darkPrimaryBtnFg: Color(0xFFFFFFFF),
  ),
  'orange': ThemePalette(
    name: 'orange', label: '橙色', icon: '🟠',
    primary: Color(0xFF9A3412), primaryDark: Color(0xFF7C2D12), primaryLight: Color(0xFFFFF7ED),
    bg: _surfaceBg, bgCard: _surfaceCard,
    textPrimary: _surfaceText, textSecondary: _surfaceText2,
    border: _surfaceBorder, divider: _surfaceDivider, accent: Color(0xFFEA580C),
    primaryBtnBg: Color(0xFF9A3412), primaryBtnFg: Color(0xFFFFFFFF),
    darkBg: _darkBg, darkCard: _darkCard,
    darkBorder: _darkBorder, darkDivider: _darkDivider,
    darkPrimaryBtnBg: Color(0xFF9A3412), darkPrimaryBtnFg: Color(0xFFFFFFFF),
  ),
};

ThemePalette getPalette(String name) => _palettes[name] ?? _palettes['zinc']!;
List<ThemePalette> get allPalettes => _palettes.values.toList();

ThemePalette _active = _palettes['zinc']!;
ThemePalette get activePalette => _active;
void setActivePalette(String name) { _active = getPalette(name); }

class AppTheme {
  static Color get primary => _active.primary;
  static Color get primaryDark => _active.primaryDark;
  static Color get primaryLight => _active.primaryLight;

  static Color get warmWhite => _active.bg;
  static Color get warmDark => _active.darkBg;
  static Color get warmGray300 => _active.border;
  static Color get warmGray400 => _active.textSecondary.withValues(alpha: 0.65);
  static Color get warmGray500 => _active.textSecondary;
  static Color get warmBorder => _active.border;

  static Color textColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFAFAFA)
        : _active.textPrimary;
  }
  static Color textSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFA1A1AA)
        : _active.textSecondary;
  }

  static const Color priorityUrgentImportant = Color(0xFFef4444);
  static const Color priorityImportant = Color(0xFF3b82f6);
  static const Color priorityUrgent = Color(0xFFf97316);
  static const Color priorityHigh = priorityUrgentImportant;
  static const Color priorityMedium = priorityImportant;
  static const Color priorityLow = priorityUrgent;

  static const Color success = Color(0xFF22c55e);
  static const Color warning = Color(0xFFf97316);
  static const Color error = priorityUrgentImportant;
  static const Color info = Color(0xFF3b82f6);

  static const Color white = Colors.white;
  static const Color onPrimary = Colors.white;
  static const Color white70 = Colors.white70;
  static const Color white54 = Colors.white54;
  static const Color white38 = Colors.white38;
  static const Color white60 = Colors.white60;

  static const Color chartGreen = Color(0xFF52C41A);
  static const Color chartBlue = Color(0xFF1890FF);
  static const Color chartYellow = Color(0xFFFAAD14);
  static const Color chartRed = Color(0xFFFF6B6B);
  static const Color chartPurple = Color(0xFF722ED1);
  static const Color chartCyan = Color(0xFF13C2C2);

  static const double textXs = 12;
  static const double textSm = 12;
  static const double textMd = 14;
  static const double textLg = 16;
  static const double textXl = 18;
  static const double text2Xl = 20;
  static const double text3Xl = 24;

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;

  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;

  static Color priorityColor(String priority) {
    switch (priority) {
      case 'urgent_important': return priorityUrgentImportant;
      case 'important': return priorityImportant;
      case 'urgent': return priorityUrgent;
      default: return _active.textSecondary;
    }
  }
  static String priorityLabel(String priority) {
    switch (priority) {
      case 'urgent_important': return '重要且紧急';
      case 'important': return '重要不紧急';
      case 'urgent': return '紧急不重要';
      default: return '不重要不紧急';
    }
  }

  static List<BoxShadow> get cardShadow => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 4)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.027), blurRadius: 7.85, offset: const Offset(0, 2)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2.93, offset: const Offset(0, 0.8)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 1.04, offset: const Offset(0, 0.2)),
  ];

  static ThemeData lightTheme({String? fontFamily}) {
    final p = _active;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: p.primary, brightness: Brightness.light,
      primary: p.primary, onPrimary: p.primaryBtnFg,
      primaryContainer: p.primaryLight, surface: p.bg,
      surfaceContainerLowest: p.bgCard,
      surfaceContainerLow: p.divider,
      surfaceContainer: p.border,
    ).copyWith(
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      outline: p.border,
      outlineVariant: p.divider,
    );
    return ThemeData(
      colorScheme: colorScheme, useMaterial3: true, fontFamily: fontFamily,
      appBarTheme: AppBarTheme(centerTitle: false, elevation: 0,
        scrolledUnderElevation: 0.5, backgroundColor: p.bgCard,
        foregroundColor: p.textPrimary,
        titleTextStyle: TextStyle(fontSize: AppTheme.textXl, height: 1.2, fontWeight: FontWeight.w600, color: p.textPrimary),
        surfaceTintColor: Colors.transparent),
      scaffoldBackgroundColor: p.bg,
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      cardTheme: CardThemeData(elevation: 0, color: p.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border, width: 1)),
        shadowColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: p.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent, width: 1)),
        hoverColor: p.divider,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: p.primaryBtnBg,
          foregroundColor: p.primaryBtnFg, elevation: 0,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
      dialogTheme: DialogThemeData(backgroundColor: p.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      splashColor: p.primary.withValues(alpha: 0.10),
      highlightColor: p.primary.withValues(alpha: 0.08),
      hoverColor: p.primary.withValues(alpha: 0.06),
      focusColor: p.accent.withValues(alpha: 0.12),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }

  static ThemeData darkTheme({String? fontFamily}) {
    final p = _active;
    const foreground = Color(0xFFFAFAFA);
    const secondary = Color(0xFFA1A1AA);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: p.accent, brightness: Brightness.dark,
      primary: p.name == 'zinc' ? foreground : p.primary,
      onPrimary: p.darkPrimaryBtnFg,
      primaryContainer: p.darkCard, surface: p.darkBg,
      surfaceContainerLowest: p.darkCard,
      surfaceContainerLow: p.darkDivider,
      surfaceContainer: p.darkBorder,
    ).copyWith(
      onSurface: foreground,
      onSurfaceVariant: secondary,
      outline: p.darkBorder,
      outlineVariant: p.darkDivider,
    );
    return ThemeData(
      colorScheme: colorScheme, useMaterial3: true, fontFamily: fontFamily,
      scaffoldBackgroundColor: p.darkBg,
      appBarTheme: AppBarTheme(centerTitle: false, elevation: 0,
        scrolledUnderElevation: 0.5, backgroundColor: p.darkCard,
        foregroundColor: foreground,
        titleTextStyle: TextStyle(fontSize: AppTheme.textXl, height: 1.2, fontWeight: FontWeight.w600, color: foreground),
        surfaceTintColor: Colors.transparent),
      dividerTheme: DividerThemeData(color: p.darkDivider, thickness: 1, space: 1),
      cardTheme: CardThemeData(elevation: 0, color: p.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.darkBorder, width: 1)),
        shadowColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: p.darkBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.darkBorder, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.darkBorder, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent, width: 1)),
        hoverColor: p.darkDivider,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: p.darkPrimaryBtnBg,
          foregroundColor: p.darkPrimaryBtnFg, elevation: 0,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
      dialogTheme: DialogThemeData(backgroundColor: p.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      splashColor: p.accent.withValues(alpha: 0.10),
      highlightColor: p.accent.withValues(alpha: 0.08),
      hoverColor: p.accent.withValues(alpha: 0.06),
      focusColor: p.accent.withValues(alpha: 0.12),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }
}

ShadTextTheme _systemTextTheme([String? family]) {
  return ShadTextTheme.custom(
    h1Large: TextStyle(fontFamily: family, fontSize: AppTheme.textXl, fontWeight: FontWeight.w800, height: 1, letterSpacing: -0.4),
    h1: TextStyle(fontFamily: family, fontSize: AppTheme.textXl, fontWeight: FontWeight.w800, height: 40/36, letterSpacing: -0.4),
    h2: TextStyle(fontFamily: family, fontSize: AppTheme.textXl, fontWeight: FontWeight.w600, height: 36/30, letterSpacing: -0.4),
    h3: TextStyle(fontFamily: family, fontSize: AppTheme.textXl, fontWeight: FontWeight.w600, height: 32/24, letterSpacing: -0.4),
    h4: TextStyle(fontFamily: family, fontSize: AppTheme.textXl, fontWeight: FontWeight.w600, height: 28/20, letterSpacing: -0.4),
    p: TextStyle(fontFamily: family, fontSize: AppTheme.textLg, fontWeight: FontWeight.w400, height: 28/16),
    blockquote: TextStyle(fontFamily: family, fontSize: AppTheme.textLg, fontWeight: FontWeight.w400, fontStyle: FontStyle.italic, height: 24/16),
    table: TextStyle(fontFamily: family, fontSize: AppTheme.textLg, fontWeight: FontWeight.w700, height: 24/16),
    list: TextStyle(fontFamily: family, fontSize: AppTheme.textLg, fontWeight: FontWeight.w400, height: 24/16),
    lead: TextStyle(fontFamily: family, fontSize: AppTheme.textXl, fontWeight: FontWeight.w400, height: 28/20),
    large: TextStyle(fontFamily: family, fontSize: AppTheme.textXl, fontWeight: FontWeight.w600, height: 28/18),
    small: TextStyle(fontFamily: family, fontSize: AppTheme.textMd, fontWeight: FontWeight.w500, height: 1),
    muted: TextStyle(fontFamily: family, fontSize: AppTheme.textMd, fontWeight: FontWeight.w400, height: 20/15),
    family: family ?? '',
  );
}

ShadButtonTheme _buttonTheme() {
  return ShadButtonTheme(
    height: 36,
    sizesTheme: ShadButtonSizesTheme(
      regular: ShadButtonSizeTheme(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      sm: ShadButtonSizeTheme(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      lg: ShadButtonSizeTheme(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
  );
}

ShadInputTheme _inputTheme() {
  final p = _active;
  return ShadInputTheme(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: ShadDecoration(
      border: ShadBorder.all(
        color: p.border,
        width: 1,
        radius: BorderRadius.circular(8),
      ),
      focusedBorder: ShadBorder.all(
        color: p.accent,
        width: 1,
        radius: BorderRadius.circular(8),
      ),
    ),
  );
}

ShadThemeData shadLightTheme([String? fontFamily]) {
  final p = _active;
  return ShadThemeData(
    colorScheme: ShadZincColorScheme.light(
      background: p.bg,
      foreground: p.textPrimary,
      card: p.bgCard,
      cardForeground: p.textPrimary,
      popover: p.bgCard,
      popoverForeground: p.textPrimary,
      primary: p.primary,
      primaryForeground: p.primaryBtnFg,
      secondary: p.primaryLight,
      secondaryForeground: p.primary,
      muted: p.divider,
      mutedForeground: p.textSecondary,
      accent: p.accent,
      accentForeground: Colors.white,
      border: p.border,
      input: p.border,
      ring: p.accent,
    ),
    brightness: Brightness.light,
    radius: BorderRadius.circular(8),
    textTheme: _systemTextTheme(fontFamily),
    primaryButtonTheme: _buttonTheme(),
    secondaryButtonTheme: _buttonTheme(),
    outlineButtonTheme: _buttonTheme(),
    ghostButtonTheme: _buttonTheme(),
    destructiveButtonTheme: _buttonTheme(),
    linkButtonTheme: _buttonTheme(),
    cardTheme: ShadCardTheme(
      backgroundColor: p.bgCard,
      radius: BorderRadius.circular(12),
    ),
    inputTheme: _inputTheme(),
  );
}

ShadThemeData shadDarkTheme([String? fontFamily]) {
  final p = _active;
  const foreground = Color(0xFFFAFAFA);
  const secondary = Color(0xFFA1A1AA);
  return ShadThemeData(
    colorScheme: ShadZincColorScheme.dark(
      background: p.darkBg,
      foreground: foreground,
      card: p.darkCard,
      cardForeground: foreground,
      popover: p.darkCard,
      popoverForeground: foreground,
      primary: p.name == 'zinc' ? foreground : p.primary,
      primaryForeground: p.darkPrimaryBtnFg,
      secondary: p.darkCard,
      secondaryForeground: foreground,
      muted: p.darkDivider,
      mutedForeground: secondary,
      accent: p.accent,
      accentForeground: Colors.white,
      border: p.darkBorder,
      input: p.darkBorder,
      ring: p.accent,
    ),
    brightness: Brightness.dark,
    radius: BorderRadius.circular(8),
    textTheme: _systemTextTheme(fontFamily),
    primaryButtonTheme: _buttonTheme(),
    secondaryButtonTheme: _buttonTheme(),
    outlineButtonTheme: _buttonTheme(),
    ghostButtonTheme: _buttonTheme(),
    destructiveButtonTheme: _buttonTheme(),
    linkButtonTheme: _buttonTheme(),
    cardTheme: ShadCardTheme(
      backgroundColor: p.darkCard,
      radius: BorderRadius.circular(12),
    ),
    inputTheme: _inputTheme(),
  );
}
