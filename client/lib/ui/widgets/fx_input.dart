import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';

/// FxInput — 文本输入组件。
///
/// 页面层统一使用 FxInput；底层优先由 shadcn_ui 的 ShadInput 提供输入能力。
/// Fx 不重复绘制 ShadInput 已由主题提供的边框 / Focus Ring；默认字号、占位符
/// 与内边距均由当前平台 Theme / SlowlightTypography 解析，组件本身不判断平台。
class FxInput extends StatelessWidget {
  // 字段标签与输入区的历史高保真内部几何，不扩散为共享 spacing。
  static const double _labelGap = 6;

  final TextEditingController? controller;
  final String? placeholder;
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onPressedOutside;
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

  const FxInput({
    super.key,
    this.controller,
    this.placeholder,
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.onPressedOutside,
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final multiline = maxLines != 1 || (minLines != null && minLines! > 1);
    final input = ShadInput(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onPressedOutside: onPressedOutside,
      onEditingComplete: onEditingComplete,
      obscureText: obscureText,
      enableSuggestions: enableSuggestions,
      autocorrect: autocorrect,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      focusNode: focusNode,
      style: style ?? SlowlightTypography.control(context),
      inputFormatters: inputFormatters,
      placeholder: placeholder == null ? null : Text(placeholder!),
      placeholderStyle:
          placeholderStyle ??
          SlowlightTypography.control(
            context,
          ).copyWith(color: theme.colorScheme.onSurfaceVariant),
      leading: leading,
      trailing: trailing,
      // 单行高度由下方完整 FxInput 约束；多行保留编辑区垂直留白。
      // 显式 contentPadding 仅供已确认的特殊场景使用。
      padding: contentPadding ??
          (multiline
              ? EdgeInsets.symmetric(
                  horizontal: SlowlightPlatformDensity.inputHorizontalPadding,
                  vertical: SlowlightPlatformDensity.multilineInputVerticalPadding,
                )
              : null),
    );

    // 最低可视高度约束在完整 ShadInput 外，不作用于内部文本区域。
    // 字体缩放可自然撑高，尾部图标显隐不会导致外框高度跳变。
    final field = multiline
        ? input
        : ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: SlowlightPlatformDensity.inputMinHeight,
            ),
            child: input,
          );

    if (label == null) return field;
    final labelStyle = SlowlightTypography.fieldLabel(
      context,
    ).copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: labelStyle),
        const SizedBox(height: _labelGap),
        field,
      ],
    );
  }
}
