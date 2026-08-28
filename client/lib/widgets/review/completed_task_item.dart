import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../high_fidelity/high_fidelity_ui.dart';

class CompletedTaskItemWidget extends StatelessWidget {
  final Map<String, dynamic> task;

  const CompletedTaskItemWidget({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = task['output_level']?.toString() ?? '';
    final title = task['title']?.toString() ?? '';
    final listName = task['list_name']?.toString() ?? '';
    final completedAt = _timeText(task['completed_at']?.toString() ?? '');
    final levelColor = _levelColor(level);

    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hfDivider(context))),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: levelColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (level.isNotEmpty || listName.isNotEmpty || completedAt.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (level.isNotEmpty) HfChip(level),
                      if (listName.isNotEmpty)
                        Text(
                          listName,
                          style: TextStyle(
                            fontSize: AppTheme.textXs,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (completedAt.isNotEmpty)
                        Text(
                          completedAt,
                          style: TextStyle(
                            fontSize: AppTheme.textXs,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (task['is_milestone'] == true || task['is_milestone'] == 1)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                LucideIcons.trophy,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Color _levelColor(String level) => switch (level) {
        'S' => AppTheme.priorityLow,
        'A' => AppTheme.success,
        'B' => AppTheme.warning,
        'C' => AppTheme.error,
        _ => AppTheme.warmGray400,
      };

  String _timeText(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    return '${parsed.month}/${parsed.day} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }
}
