import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../color_tokens.dart';
import '../layout_tokens.dart';
import '../typography_tokens.dart';

/// FxDialog — 统一弹窗入口。
class FxDialog {
  static const Color barrierColor = SlowlightSemanticColor.dialogBarrier;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    String? description,
    double? width,
    bool barrierDismissible = true,
  }) {
    return showShadDialog<T>(
      context: context,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (ctx) => ShadDialog(
        title: title != null
            ? Text(
                title,
                style: SlowlightTypography.cardTitle(ctx).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
        description: description != null
            ? Text(
                description,
                style: SlowlightTypography.secondary(ctx).copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        constraints: width != null ? BoxConstraints(maxWidth: width) : null,
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }

  /// Material showDialog 的 Fx 兼容入口。
  ///
  /// 业务 builder 应返回 FxAlertDialog / FxDialogSurface 或其他 Fx 内容。
  static Future<T?> raw<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
    String? barrierLabel,
    bool useSafeArea = true,
    bool useRootNavigator = true,
    RouteSettings? routeSettings,
    Offset? anchorPoint,
    Object? traversalEdgeBehavior,
    bool? requestFocus,
    Object? animationStyle,
  }) {
    return showShadDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? FxDialog.barrierColor,
      barrierLabel: barrierLabel ??
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      builder: (dialogContext) {
        final child = builder(dialogContext);
        return useSafeArea ? SafeArea(child: child) : child;
      },
    );
  }

  /// 确认弹窗。
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String content,
    String confirmText = '确认',
    String cancelText = '取消',
    bool destructive = false,
    bool barrierDismissible = true,
  }) {
    return showShadDialog<bool>(
      context: context,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      variant:
          destructive ? ShadDialogVariant.alert : ShadDialogVariant.primary,
      builder: (ctx) => ShadDialog(
        title: Text(
          title,
          style: SlowlightTypography.cardTitle(ctx).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        description: Text(
          content,
          style: SlowlightTypography.secondary(ctx).copyWith(
            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(cancelText, style: SlowlightTypography.button),
          ),
          destructive
              ? ShadButton.destructive(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                  child: Text(confirmText, style: SlowlightTypography.button),
                )
              : ShadButton(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                  child: Text(confirmText, style: SlowlightTypography.button),
                ),
        ],
      ),
    );
  }
}

/// Material AlertDialog 的 Fx 兼容表面。
class FxAlertDialog extends StatelessWidget {
  const FxAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.actionsAlignment,
    this.actionsOverflowAlignment,
    this.actionsOverflowDirection,
    this.actionsOverflowButtonSpacing,
    this.buttonPadding,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.semanticLabel,
    this.insetPadding,
    this.clipBehavior = Clip.none,
    this.shape,
    this.alignment,
    this.scrollable = false,
    this.titlePadding,
    this.contentPadding = const EdgeInsets.fromLTRB(
      SlowlightSpacing.page,
      SlowlightSpacing.section,
      SlowlightSpacing.page,
      SlowlightSpacing.page,
    ),
    this.actionsPadding = EdgeInsets.zero,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final MainAxisAlignment? actionsAlignment;
  final OverflowBarAlignment? actionsOverflowAlignment;
  final VerticalDirection? actionsOverflowDirection;
  final double? actionsOverflowButtonSpacing;
  final EdgeInsetsGeometry? buttonPadding;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final String? semanticLabel;
  final EdgeInsets? insetPadding;
  final Clip clipBehavior;
  final ShapeBorder? shape;
  final AlignmentGeometry? alignment;
  final bool scrollable;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry actionsPadding;

  BorderRadius? get _radius {
    final currentShape = shape;
    if (currentShape is RoundedRectangleBorder &&
        currentShape.borderRadius is BorderRadius) {
      return currentShape.borderRadius as BorderRadius;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Widget? effectiveContent = content;
    if (effectiveContent != null) {
      effectiveContent = Padding(
        padding: contentPadding,
        child: effectiveContent,
      );
    }
    Widget? effectiveTitle = title;
    if (effectiveTitle != null && titlePadding != null) {
      effectiveTitle = Padding(padding: titlePadding!, child: effectiveTitle);
    }
    if (icon != null) {
      effectiveTitle = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon!,
          if (effectiveTitle != null) ...[
            const SizedBox(width: SlowlightSpacing.md),
            Flexible(child: effectiveTitle),
          ],
        ],
      );
    }

    return Semantics(
      label: semanticLabel,
      child: ShadDialog.alert(
        title: effectiveTitle,
        child: effectiveContent,
        actions: actions ?? const [],
        actionsMainAxisAlignment: actionsAlignment,
        backgroundColor: backgroundColor,
        radius: _radius,
        alignment: alignment is Alignment ? alignment as Alignment : null,
        scrollable: scrollable,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Material Dialog 的 Fx 兼容表面。
class FxDialogSurface extends StatelessWidget {
  const FxDialogSurface({
    super.key,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.insetAnimationDuration = const Duration(milliseconds: 100),
    this.insetAnimationCurve = Curves.decelerate,
    this.insetPadding,
    this.clipBehavior = Clip.none,
    this.shape,
    this.alignment,
    this.child,
  });

  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final Duration insetAnimationDuration;
  final Curve insetAnimationCurve;
  final EdgeInsets? insetPadding;
  final Clip clipBehavior;
  final ShapeBorder? shape;
  final AlignmentGeometry? alignment;
  final Widget? child;

  BorderRadius? get _radius {
    final currentShape = shape;
    if (currentShape is RoundedRectangleBorder &&
        currentShape.borderRadius is BorderRadius) {
      return currentShape.borderRadius as BorderRadius;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      backgroundColor: backgroundColor,
      radius: _radius,
      alignment: alignment is Alignment ? alignment as Alignment : null,
      child: child,
    );
  }
}
