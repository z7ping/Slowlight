import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../typography_tokens.dart';

/// FxInput — 文本输入组件。
///
/// 页面层统一使用 FxInput；内部保留原生 TextField 以保证桌面端中文输入法
/// 的稳定性，但字号、占位文字和标签语义统一由 Slowlight Typography 管理。
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
  final EdgeInsetsGeometry? contentPadding;
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
    final input = TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      obscureText: obscureText,
      enableSuggestions: enableSuggestions,
      autocorrect: autocorrect,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines ?? 1,
      maxLength: maxLength,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      focusNode: focusNode,
      style: style ?? SlowlightTypography.body(context),
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: placeholderStyle ??
            SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
        prefixIcon: leading,
        suffixIcon: trailing,
        border: InputBorder.none,
        isDense: isDense,
        contentPadding: contentPadding ??
            EdgeInsets.symmetric(
              horizontal: leading == null ? 0 : 12,
              vertical: isDense ? 8 : 10,
            ),
      ),
    );

    if (label == null) return input;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: SlowlightTypography.secondary(context).copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        input,
      ],
    );
  }
}
