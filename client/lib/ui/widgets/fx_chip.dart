import 'fx_cursor.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxChip — 标签/徽章组件（用 ShadBadge 实现）
class FxChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final FxChipVariant variant;

  const FxChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.onDeleted,
    this.variant = FxChipVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final badge = ShadBadge(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14),
            const SizedBox(width: 4),
          ],
          Flexible(child: Text(label)),
          if (onDeleted != null) ...[
            const SizedBox(width: 4),
            FxGestureDetector(
              onTap: onDeleted,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Icon(Icons.close, size: 14)),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return FxGestureDetector(onTap: onTap, child: badge);
    }
    return badge;
  }
}

enum FxChipVariant { primary, secondary, outline, destructive }
