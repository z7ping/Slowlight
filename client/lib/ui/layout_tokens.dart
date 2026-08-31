/// Slowlight 通用布局 Token。
///
/// 这里只保留跨页面、跨组件确实需要共享的基础尺度。Feature 私有几何值
/// （例如日历格高、侧栏宽度、某个弹窗宽度）应留在对应组件内部，避免
/// 为了消除数字而制造没有产品语义的“伪通用” Token。
abstract final class SlowlightSpacing {
  // TODO(fx-visual-regression): 旧命名仍被大量现有代码引用；逐组件恢复视觉时
  // 迁移到 4 / 8 / 12 / 16 / 24 基础间距后，再删除这些兼容项。禁止新增引用。
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
  /// Android 的最低触控目标。桌面组件不能直接用它撑大可见尺寸或布局高度。
  static const double minTouchTarget = 44;

  static const double buttonSm = 32;
  static const double button = 36;
  static const double buttonLg = 40;
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
