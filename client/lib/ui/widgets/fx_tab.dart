import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// FxTab — 标签切换组件
class FxTab extends StatelessWidget {
  final List<FxTabItem> tabs;
  final int currentIndex;
  final ValueChanged<int>? onChanged;

  const FxTab({
    super.key,
    required this.tabs,
    required this.currentIndex,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ShadTabs<String>(
      value: currentIndex.toString(),
      onChanged: (value) => onChanged?.call(int.parse(value)),
      tabs: tabs.asMap().entries.map((entry) {
        final tab = entry.value;
        return ShadTab<String>(
          value: entry.key.toString(),
          content: tab.content,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tab.icon != null) ...[
                Icon(tab.icon, size: 16),
                const SizedBox(width: 6),
              ],
              Text(tab.label),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class FxTabItem {
  final String label;
  final IconData? icon;
  final Widget? content;
  const FxTabItem({required this.label, this.icon, this.content});
}
