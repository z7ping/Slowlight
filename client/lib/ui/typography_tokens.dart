import 'package:flutter/material.dart';

/// Slowlight 语义排版 Token。
///
/// 页面和业务组件应优先表达“这段文字是什么”，而不是自行选择字号。
/// 同一字号可以承担不同语义，但字重、行高和使用场景由 Token 统一管理，
/// 避免 Windows / Android 因页面各自硬编码而出现层级和密度漂移。
abstract final class SlowlightTypography {
  static const double captionSize = 12;
  static const double captionLineHeight = 16;

  static const double secondarySize = 14;
  static const double secondaryLineHeight = 20;

  /// 表单字段名：清单、优先级、标签、提醒等。
  static const double fieldLabelSize = 14;
  static const double fieldLabelLineHeight = 20;

  /// 选择器、下拉项及其他紧凑控件正文。
  static const double controlSize = 14;
  static const double controlLineHeight = 20;

  /// 标签 / 选择 Chip。保持可读，不再退回历史 12–13px 小字号。
  static const double chipSize = 14;
  static const double chipLineHeight = 20;

  /// “查看全部 / 编辑 / 更多”等区块级紧凑操作。
  static const double compactActionSize = 14;
  static const double compactActionLineHeight = 20;

  static const double buttonSize = 15;
  static const double buttonLineHeight = 20;

  static const double bodySize = 16;
  static const double bodyLineHeight = 24;

  static const double cardTitleSize = 16;
  static const double cardTitleLineHeight = 24;

  static const double pageTitleSize = 20;
  static const double pageTitleLineHeight = 28;

  static const double heroSize = 24;
  static const double heroLineHeight = 32;

  static double _height(double size, double lineHeight) => lineHeight / size;

  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
            fontSize: captionSize,
            height: _height(captionSize, captionLineHeight),
          );

  static TextStyle secondary(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: secondarySize,
            height: _height(secondarySize, secondaryLineHeight),
          );

  static TextStyle fieldLabel(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
            fontSize: fieldLabelSize,
            height: _height(fieldLabelSize, fieldLabelLineHeight),
            fontWeight: FontWeight.w600,
          );

  static TextStyle control(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: controlSize,
            height: _height(controlSize, controlLineHeight),
          );

  static TextStyle chip(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
            fontSize: chipSize,
            height: _height(chipSize, chipLineHeight),
            fontWeight: FontWeight.w500,
          );

  static TextStyle compactAction(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
            fontSize: compactActionSize,
            height: _height(compactActionSize, compactActionLineHeight),
            fontWeight: FontWeight.w600,
          );

  /// 主按钮仅规定字号、行高和字重，不指定颜色。
  /// 颜色继续由 ShadButton / 当前 variant 的 DefaultTextStyle 决定。
  static TextStyle get button => TextStyle(
        fontSize: buttonSize,
        height: _height(buttonSize, buttonLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
            fontSize: bodySize,
            height: _height(bodySize, bodyLineHeight),
          );

  static TextStyle cardTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall!.copyWith(
            fontSize: cardTitleSize,
            height: _height(cardTitleSize, cardTitleLineHeight),
            fontWeight: FontWeight.w600,
          );

  static TextStyle pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.copyWith(
            fontSize: pageTitleSize,
            height: _height(pageTitleSize, pageTitleLineHeight),
            fontWeight: FontWeight.w600,
          );

  static TextStyle hero(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontSize: heroSize,
            height: _height(heroSize, heroLineHeight),
            fontWeight: FontWeight.w600,
          );
}
