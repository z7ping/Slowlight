import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

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
    final radius = BorderRadius.circular(AppTheme.radiusLg);
    final cardColor = color ?? hfSurface(context);
    final cardBorder = border ?? Border.all(color: hfBorder(context));
    final body = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: radius,
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? AppTheme.cardShadow
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: cardColor,
            border: cardBorder,
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: body,
    );
  }
}

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
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTheme.textXs,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (trailingWidget != null) trailingWidget!,
      ],
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: hfSubtleSurface(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onChanged(index),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 52),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? hfSurface(context) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: selected && theme.brightness == Brightness.light
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: AppTheme.textSm,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: hfSurface(context),
        border: Border.all(color: hfBorder(context)),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              children: [
                TextSpan(text: value),
                if (suffix != null)
                  TextSpan(
                    text: suffix,
                    style: TextStyle(
                      fontSize: AppTheme.textSm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTheme.textXs,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class HfChip extends StatelessWidget {
  final String label;
  final bool accent;

  const HfChip(this.label, {super.key, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: accent
            ? activePalette.accent.withValues(alpha: .12)
            : hfSubtleSurface(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTheme.textXs,
          fontWeight: FontWeight.w500,
          color: accent
              ? activePalette.accent
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
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
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                if (!last)
                  Expanded(child: Container(width: 1, color: hfDivider(context))),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 54),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTheme.textSm,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}
