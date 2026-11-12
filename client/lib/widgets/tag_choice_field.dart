import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/observation_tag.dart';
import '../utils/color_utils.dart';
import '../ui/fx.dart';

/// 统一标签选择视觉层：兼容旧单选，并为多标签调用方提供多选交互。
/// 多选仅返回选中 ID 集合，持久化由业务调用方负责。
class TagChoiceField extends StatelessWidget {
  final List<ObservationTag> tags;
  final int? selectedTagId;
  final ValueChanged<int?>? onChanged;
  final Set<int>? selectedTagIds;
  final ValueChanged<Set<int>>? onMultipleChanged;
  final bool enabled;
  final VoidCallback? onCreateTag;
  final String label;
  final bool showEmptyOption;
  /// Use the same Fx list option style in a two-column anchored picker.
  final bool compactGrid;

  const TagChoiceField({
    super.key,
    required this.tags,
    this.selectedTagId,
    this.onChanged,
    this.selectedTagIds,
    this.onMultipleChanged,
    this.enabled = true,
    this.onCreateTag,
    this.label = '标签（可选）',
    this.showEmptyOption = true,
    this.compactGrid = false,
  });

  @override
  Widget build(BuildContext context) {
    final multiple = onMultipleChanged != null;
    final selectedIds = selectedTagIds ?? <int>{};
    return FxFormField(
      label: label,
      child: compactGrid ? LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 240 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.4
              ? 2
              : 1;
          final cellWidth = (constraints.maxWidth -
              (columns - 1) * SlowlightSpacing.xs) / columns;
          final colors = Theme.of(context).colorScheme;
          Widget option(
            String text, {
            required bool selected,
            required Color color,
            required VoidCallback? onTap,
            bool create = false,
          }) => SizedBox(
            width: cellWidth,
            child: FxListTile(
              density: FxListTileDensity.compact,
              minTileHeight: SlowlightControlSize.minTouchTarget,
              padding: const EdgeInsets.symmetric(
                horizontal: SlowlightSpacing.md,
                vertical: SlowlightSpacing.xs,
              ),
              title: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.componentSecondary(context),
              ),
              leading: create
                  ? const Icon(LucideIcons.plus, size: SlowlightIconSize.sm)
                  : null,
              trailing: selected
                  ? Icon(LucideIcons.check,
                      size: SlowlightIconSize.sm, color: color)
                  : null,
              selected: selected,
              selectedTileColor: color.withValues(alpha: .10),
              enabled: enabled,
              onTap: enabled ? onTap : null,
            ),
          );
          return Wrap(
            spacing: SlowlightSpacing.xs,
            runSpacing: SlowlightSpacing.xs,
            children: [
              if (showEmptyOption)
                option(
                  '无标签',
                  selected: multiple ? selectedIds.isEmpty : selectedTagId == null,
                  color: colors.onSurfaceVariant,
                  onTap: () => multiple
                      ? onMultipleChanged!(<int>{})
                      : onChanged?.call(null),
                ),
              for (final tag in tags)
                option(
                  '#${tag.name}',
                  selected: multiple
                      ? selectedIds.contains(tag.id)
                      : selectedTagId == tag.id,
                  color: ColorUtils.safeParse(tag.color),
                  onTap: () {
                    if (!multiple) {
                      onChanged?.call(tag.id);
                      return;
                    }
                    final updated = {...selectedIds};
                    if (!updated.add(tag.id)) updated.remove(tag.id);
                    onMultipleChanged!(updated);
                  },
                ),
              if (onCreateTag != null)
                option(
                  '新建',
                  selected: false,
                  color: colors.onSurfaceVariant,
                  onTap: onCreateTag,
                  create: true,
                ),
            ],
          );
        },
      ) : Wrap(
        spacing: SlowlightSpacing.md,
        runSpacing: SlowlightSpacing.md,
        children: [
          if (showEmptyOption) FxChoiceChip(
            label: '无标签',
            selected: multiple ? selectedIds.isEmpty : selectedTagId == null,
            // “无标签”是默认状态，不使用强调色冒充用户主动选择的标签。
            selectionColor: Theme.of(context).colorScheme.onSurfaceVariant,
            onTap: enabled
                ? () => multiple ? onMultipleChanged!(<int>{}) : onChanged?.call(null)
                : null,
          ),
          ...tags.map((tag) => FxChoiceChip(
                label: '#${tag.name}',
                selected: multiple ? selectedIds.contains(tag.id) : selectedTagId == tag.id,
                selectionColor: ColorUtils.safeParse(tag.color),
                onTap: enabled
                    ? () {
                        if (!multiple) {
                          onChanged?.call(tag.id);
                          return;
                        }
                        final updated = {...selectedIds};
                        if (!updated.add(tag.id)) updated.remove(tag.id);
                        onMultipleChanged!(updated);
                      }
                    : null,
              )),
          if (onCreateTag != null)
            FxChoiceChip(
              label: '新建',
              icon: LucideIcons.plus,
              selected: false,
              onTap: enabled ? onCreateTag : null,
            ),
        ],
      ),
    );
  }
}
