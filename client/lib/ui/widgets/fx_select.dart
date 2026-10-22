import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';

/// FxSelect — 统一下拉选择组件。
///
/// Windows / Android 共用 Control 语义字号和最小表单高度，
/// 保留 ShadSelect 提供的 Focus、弹层与键盘交互。
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

  TextStyle _textStyle(BuildContext context) =>
      SlowlightTypography.control(context);

  @override
  Widget build(BuildContext context) {
    final textStyle = _textStyle(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: SlowlightPlatformDensity.inputMinHeight,
      ),
      child: ShadSelect<T>(
        key: ValueKey(value),
        initialValue: value,
        enabled: enabled,
        // 与 FxInput 使用相同的可视高度契约，避免 Select 默认上下内边距
        // 将下拉框撑得比输入框高；字体缩放时仍允许内容向上增长。
        // 实际触发器本身要有上下留白，不能只给外层设置 minHeight：
        // ShadSelect 内部只向触发器传递宽度约束，外层的最低高度不会撑开边框。
        padding: EdgeInsets.symmetric(
          horizontal: SlowlightPlatformDensity.inputHorizontalPadding,
          vertical: SlowlightPlatformDensity.singleLineInputVerticalPadding,
        ),
        trailing: Icon(
          LucideIcons.chevronDown,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
      ),
    );
  }
}

class FxSelectOption<T> {
  final T value;
  final String label;

  const FxSelectOption({required this.value, required this.label});
}
