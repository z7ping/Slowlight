import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';

/// FxInput — 文本输入组件
/// 页面层统一使用 FxInput；内部使用原生 TextField 以保持桌面端中文输入稳定。
class FxInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? placeholder;
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final bool obscureText;
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
    // 如果有 label，用 Column 包裹
    final input = TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines ?? 1,
      maxLength: maxLength,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      focusNode: focusNode,
      style: style,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: placeholderStyle,
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

    if (label != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label!,
              style: TextStyle(
                  fontSize: AppTheme.textMd,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.warmGray500)),
          const SizedBox(height: 6),
          input,
        ],
      );
    }

    return input;
  }
}
