import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../typography_tokens.dart';

/// FxTab — 标签切换组件。
///
/// Android 使用可读字号；桌面端继承 ShadTabs 既有文字视觉。
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
    final android = SlowlightTypography.useAndroidComponentTypography;
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
              Text(
                tab.label,
                style: android
                    ? SlowlightTypography.secondary(context).copyWith(
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }
}

class FxTabItem {
  final String label;
  final IconData? icon;
  final Widget? content;

  const FxTabItem({required this.label, this.icon, this.content});
}
