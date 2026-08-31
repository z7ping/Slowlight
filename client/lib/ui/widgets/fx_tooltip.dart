import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 统一辅助提示组件。
///
/// 产品 Tooltip 直接走 shadcn_ui，不再通过 Material Tooltip 形成第二套视觉。
class FxTooltip extends StatelessWidget {
  const FxTooltip({
    super.key,
    required this.child,
    required this.message,
    this.waitDuration,
    this.showDuration,
    this.focusNode,
  });

  final Widget child;
  final String message;
  final Duration? waitDuration;
  final Duration? showDuration;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return ShadTooltip(
      waitDuration: waitDuration,
      showDuration: showDuration,
      focusNode: focusNode,
      builder: (_) => Text(message),
      child: child,
    );
  }
}
