import 'package:flutter/material.dart';

import '../../ui/widgets/fx_page_header.dart';

/// 旧高保真页头兼容层。
///
/// 新代码必须直接使用 [FxPageHeader]；保留此适配器仅用于渐进迁移现有调用方。
@Deprecated('Use FxPageHeader from ui/fx.dart instead.')
class HfPageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  const HfPageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return FxPageHeader(
      title: title,
      onBack: onBack,
      trailing: trailing,
      actionIcon: actionIcon,
      actionTooltip: actionTooltip,
      onAction: onAction,
    );
  }
}
