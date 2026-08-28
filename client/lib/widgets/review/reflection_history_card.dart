import 'package:flutter/material.dart';

import '../../models/dimension.dart';
import '../../models/reflection_entry.dart';
import '../../repositories/reflection_repository.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../reflection_composer.dart';

class ReflectionHistoryCard extends StatefulWidget {
  const ReflectionHistoryCard({super.key});

  @override
  State<ReflectionHistoryCard> createState() => _ReflectionHistoryCardState();
}

class _ReflectionHistoryCardState extends State<ReflectionHistoryCard> {
  bool _loading = true;
  List<ReflectionEntry> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ReflectionRepository().recent(limit: 5);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FxCard(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_outlined,
                  size: 19, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '我的观察',
                  style: TextStyle(
                    fontSize: AppTheme.textMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FxButton(
                label: '记录',
                size: FxButtonSize.sm,
                variant: FxButtonVariant.secondary,
                onPressed: () async {
                  final saved = await ReflectionComposer.show(
                    context,
                    entryType: 'observation',
                  );
                  if (saved) await _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_items.isEmpty)
            Text(
              '还没有自己的记录。这里保存的是你的解释，不是系统给你的结论。',
              style: TextStyle(
                fontSize: AppTheme.textSm,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            )
          else
            ..._items.map(_buildItem),
        ],
      ),
    );
  }

  Widget _buildItem(ReflectionEntry item) {
    final dimension = DimensionCatalog.byKey(item.dimensionKey);
    final local = item.createdAt.toLocal();
    final time =
        '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.content,
            style: const TextStyle(fontSize: AppTheme.textSm, height: 1.5),
          ),
          const SizedBox(height: 3),
          Text(
            '${dimension == null ? '' : '${dimension.icon} ${dimension.name} · '}$time',
            style: TextStyle(
              fontSize: AppTheme.textXs,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
