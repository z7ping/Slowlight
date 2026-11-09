import 'package:flutter/material.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';
import 'fx_button.dart';

/// Slowlight 操作区布局规则。
///
/// 适用范围：页面内容区顶部工具栏、列表/筛选标题行、卡片顶部主操作、
/// Dialog / Sheet 底部操作区。
///
/// 规则：
/// 1. 上下文、筛选、计数等信息在左；创建/保存/查看等动作在右。
/// 2. 禁止使用 WrapAlignment.spaceBetween 让按钮“碰巧”落在右侧；
///    动作区必须有明确的右侧锚点。
/// 3. 空间不足或大字体时，上下文留在上一行，动作整体下移并继续右对齐。
/// 4. 多个动作按“次要 → 主要”从左到右排列，主要动作永远最右。
/// 5. 删除等破坏性动作只有在编辑型 Footer 中可通过 leading 独立放左侧；
///    普通 Dialog 的取消/确认仍作为一组靠右。
/// 6. 空状态 CTA、正文内联动作、卡片行内动作不属于本规则，不强制靠边。
class FxActionBar extends StatelessWidget {
  final Widget? leading;
  final List<Widget> actions;
  final double stackBelow;
  final double gap;
  final double runSpacing;

  const FxActionBar({
    super.key,
    this.leading,
    required this.actions,
    this.stackBelow = 520,
    this.gap = SlowlightSpacing.xl,
    this.runSpacing = SlowlightSpacing.md,
  });

  // Short explanatory copy and a single button often fit at 360dp.
  // Measure their actual text rather than automatically stacking below 520dp.
  // Composite filters/menus keep the existing conservative behavior.
  bool _simpleActionFits(BuildContext context, double width) {
    final copy = leading;
    if (copy is! Text || copy.data == null || actions.length != 1) return false;
    final action = actions.single;
    if (action is! FxButton) return false;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final copyPainter = TextPainter(
      text: TextSpan(
        text: copy.data!,
        style: copy.style ?? SlowlightTypography.componentSecondary(context),
      ),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final buttonPainter = TextPainter(
      text: TextSpan(
        text: action.label,
        style: SlowlightTypography.componentButton(
          context,
          compact: action.size == FxButtonSize.sm,
        ),
      ),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final buttonIconWidth = action.icon != null || action.leading != null
        ? (action.size == FxButtonSize.sm
            ? SlowlightIconSize.compactAction + 6
            : SlowlightIconSize.sm + SlowlightSpacing.md)
        : 0.0;
    final buttonPadding = action.size == FxButtonSize.sm ? 28.0 : 36.0;
    final requiredWidth = copyPainter.width + gap +
        buttonPainter.width + buttonIconWidth + buttonPadding + 20;
    copyPainter.dispose();
    buttonPainter.dispose();
    return requiredWidth <= width;
  }

  Widget _actionGroup() {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: gap,
      runSpacing: runSpacing,
      children: actions,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (leading == null) {
      return SizedBox(
        width: double.infinity,
        child: Align(alignment: Alignment.centerRight, child: _actionGroup()),
      );
    }
    if (actions.isEmpty) return leading!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final compactFits = scale < 1.6 &&
            _simpleActionFits(context, constraints.maxWidth);
        final stacked = !compactFits &&
            (constraints.maxWidth < stackBelow || scale >= 1.6);

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              leading!,
              SizedBox(height: runSpacing),
              Align(alignment: Alignment.centerRight, child: _actionGroup()),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: leading!),
            SizedBox(width: gap),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: _actionGroup(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Dialog / Sheet 底部动作的语义别名。
///
/// 无 leading 时所有动作右对齐；需要把“删除”与“保存”分开时，
/// 仅把删除放入 leading，保存仍是最右动作。
class FxDialogActions extends StatelessWidget {
  final Widget? leading;
  final List<Widget> actions;
  final double stackBelow;

  const FxDialogActions({
    super.key,
    this.leading,
    required this.actions,
    this.stackBelow = 440,
  });

  @override
  Widget build(BuildContext context) {
    return FxActionBar(
      leading: leading,
      actions: actions,
      stackBelow: stackBelow,
      gap: SlowlightSpacing.md,
      runSpacing: SlowlightSpacing.md,
    );
  }
}
