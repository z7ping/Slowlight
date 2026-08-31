import 'package:flutter/material.dart';

/// 不随主题强调色变化、但具有稳定产品语义的固定颜色。
///
/// 主题表面、正文、边框等仍由 Theme / AppTheme 提供；这里只承载需要跨页面
/// 保持身份的语义色，避免 Feature 自己写 Color(0x...)。
abstract final class SlowlightSemanticColor {
  static const Color focus = Color(0xFF8B5CF6);
  static const Color successEmphasis = Color(0xFF4ADE80);
}
