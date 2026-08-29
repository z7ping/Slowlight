import 'package:flutter/material.dart';

/// Slowlight 语义排版 Token。
///
/// 页面和业务组件应优先表达“这段文字是什么”，而不是自行选择字号。
/// 这里仅定义跨页面稳定的语义尺度；真正页面独有的视觉需求应有明确理由，
/// 不通过新增一组近似字号解决。
abstract final class SlowlightTypography {
  static const double captionSize = 12;
  static const double captionLineHeight = 16;

  static const double secondarySize = 14;
  static const double secondaryLineHeight = 20;

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

  static TextStyle button(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!.copyWith(
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
