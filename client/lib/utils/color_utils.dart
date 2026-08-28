import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../ui/app_theme.dart';

/// 颜色工具类
class ColorUtils {
  ColorUtils._();

  /// 解析 hex 颜色字符串为 Color
  static Color parseHex(String hexColor) {
    var hex = hexColor.replaceAll('#', '').replaceAll(' ', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  /// 安全解析，失败返回 fallback
  static Color safeParse(String hexColor, {Color? fallback}) {
    try {
      return parseHex(hexColor);
    } catch (e) {
      return fallback ?? AppTheme.warmGray500;
    }
  }
}
