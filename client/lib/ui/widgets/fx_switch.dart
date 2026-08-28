import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../ui/app_theme.dart';

/// FxSwitch — 开关组件
class FxSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;

  const FxSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return ShadSwitch(
      value: value,
      onChanged: onChanged,
      label: label != null ? Text(label!, style: const TextStyle(fontSize: AppTheme.textMd, height: 1.5)) : null,
    );
  }
}
