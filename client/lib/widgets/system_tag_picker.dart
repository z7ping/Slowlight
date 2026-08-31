import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../ui/fx.dart';

/// 系统标签选择器弹窗。
/// 用于番茄钟结束时选择系统标签。
class SystemTagPicker extends StatefulWidget {
  final int? defaultTagId;
  final String title;

  const SystemTagPicker({super.key, this.defaultTagId, this.title = '选择系统标签'});

  /// 显示系统标签选择弹窗，返回选中的 tag ID 或 null。
  static Future<int?> show(
    BuildContext context, {
    int? defaultTagId,
    String title = '选择系统标签',
  }) async {
    return FxSheet.show<int?>(
      context: context,
      isScrollControlled: false,
      showDragHandle: false,
      builder: (_) => SystemTagPicker(defaultTagId: defaultTagId, title: title),
    );
  }

  @override
  State<SystemTagPicker> createState() => _SystemTagPickerState();
}

class _SystemTagPickerState extends State<SystemTagPicker> {
  List<Map<String, dynamic>> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final tags = await ApiService.getSystemTags();
      if (mounted) {
        setState(() {
          _tags = tags;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        FxNotice.showContent(
          context,
          const Text('加载系统标签失败'),
          variant: FxNoticeVariant.destructive,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: SlowlightTypography.cardTitle(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '这次专注属于哪个维度？',
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: FxCircularProgress())
            else if (_tags.isEmpty)
              Text('暂无系统标签', style: SlowlightTypography.body(context))
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    _tags.map((tag) {
                      final id = tag['id'] as int;
                      final name = tag['name'] as String? ?? '';
                      final icon = tag['icon'] as String? ?? '🏷️';
                      final isSelected = id == widget.defaultTagId;

                      return FxInkWell(
                        onTap: () => Navigator.pop(context, id),
                        borderRadius: BorderRadius.circular(SlowlightRadius.md),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(
                              SlowlightRadius.md,
                            ),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                icon,
                                style: const TextStyle(
                                  fontSize: SlowlightTypography.sectionTitleSize,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                name,
                                style: SlowlightTypography.control(
                                  context,
                                ).copyWith(
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(growable: false),
              ),
            const SizedBox(height: 16),
            FxButton(
              label: '跳过，不标记',
              variant: FxButtonVariant.ghost,
              expanded: true,
              onPressed: () => Navigator.pop(context, null),
            ),
          ],
        ),
      ),
    );
  }
}
