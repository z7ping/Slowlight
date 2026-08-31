import 'package:flutter/material.dart';

import 'layout_tokens.dart';

/// 窗口级响应式布局工具。
///
/// 全局设备档位只使用 SlowlightBreakpoints；组件内部能否横排仍应通过
/// LayoutBuilder 判断自身真实可用宽度，不得把窗口档位代替组件级响应式。
class ResponsiveLayout {
  static double widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isMobile(BuildContext context) =>
      widthOf(context) < SlowlightBreakpoints.tabletMin;

  static bool isTablet(BuildContext context) {
    final width = widthOf(context);
    return width >= SlowlightBreakpoints.tabletMin &&
        width < SlowlightBreakpoints.desktopMin;
  }

  static bool isDesktop(BuildContext context) {
    final width = widthOf(context);
    return width >= SlowlightBreakpoints.desktopMin &&
        width < SlowlightBreakpoints.wideMin;
  }

  static bool isWide(BuildContext context) =>
      widthOf(context) >= SlowlightBreakpoints.wideMin;

  /// 桌面 Shell、左右分栏等“桌面及以上”行为使用此判断。
  static bool isDesktopOrWider(BuildContext context) =>
      widthOf(context) >= SlowlightBreakpoints.desktopMin;

  static Widget build(
    BuildContext context, {
    required Widget mobile,
    Widget? tablet,
    required Widget desktop,
    Widget? wide,
  }) {
    if (isWide(context)) return wide ?? desktop;
    if (isDesktop(context)) return desktop;
    if (isTablet(context) && tablet != null) return tablet;
    return mobile;
  }

  static int gridColumns(BuildContext context) {
    if (isWide(context)) return 4;
    if (isDesktop(context)) return 3;
    if (isTablet(context)) return 2;
    return 1;
  }
}
