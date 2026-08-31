import 'package:flutter/material.dart';

/// Fx 层统一管理的基础表面颜色；具体明暗值来自当前 Theme，而不是 Fx 再维护一套固定色。
Color fxSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLowest;

/// 卡片、输入框和按钮边界使用的基础边框色。
Color fxBorder(BuildContext context) => Theme.of(context).colorScheme.outline;

/// 列表和区块内部使用的弱分隔线色。
Color fxDivider(BuildContext context) =>
    Theme.of(context).colorScheme.outlineVariant;

/// 低强调背景表面。
Color fxSubtleSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerLow;
