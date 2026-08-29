import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/widgets/fx_card.dart';
import '../../ui/widgets/fx_chip.dart';
import '../../ui/widgets/fx_empty_state.dart';
import '../../ui/widgets/fx_section_header.dart';
import '../../ui/widgets/fx_segmented.dart';
import '../../ui/widgets/fx_stat_cell.dart';

Color hfSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF111113);

/// 原型中的边框色：用于卡片、输入框、按钮边界。
Color hfBorder(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFE4E4E7)
        : const Color(0xFF27272A);

/// 原型中的分隔线色：比边框更弱，用于列表/区块分隔。
Color hfDivider(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF1F1F23);

Color hfSubtleSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF27272A);

/// 兼容旧高保真调用；新代码请直接使用 FxCard。
@Deprecated('Use FxCard instead')
class HfCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Border? border;
  final Color? color;
  final VoidCallback? onTap;

  const HfCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.border,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FxCard(
      padding: padding,
      color: color ?? hfSurface(context),
      borderRadius: AppTheme.radiusLg,
      border: border ?? Border.all(color: hfBorder(context)),
      boxShadow:
          Theme.of(context).brightness == Brightness.light ? AppTheme.cardShadow : null,
      expanded: true,
      onTap: onTap,
      child: child,
    );
  }
}

/// 兼容旧高保真调用；新代码请直接使用 FxSectionHeader。
@Deprecated('Use FxSectionHeader instead')
class HfSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? trailingWidget;

  const HfSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return FxSectionHeader(
      title: title,
      trailing: trailing,
      trailingWidget: trailingWidget,
    );
  }
}

/// 兼容旧高保真调用；新代码请直接使用 FxSegmented。
@Deprecated('Use FxSegmented instead')
class HfSegmented extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const HfSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FxSegmented(
      labels: labels,
      selectedIndex: selectedIndex,
      onChanged: onChanged,
      backgroundColor: hfSubtleSurface(context),
      selectedColor: hfSurface(context),
      selectedShadow: theme.brightness == Brightness.light
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: .06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
      borderRadius: AppTheme.radiusMd,
    );
  }
}

/// 兼容旧高保真调用；新代码请直接使用 FxStatCell。
@Deprecated('Use FxStatCell instead')
class HfStatCell extends StatelessWidget {
  final String value;
  final String label;
  final String? suffix;

  const HfStatCell({
    super.key,
    required this.value,
    required this.label,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return FxStatCell(
      value: value,
      label: label,
      suffix: suffix,
      backgroundColor: hfSurface(context),
      border: Border.all(color: hfBorder(context)),
      borderRadius: AppTheme.radiusLg,
    );
  }
}

/// 兼容旧高保真调用；新代码请直接使用 FxChip。
@Deprecated('Use FxChip instead')
class HfChip extends StatelessWidget {
  final String label;
  final bool accent;

  const HfChip(this.label, {super.key, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FxChip(
      label: label,
      backgroundColor: accent
          ? activePalette.accent.withValues(alpha: .12)
          : hfSubtleSurface(context),
      foregroundColor:
          accent ? activePalette.accent : theme.colorScheme.onSurfaceVariant,
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    );
  }
}

class HfTimelineItem extends StatelessWidget {
  final Color color;
  final String time;
  final String title;
  final String? note;
  final bool last;

  const HfTimelineItem({
    super.key,
    required this.color,
    required this.time,
    required this.title,
    this.note,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 1, color: hfDivider(context)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      note!,
                      style: TextStyle(
                        fontSize: AppTheme.textXs,
                        height: 1.45,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 兼容旧高保真调用；新代码请直接使用 FxEmptyState。
@Deprecated('Use FxEmptyState instead')
class HfEmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Widget? action;

  const HfEmptyState({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return FxEmptyState(
      emoji: emoji,
      title: title,
      subtitle: subtitle,
      action: action,
      padding: const EdgeInsets.symmetric(vertical: 54),
      emojiSize: 30,
    );
  }
}
