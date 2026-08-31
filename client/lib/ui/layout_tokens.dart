/// Slowlight 通用布局 Token。
///
/// 这里只放跨页面、跨组件需要保持一致的基础尺度；日历格高、侧栏宽度、
/// 图表绘制尺寸等明确属于单个 Feature 的几何值继续留在 Feature 内，避免
/// 为了“数字清零”制造没有产品语义的 Token。
abstract final class SlowlightSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double xxl = 14;
  static const double xxxl = 16;
  static const double section = 20;
  static const double page = 24;
  static const double spacious = 32;
}

abstract final class SlowlightRadius {
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double sheet = 18;
  static const double pill = 999;
}

/// Slowlight 可操作控件的共同尺寸。
abstract final class SlowlightControlSize {
  /// Android / Windows 共同采用的最小主要点击区域。
  static const double minTouchTarget = 44;

  static const double buttonSm = 32;
  static const double button = 36;
  static const double buttonLg = 40;
}

abstract final class SlowlightIconSize {
  static const double xs = 14;

  /// 紧凑文字操作中的配套图标，保持现有视觉比例。
  static const double compactAction = 15;

  static const double sm = 16;
  static const double md = 18;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 30;
}

/// 全局窗口级断点。
///
/// 组件内部若只关心“当前真实可用宽度能否容纳内容”，应继续使用 LayoutBuilder
/// 和自身的内容阈值，不要把这些窗口断点拿来替代组件级响应式判断。
abstract final class SlowlightBreakpoints {
  /// mobile: < 600
  static const double tabletMin = 600;

  /// tablet: 600–899；desktop: 900–1199
  static const double desktopMin = 900;

  /// wide: >= 1200
  static const double wideMin = 1200;
}
