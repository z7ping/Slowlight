import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/dimension.dart';
import '../models/observation_tag.dart';
import '../models/tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../repositories/reflection_repository.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'tag_choice_field.dart';
import 'tag_picker.dart';

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
    List<Tag> canonicalTags = [];
    var saving = false;
    String? error;

    Widget buildFields(BuildContext entryContext, StateSetter setEntryState) {
      final theme = Theme.of(entryContext);

      Future<void> saveObservation() async {
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
            tagIds: canonicalTags.map((tag) => tag.id).toList(growable: false),
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
          if (!entryContext.mounted) return;
          setEntryState(() {
            saving = false;
            error = e.toString();
          });
        }
      }

      final saveButton = FxButton(
        label: saving ? '保存中…' : '保存观察',
        size: FxButtonSize.sm,
        onPressed: saving ? null : saveObservation,
      );

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
            TagChoiceField(
              label: '历史观察分类（兼容）',
              tags: tags,
              selectedTagId: selectedTagId,
              enabled: !saving,
              onChanged: (id) => setEntryState(() {
                selectedTagId = id;
                final match = tags.where((tag) => tag.id == id);
                if (match.isNotEmpty && match.first.dimensionKey != null) {
                  // 仅用于旧记录兼容，不再展示维度概念。
                  selectedDimension = match.first.dimensionKey;
                }
              }),
              onCreateTag: () async {
                if (saving) return;
                final created = await _createObservationTag(entryContext);
                if (created == null || !entryContext.mounted) return;
                setEntryState(() {
                  tags = [...tags, created];
                  selectedTagId = created.id;
                });
              },
            ),
            const SizedBox(height: 12),
            TagPicker(
              enabled: !saving,
              selectedTags: canonicalTags,
              onChanged: (tags) => setEntryState(() => canonicalTags = tags),
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
            if (_useDesktopObservationDialog)
              FxDialogActions(
                actions: [
                  FxButton(
                    label: '取消',
                    size: FxButtonSize.sm,
                    variant: FxButtonVariant.outline,
                    onPressed: saving
                        ? null
                        : () => Navigator.of(entryContext).pop(false),
                  ),
                  saveButton,
                ],
              )
            else
              SizedBox(width: double.infinity, child: saveButton),
          ],
        ),
      );
    }

    Future<bool?> showDesktopDialog() {
      return FxDialog.show<bool>(
        context: context,
        title: '记录观察',
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
                      '记录观察',
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
      title: '新建标签',
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
    List<Tag> canonicalTags = [];
    var saving = false;
    String? error;

    final saved = await FxDialog.show<bool>(
      context: context,
      title: '写下想法',
      width: 520,
      child: StatefulBuilder(
        builder: (dialogContext, setState) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (prompt != null && prompt.trim().isNotEmpty) ...[
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
                const SizedBox(height: 12),
                TagPicker(
                  enabled: !saving,
                  selectedTags: canonicalTags,
                  onChanged: (tags) => setState(() => canonicalTags = tags),
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
                                  tagIds: canonicalTags.map((tag) => tag.id).toList(growable: false),
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
