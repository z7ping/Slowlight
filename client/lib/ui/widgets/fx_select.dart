import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxSelect — 统一下拉选择组件。
class FxSelect<T> extends StatelessWidget {
  final T? value;
  final List<FxSelectOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? placeholder;

  const FxSelect({
    super.key,
    this.value,
    required this.options,
    this.onChanged,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = SlowlightTypography.secondary(context);
    return ShadSelect<T>(
      key: ValueKey(value),
      initialValue: value,
      placeholder:
          placeholder != null ? Text(placeholder!, style: textStyle) : null,
      onChanged: onChanged,
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
