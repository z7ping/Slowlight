import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';

/// FxInput — 文本输入组件。
///
/// 页面层统一使用 FxInput；底层优先由 shadcn_ui 的 ShadInput 提供输入能力。
/// Fx 不重复绘制 ShadInput 已由主题提供的边框 / Focus Ring，避免 Windows
/// 出现双层框线。平台差异只保留可读性与密度所需的输入内容尺寸。
class FxInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? placeholder;
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget? leading;
  final Widget? trailing;
  final TextStyle? style;
  final TextStyle? placeholderStyle;
  final List<TextInputFormatter>? inputFormatters;
  final EdgeInsets? contentPadding;
  final bool isDense;

  const FxInput({
    super.key,
    this.controller,
    this.placeholder,
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.keyboardType,
    this.textInputAction,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.leading,
    this.trailing,
    this.style,
    this.placeholderStyle,
    this.inputFormatters,
    this.contentPadding,
    this.isDense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useAndroidTypography =
        SlowlightTypography.useAndroidComponentTypography;
    final input = ShadInput(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      obscureText: obscureText,
      enableSuggestions: enableSuggestions,
      autocorrect: autocorrect,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: maxLines ?? 1,
      maxLength: maxLength,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      focusNode: focusNode,
      style:
          style ??
          (useAndroidTypography ? SlowlightTypography.body(context) : null),
      inputFormatters: inputFormatters,
      placeholder: placeholder == null ? null : Text(placeholder!),
      placeholderStyle:
          placeholderStyle ??
          (useAndroidTypography
              ? SlowlightTypography.control(
                  context,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant)
              : null),
      leading: leading,
      trailing: trailing,
      padding:
          contentPadding ??
          EdgeInsets.symmetric(
            horizontal: useAndroidTypography ? 14 : 12,
            vertical: useAndroidTypography ? (isDense ? 9 : 12) : 8,
          ),
    );

    if (label == null) return input;
    final labelStyle = useAndroidTypography
        ? SlowlightTypography.fieldLabel(
            context,
          ).copyWith(color: theme.colorScheme.onSurfaceVariant)
        : TextStyle(
            fontSize: SlowlightTypography.desktopControlSize,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurfaceVariant,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: labelStyle),
        const SizedBox(height: SlowlightSpacing.sm),
        input,
      ],
    );
  }
}
