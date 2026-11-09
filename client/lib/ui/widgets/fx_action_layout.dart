import 'package:flutter/material.dart';

import '../layout_tokens.dart';
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
  // Legacy constructor argument retained for callers; width no longer decides wrapping.
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

    // Let Flutter measure the two real children. A fixed device/scale
    // breakpoint could push a short action to a second row on 320–393dp.
    // OverflowBar retains the left/right anchors and naturally stacks only
    // when the children and their gap cannot fit.
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: gap,
      overflowSpacing: runSpacing,
      children: [leading!, _actionGroup()],
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
