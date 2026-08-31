import 'package:flutter/material.dart';

import '../layout_tokens.dart';
import '../typography_tokens.dart';
import 'fx_cursor.dart';

/// FxSegmented — 紧凑的互斥分段选择组件。
///
/// 与页面级 Tab 不同，它用于同一区域内少量选项的即时切换。Windows 保持
/// 高保真中的约 36px 总可视高度；Android 的触控尺寸由平台密度层统一解析。
class FxSegmented extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<Key?>? itemKeys;
  final Color? backgroundColor;
  final Color? selectedColor;
  final List<BoxShadow>? selectedShadow;
  final double borderRadius;
  final bool expanded;

  const FxSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.itemKeys,
    this.backgroundColor,
    this.selectedColor,
    this.selectedShadow,
    this.borderRadius = 8,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    assert(labels.isNotEmpty);
    assert(selectedIndex >= 0 && selectedIndex < labels.length);
    assert(itemKeys == null || itemKeys!.length == labels.length);

    final theme = Theme.of(context);
    final itemMinHeight = SlowlightPlatformDensity.segmentedItemMinHeight;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          final item = FxInkWell(
            key: itemKeys?[index],
            borderRadius: BorderRadius.circular(borderRadius - 2),
            onTap: () => onChanged(index),
            child: Container(
              constraints: BoxConstraints(minHeight: itemMinHeight, minWidth: 52),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? selectedColor ?? theme.colorScheme.surface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(borderRadius - 2),
                boxShadow: selected ? selectedShadow : null,
              ),
              child: Text(
                labels[index],
                textAlign: TextAlign.center,
                style: SlowlightTypography.componentChip(context).copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
          return expanded ? Expanded(child: item) : item;
        }),
      ),
    );
  }
}
