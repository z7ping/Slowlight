import 'package:flutter/material.dart';

/// 不随主题强调色变化、但具有稳定产品语义的固定颜色。
///
/// 主题表面、正文、边框等仍由 Theme / AppTheme 提供；这里只承载需要跨页面
/// 保持身份的语义色，避免 Feature 或 Fx 组件自己写 Color(0x...)。
abstract final class SlowlightSemanticColor {
  static const Color focus = Color(0xFF8B5CF6);
  static const Color successEmphasis = Color(0xFF4ADE80);

  static const Color restGradientStart = Color(0xFF0F2027);
  static const Color restGradientMiddle = Color(0xFF203A43);
  static const Color restGradientEnd = Color(0xFF2C5364);

  /// Dialog 与 Sheet 使用不同遮罩强度，但都由统一语义入口管理。
  static const Color dialogBarrier = Color(0x73000000);
  static const Color sheetBarrier = Color(0xCC000000);
}
