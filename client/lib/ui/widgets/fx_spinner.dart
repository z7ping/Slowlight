import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Slowlight 统一不确定等待指示器。
///
/// 使用 Lucide loader 图形和 Flutter 动画基础设施，不依赖 Material
/// CircularProgressIndicator。
class FxSpinner extends StatefulWidget {
  const FxSpinner({
    super.key,
    this.size = 20,
    this.strokeWidth = 2,
    this.color,
    this.semanticsLabel = '加载中',
  });

  final double size;
  final double strokeWidth;
  final Color? color;
  final String? semanticsLabel;

  @override
  State<FxSpinner> createState() => _FxSpinnerState();
}

class _FxSpinnerState extends State<FxSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Semantics(
      label: widget.semanticsLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: RotationTransition(
          turns: _controller,
          child: Icon(
            LucideIcons.loaderCircle,
            size: widget.size,
            color: widget.color ?? theme.colorScheme.foreground,
            weight: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}
