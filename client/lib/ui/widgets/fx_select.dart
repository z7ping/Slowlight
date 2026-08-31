import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxSelect — 统一下拉选择组件。
///
/// Android 使用 Control 语义字号；桌面端继承 ShadSelect 的既有文字视觉，
/// 避免 Fx 化把 Windows 下拉项统一放大。
class FxSelect<T> extends StatelessWidget {
  final T? value;
  final List<FxSelectOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? placeholder;
  final bool enabled;

  const FxSelect({
    super.key,
    this.value,
    required this.options,
    this.onChanged,
    this.placeholder,
    this.enabled = true,
  });

  TextStyle? _textStyle(BuildContext context) =>
      SlowlightTypography.useAndroidComponentTypography
          ? SlowlightTypography.control(context)
          : null;

  @override
  Widget build(BuildContext context) {
    final textStyle = _textStyle(context);
    return ShadSelect<T>(
      key: ValueKey(value),
      initialValue: value,
      enabled: enabled,
      placeholder:
          placeholder != null ? Text(placeholder!, style: textStyle) : null,
      onChanged: enabled ? onChanged : null,
      selectedOptionBuilder: (context, value) {
        final opt = options.firstWhere((o) => o.value == value);
        return Text(opt.label, style: textStyle);
      },
      options: options
          .map(
            (opt) => ShadOption(
              value: opt.value,
              child: Text(opt.label, style: textStyle),
            ),
          )
          .toList(growable: false),
    );
  }
}

class FxSelectOption<T> {
  final T value;
  final String label;

  const FxSelectOption({required this.value, required this.label});
}
