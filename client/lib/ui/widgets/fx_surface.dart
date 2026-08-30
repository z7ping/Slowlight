import 'package:flutter/material.dart';

/// Fx 层统一管理的基础表面颜色。
Color fxSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF111113);

/// 卡片、输入框和按钮边界使用的基础边框色。
Color fxBorder(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFE4E4E7)
        : const Color(0xFF27272A);

/// 列表和区块内部使用的弱分隔线色。
Color fxDivider(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF1F1F23);

/// 低强调背景表面。
Color fxSubtleSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF27272A);
