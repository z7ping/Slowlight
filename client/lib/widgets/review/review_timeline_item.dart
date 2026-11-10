import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ui/typography_tokens.dart';
import '../../ui/fx.dart';
import '../timeline_type_label.dart';

/// 回顾页专属时间线项。
///
/// 时间线表达“今天真实发生了什么”，属于 Review Feature Widget，
/// 不进入全局 Fx 基础组件层。
class ReviewTimelineItem extends StatefulWidget {
  final Color color;
  final String time;
  final String title;
  final String? note;
  final bool last;
  final String kind;
  final bool compact;

  const ReviewTimelineItem({
    super.key,
    required this.color,
    required this.time,
    required this.title,
    this.note,
    this.last = false,
    this.kind = 'record',
    this.compact = false,
  });

  @override
  State<ReviewTimelineItem> createState() => _ReviewTimelineItemState();
}

class _ReviewTimelineItemState extends State<ReviewTimelineItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _compactItem(context);
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
                if (!widget.last)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.time,
                    style: SlowlightTypography.caption(context).copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.title,
                    style: SlowlightTypography.body(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.note != null && widget.note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.note!,
                      style: SlowlightTypography.caption(context).copyWith(
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

  Widget _compactItem(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final identityColor = Color.lerp(widget.color, theme.colorScheme.onSurface, .35)!;
    final observation = widget.kind == 'observation';
    final displayTitle = observation && (widget.note?.isNotEmpty ?? false)
        ? widget.note!
        : widget.title;
    final detail = observation ? null : widget.note;
    // A panel containing only the timestamp/type is not useful.
    final canExpand = detail != null &&
        detail.trim().isNotEmpty && detail.trim() != displayTitle.trim();
    final separator = widget.time.lastIndexOf(' ');
    final shortTime = separator < 0
        ? widget.time
        : widget.time.substring(separator + 1);
    final datePart = separator < 0 ? null : widget.time.substring(0, separator);
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              shortTime,
              style: SlowlightTypography.caption(context).copyWith(
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: identityColor, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: FxInkWell(
            onTap: canExpand
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(SlowlightRadius.md),
            child: Semantics(
              button: canExpand,
              expanded: canExpand ? _expanded : null,
              label: canExpand
                  ? '${displayTitle}，${TimelineTypeLabel.labelFor(widget.kind)}，${_expanded ? '收起' : '展开'}详情'
                  : '${displayTitle}，${TimelineTypeLabel.labelFor(widget.kind)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      maxLines: canExpand && !_expanded ? 2 : null,
                      overflow: canExpand && !_expanded
                          ? TextOverflow.ellipsis : TextOverflow.visible,
                      style: SlowlightTypography.body(context).copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        TimelineTypeLabel(
                          kind: widget.kind,
                          baseColor: widget.color,
                        ),
                        if (datePart != null) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(' · $datePart',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SlowlightTypography.caption(context)
                                    .copyWith(color: muted)),
                          ),
                        ],
                        if (canExpand) ...[
                          const Spacer(),
                          Icon(
                            _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                            size: SlowlightIconSize.sm, color: muted,
                          ),
                        ],
                      ],
                    ),
                    if (canExpand)
                      AnimatedSize(
                        duration: reducedMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: !_expanded
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(
                                    SlowlightSpacing.md,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerLowest,
                                    borderRadius:
                                        BorderRadius.circular(SlowlightRadius.md),
                                  ),
                                  child: Text(
                                    detail!,
                                    style: SlowlightTypography.caption(context)
                                        .copyWith(color: muted),
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

}

 
/// 时间已知的事实按发生时刻排列；只有“今天”的汇总放在最后。
int compareReviewTimelineItems(ReviewTimelineItem a, ReviewTimelineItem b) {
  int? minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null ||
        hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  final first = minutes(a.time);
  final second = minutes(b.time);
  if (first == null) return second == null ? 0 : 1;
  if (second == null) return -1;
  return first.compareTo(second);
}
