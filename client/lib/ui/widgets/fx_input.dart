import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../app_theme.dart';
import '../typography_tokens.dart';

/// FxInput — 文本输入组件。
///
/// 页面层统一使用 FxInput；底层统一由 shadcn_ui 的 ShadInput 提供输入能力，
/// Slowlight 只在 Fx 层管理语义排版、尺寸和装饰。
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
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    final shadTheme = ShadTheme.of(context);
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
      style: style ?? SlowlightTypography.body(context),
      inputFormatters: inputFormatters,
      placeholder: placeholder == null ? null : Text(placeholder!),
      placeholderStyle: placeholderStyle ??
          SlowlightTypography.secondary(context).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
      leading: leading,
      trailing: trailing,
      padding: contentPadding ??
          EdgeInsets.symmetric(
            horizontal: 12,
            vertical: isDense ? 9 : 11,
          ),
      decoration: ShadDecoration(
        color: enabled
            ? shadTheme.colorScheme.background
            : shadTheme.colorScheme.muted,
        border: ShadBorder.all(
          color: shadTheme.colorScheme.border,
          width: 1,
          radius: radius,
        ),
        focusedBorder: ShadBorder.all(
          color: shadTheme.colorScheme.ring,
          width: 1.5,
          radius: radius,
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
