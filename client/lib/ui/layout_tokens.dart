import 'package:flutter/foundation.dart';

/// Slowlight 通用布局 Token。
///
/// 这里只保留跨页面、跨组件确实需要共享的基础尺度。Feature 私有几何值
/// （例如日历格高、侧栏宽度、某个弹窗宽度）应留在对应组件内部，避免
/// 为了消除数字而制造没有产品语义的“伪通用” Token。
abstract final class SlowlightSpacing {
  /// 跨页面共享的基础间距为 4 / 8 / 12 / 16 / 24。
  /// 2 / 6 / 10 / 14 / 20 / 32 等业务几何值只在所属组件内定义。
  static const double xs = 4;
  static const double md = 8;
  static const double xl = 12;
  static const double xxxl = 16;
  static const double page = 24;
}

abstract final class SlowlightRadius {
  @Deprecated('Legacy 2px radius; do not reuse as a general design token')
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  /// 特定 Sheet 的 18px 语义圆角；不可作为普通卡片通用圆角。
  static const double sheet = 18;
  /// 胶囊形 Chip 的完整圆角；不按 999px 数值机械迁移。
  static const double pill = 999;
}

/// Slowlight 可操作控件的共同尺寸。
abstract final class SlowlightControlSize {
  /// Android 的最低触控目标。桌面组件不能直接用它撑大可见尺寸或布局高度。
  static const double minTouchTarget = 44;

  static const double buttonSm = 32;
  static const double button = 36;
  static const double buttonLg = 40;
}

/// 平台密度只在这一层解析，Fx 组件消费已经解析后的可视/触控尺寸，
/// 不再各自判断 Windows / Android。
abstract final class SlowlightPlatformDensity {
  static bool get usesMobileTouchTargets =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 统一单行输入框的最低可视高度；字体放大允许向上增长。
  static double get inputMinHeight =>
      usesMobileTouchTargets
          ? SlowlightControlSize.minTouchTarget
          : SlowlightControlSize.button;

  /// ShadInput 与 FxInput 共用的输入区内边距语义。
  static double get inputHorizontalPadding => usesMobileTouchTargets ? 14 : 12;
  static double get multilineInputVerticalPadding =>
      usesMobileTouchTargets ? 12 : 8;

  static double get iconButtonVisualSize =>
      usesMobileTouchTargets ? SlowlightControlSize.minTouchTarget : 30;

  static double get segmentedItemMinHeight =>
      usesMobileTouchTargets ? SlowlightControlSize.minTouchTarget : 32;

  static double get chipDeleteTargetSize =>
      usesMobileTouchTargets ? SlowlightControlSize.minTouchTarget : 18;

  static bool get expandClickableChipHitArea => usesMobileTouchTargets;
}

abstract final class SlowlightIconSize {
  static const double xs = 14;
  static const double compactAction = 15;
  static const double sm = 16;
  static const double md = 18;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 30;
  static const double heroGlyph = 48;
  static const double overlay = 64;
}

/// 应用壳层断点。
///
/// 仅用于页面 / 应用壳层布局：mobile < 600，medium 600–1023，
/// desktop >= 1024。组件内部（表单列数、Dialog Footer、ActionBar 等）
/// 必须继续基于 LayoutBuilder 的真实可用宽度判断，不能套用这里的壳层断点。
abstract final class SlowlightBreakpoints {
  static const double tabletMin = 600;
  static const double desktopMin = 1024;

  /// 旧 wide 断点不再作为独立全局规则；保留兼容入口，避免业务代码瞬间失效。
  @Deprecated('Use desktopMin for shell layout; components must use LayoutBuilder')
  static const double wideMin = desktopMin;
}
