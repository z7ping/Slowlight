import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/dimension.dart';
import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../repositories/reflection_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'task_dimension_field.dart';

/// Observation / Reflection 的统一轻量输入入口。
class ReflectionComposer {
  const ReflectionComposer._();

  static Future<bool> show(
    BuildContext context, {
    String entryType = 'reflection',
    String? questionId,
    String? prompt,
    String? dimensionKey,
    Map<String, dynamic> contextData = const {},
  }) async {
    if (entryType == 'observation') {
      return _showObservationEntry(
        context,
        questionId: questionId,
        dimensionKey: dimensionKey,
        contextData: contextData,
      );
    }
    return _showReflectionDialog(
      context,
      questionId: questionId,
      prompt: prompt,
      dimensionKey: dimensionKey,
      contextData: contextData,
    );
  }

  static bool get _useDesktopObservationDialog =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<bool> _showObservationEntry(
    BuildContext context, {
    String? questionId,
    String? dimensionKey,
    Map<String, dynamic> contextData = const {},
  }) async {
    final controller = TextEditingController();
    List<ObservationTag> tags = const [];
    try {
      tags = await ObservationTagRepository().getAll();
    } catch (_) {}
    if (!context.mounted) {
      controller.dispose();
      return false;
    }

    var selectedDimension = dimensionKey;
    int? selectedTagId;
    var saving = false;
    String? error;

    Widget buildFields(BuildContext entryContext, StateSetter setEntryState) {
      final theme = Theme.of(entryContext);

      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FxInput(
              controller: controller,
              autofocus: true,
              enabled: !saving,
              minLines: 2,
              maxLines: 4,
              placeholder: '写下此刻的观察，只描述真实发生的事…',
            ),
            const SizedBox(height: 12),
            TaskDimensionField(
              selectedKey: selectedDimension,
              enabled: !saving,
              onChanged: (key) => setEntryState(() {
                selectedDimension = key;
                if (selectedTagId != null) {
                  final linked = tags.where((tag) => tag.id == selectedTagId);
                  if (linked.isNotEmpty &&
                      linked.first.dimensionKey != null &&
                      linked.first.dimensionKey!.isNotEmpty) {
                    selectedDimension = linked.first.dimensionKey;
                  }
                }
              }),
            ),
            const SizedBox(height: SlowlightSpacing.xxxl),
            FxFormField(
              label: '标签（可选）',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...tags.take(8).map((tag) {
                    final selected = selectedTagId == tag.id;
                    return FxChoiceChip(
                      label: '#${tag.name}',
                      selected: selected,
                      onTap: saving
                          ? null
                          : () => setEntryState(() {
                                selectedTagId = selected ? null : tag.id;
                                if (!selected &&
                                    tag.dimensionKey != null &&
                                    tag.dimensionKey!.isNotEmpty) {
                                  selectedDimension = tag.dimensionKey;
                                }
                              }),
                    );
                  }),
                  FxChoiceChip(
                    label: '＋ 新建标签',
                    selected: false,
                    onTap: saving
                        ? null
                        : () async {
                            final created = await _createObservationTag(
                              entryContext,
                              dimensionKey: selectedDimension,
                            );
                            if (created == null || !entryContext.mounted) return;
                            setEntryState(() {
                              tags = [...tags, created];
                              selectedTagId = created.id;
                              if (created.dimensionKey != null &&
                                  created.dimensionKey!.isNotEmpty) {
                                selectedDimension = created.dimensionKey;
                              }
                            });
                          },
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: SlowlightTypography.caption(
                  entryContext,
                ).copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: SlowlightSpacing.xxxl),
            FxDialogActions(
              actions: [
                FxButton(
                  label: '取消',
                  size: FxButtonSize.sm,
                  variant: FxButtonVariant.outline,
                  onPressed: saving ? null : () => Navigator.of(entryContext).pop(false),
                ),
                FxButton(
                  label: saving ? '保存中…' : '保存观察',
                  size: FxButtonSize.sm,
                  onPressed: saving
                      ? null
                      : () async {
                          final value = controller.text.trim();
                          if (value.isEmpty) {
                            setEntryState(() => error = '先写一点观察');
                            return;
                          }
                          setEntryState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            ObservationTag? selectedTag;
                            for (final tag in tags) {
                              if (tag.id == selectedTagId) {
                                selectedTag = tag;
                                break;
                              }
                            }
                            await ReflectionRepository().create(
                              content: value,
                              entryType: 'observation',
                              questionId: questionId,
                              dimensionKey: selectedDimension,
                              context: {
                                ...contextData,
                                if (selectedTag != null)
                                  'observation_tag_id': selectedTag.id,
                                if (selectedTag != null)
                                  'observation_tag_name': selectedTag.name,
                              },
                            );
                            if (entryContext.mounted) {
                              Navigator.of(entryContext).pop(true);
                            }
                          } catch (e) {
                            setEntryState(() {
                              saving = false;
                              error = e.toString();
                            });
                          }
                        },
                ),
              ],
            ),
          ],
        ),
      );
    }

    Future<bool?> showDesktopDialog() {
      return FxDialog.show<bool>(
        context: context,
        title: '写下观察',
        width: 520,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .72,
            ),
            child: buildFields(dialogContext, setDialogState),
          ),
        ),
      );
    }

    Future<bool?> showMobileSheet() {
      return FxSheet.show<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '写下观察',
                      style: SlowlightTypography.cardTitle(
                        sheetContext,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Flexible(child: buildFields(sheetContext, setSheetState)),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    final saved = _useDesktopObservationDialog
        ? await showDesktopDialog()
        : await showMobileSheet();

    controller.dispose();
    return saved == true;
  }

  static Future<ObservationTag?> _createObservationTag(
    BuildContext context, {
    String? dimensionKey,
  }) async {
    final controller = TextEditingController();
    var saving = false;
    String? error;

    final created = await FxDialog.show<ObservationTag>(
      context: context,
      title: '新建观察标签',
      width: 420,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FxInput(
                controller: controller,
                autofocus: true,
                enabled: !saving,
                textInputAction: TextInputAction.done,
                onSubmitted: saving
                    ? null
                    : (_) => _saveQuickTag(
                          dialogContext,
                          controller: controller,
                          dimensionKey: dimensionKey,
                          setDialogState: setDialogState,
                          setSaving: (value) => saving = value,
                          setError: (value) => error = value,
                        ),
                placeholder: '例如：分心、心流、精力低谷',
              ),
              if (dimensionKey != null && dimensionKey.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '默认归属当前选择的维度',
                  style: SlowlightTypography.caption(dialogContext)
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: SlowlightTypography.caption(dialogContext)
                      .copyWith(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FxButton(
                    label: '取消',
                    variant: FxButtonVariant.outline,
                    size: FxButtonSize.sm,
                    onPressed: saving
                        ? null
                        : () => Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).pop(),
                  ),
                  FxButton(
                    label: saving ? '创建中…' : '创建',
                    size: FxButtonSize.sm,
                    onPressed: saving
                        ? null
                        : () => _saveQuickTag(
                              dialogContext,
                              controller: controller,
                              dimensionKey: dimensionKey,
                              setDialogState: setDialogState,
                              setSaving: (value) => saving = value,
                              setError: (value) => error = value,
                            ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();
    return created;
  }

  static Future<void> _saveQuickTag(
    BuildContext dialogContext, {
    required TextEditingController controller,
    required String? dimensionKey,
    required StateSetter setDialogState,
    required ValueChanged<bool> setSaving,
    required ValueChanged<String?> setError,
  }) async {
    final name = controller.text.trim();
    if (name.isEmpty) {
      setDialogState(() => setError('请输入标签名称'));
      return;
    }
    setDialogState(() {
      setSaving(true);
      setError(null);
    });
    try {
      final tag = await ObservationTagRepository().create(
        name: name,
        icon: '🏷️',
        color: '#1890FF',
        dimensionKey: dimensionKey,
      );
      if (dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true).pop(tag);
      }
    } catch (e) {
      setDialogState(() {
        setSaving(false);
        setError('创建失败：$e');
      });
    }
  }

  static Future<bool> _showReflectionDialog(
    BuildContext context, {
    String? questionId,
    String? prompt,
    String? dimensionKey,
    Map<String, dynamic> contextData = const {},
  }) async {
    final controller = TextEditingController();
    var saving = false;
    String? error;

    final saved = await FxDialog.show<bool>(
      context: context,
      title: '写下想法',
      width: 520,
      child: StatefulBuilder(
        builder: (dialogContext, setState) {
          final dimension = DimensionCatalog.byKey(dimensionKey);
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dimension != null) ...[
                  Text(
                    '${dimension.icon} ${dimension.name}',
                    style: SlowlightTypography.secondary(dialogContext)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
                if (prompt != null && prompt.trim().isNotEmpty) ...[
                  if (dimension != null) const SizedBox(height: 10),
                  Text(
                    prompt,
                    style: SlowlightTypography.secondary(dialogContext)
                        .copyWith(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FxInput(
                  controller: controller,
                  autofocus: true,
                  enabled: !saving,
                  minLines: 4,
                  maxLines: 8,
                  placeholder: '只记录你的真实想法，不需要写成结论。',
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: SlowlightTypography.caption(dialogContext).copyWith(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FxButton(
                      label: '取消',
                      variant: FxButtonVariant.outline,
                      onPressed: saving
                          ? null
                          : () => Navigator.of(
                                dialogContext,
                                rootNavigator: true,
                              ).pop(false),
                    ),
                    FxButton(
                      label: saving ? '保存中…' : '保存',
                      onPressed: saving
                          ? null
                          : () async {
                              final value = controller.text.trim();
                              if (value.isEmpty) {
                                setState(() => error = '先写一点内容');
                                return;
                              }
                              setState(() {
                                saving = true;
                                error = null;
                              });
                              try {
                                await ReflectionRepository().create(
                                  content: value,
                                  questionId: questionId,
                                  dimensionKey: dimensionKey,
                                  context: contextData,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.of(
                                    dialogContext,
                                    rootNavigator: true,
                                  ).pop(true);
                                }
                              } catch (e) {
                                setState(() {
                                  saving = false;
                                  error = e.toString();
                                });
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    controller.dispose();
    return saved == true;
  }
}
