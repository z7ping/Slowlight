import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/dimension.dart';
import '../models/observation_tag.dart';
import '../models/tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../repositories/reflection_repository.dart';
import '../services/api_service.dart';
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
    final inlineTagName = TextEditingController();
    List<ObservationTag> tags = const [];
    if (_useDesktopObservationDialog) {
      try {
        tags = await ObservationTagRepository().getAll();
      } catch (_) {}
    }
    if (!context.mounted) {
      controller.dispose();
      inlineTagName.dispose();
      return false;
    }

    var selectedDimension = dimensionKey;
    int? selectedTagId;
    List<Tag> canonicalTags = [];
    var saving = false;
    var resultUnknown = false;
    var inlineTagOpen = false;
    var mobileExpandedSection = '';
    var inlineTagSaving = false;
    var inlineTagResultUnknown = false;
    var allowEditorPop = false;
    var closePending = false;
    String? inlineTagError;
    String? error;

    bool observationDirty() =>
        controller.text.trim().isNotEmpty ||
        selectedDimension != dimensionKey ||
        selectedTagId != null ||
        canonicalTags.isNotEmpty ||
        inlineTagName.text.trim().isNotEmpty;

    Future<void> requestEntryClose(
      BuildContext sheetContext,
      StateSetter setSheetState,
    ) async {
      if (saving || inlineTagSaving || closePending) return;
      if (!observationDirty() && !resultUnknown) {
        setSheetState(() => allowEditorPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (sheetContext.mounted) Navigator.of(sheetContext).pop(false);
        });
        return;
      }
      closePending = true;
      try {
        final discard = await FxDialog.confirm(
          context: sheetContext,
          title: resultUnknown ? '观察保存结果未确认' : '放弃未保存的观察？',
          content: resultUnknown
              ? '本次保存可能已经成功，请先到回顾核对，避免再次创建重复记录。'
              : '本次观察尚未保存，关闭后会丢失填写的内容。',
          confirmText: resultUnknown ? '返回核对' : '放弃修改',
          destructive: !resultUnknown,
          draftDiscard: !resultUnknown,
        );
        if (discard != true || !sheetContext.mounted) return;
        setSheetState(() => allowEditorPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (sheetContext.mounted) Navigator.of(sheetContext).pop(false);
        });
      } finally {
        closePending = false;
      }
    }

    Future<void> createInlineTag(
      BuildContext entryContext,
      StateSetter setEntryState,
    ) async {
      if (inlineTagSaving || inlineTagResultUnknown) return;
      final name = inlineTagName.text.trim().replaceFirst(RegExp(r'^#'), '').trim();
      if (name.isEmpty) {
        setEntryState(() => inlineTagError = '请输入标签名称');
        return;
      }
      setEntryState(() {
        inlineTagSaving = true;
        inlineTagError = null;
      });
      try {
        final tag = await ApiService.createTag(
          name: name,
          color: '#0075de',
        );
        if (!entryContext.mounted) return;
        setEntryState(() {
          canonicalTags = [
            ...canonicalTags.where((value) => value.id != tag.id),
            tag,
          ];
          inlineTagOpen = false;
          inlineTagSaving = false;
          inlineTagResultUnknown = false;
          inlineTagName.clear();
        });
      } catch (_) {
        if (!entryContext.mounted) return;
        setEntryState(() {
          inlineTagSaving = false;
          inlineTagResultUnknown = true;
          inlineTagError = '标签创建结果未确认，请先核对，避免重复创建';
        });
      }
    }

    // A create may have committed before its response was lost. Reconcile by
    // the existing canonical tag read instead of blindly posting again.
    Future<void> reconcileInlineTag(
      BuildContext entryContext,
      StateSetter setEntryState,
    ) async {
      if (inlineTagSaving || !inlineTagResultUnknown) return;
      final name = inlineTagName.text.trim()
          .replaceFirst(RegExp(r'^#'), '').trim();
      setEntryState(() => inlineTagSaving = true);
      try {
        final existing = await ApiService.getTags();
        if (!entryContext.mounted) return;
        final matches = existing.where((tag) => tag.name == name).toList();
        setEntryState(() {
          inlineTagSaving = false;
          if (matches.length == 1) {
            final tag = matches.single;
            canonicalTags = [
              ...canonicalTags.where((value) => value.id != tag.id),
              tag,
            ];
            inlineTagOpen = false;
            inlineTagResultUnknown = false;
            inlineTagError = null;
            inlineTagName.clear();
          } else {
            // Not finding a tag is not evidence that a timed-out POST failed.
            inlineTagError = '尚未核实创建结果，请稍后核对或到标签管理查看';
          }
        });
      } catch (_) {
        if (!entryContext.mounted) return;
        setEntryState(() {
          inlineTagSaving = false;
          inlineTagError = '核对标签失败，输入已保留，请稍后核对';
        });
      }
    }

    Widget buildFields(BuildContext entryContext, StateSetter setEntryState) {
      final theme = Theme.of(entryContext);

      Future<void> saveObservation() async {
        if (saving || resultUnknown) return;
        if (inlineTagResultUnknown) {
          setEntryState(() => error = '请先核对新标签的创建结果');
          return;
        }
        if (inlineTagOpen && inlineTagName.text.trim().isNotEmpty) {
          setEntryState(() => error = '请先添加或取消正在编辑的新标签');
          return;
        }
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
            // Both desktop and mobile routes own a draft-protecting PopScope.
            // Allow the confirmed success to pop only after the guard rebuilds.
            setEntryState(() => allowEditorPop = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (entryContext.mounted) Navigator.of(entryContext).pop(true);
            });
          }
        } catch (_) {
          if (!entryContext.mounted) return;
          // A remote create might have committed before its response or
          // cache update failed. Neither platform may replay that write.
          setEntryState(() {
            saving = false;
            resultUnknown = true;
            error = '保存结果未确认。请先到回顾核对，避免重复记录。';
          });
        }
      }

      final mobileCancelButton = FxButton(
        key: const ValueKey('observation.mobile.cancel'),
        label: '取消',
        size: FxButtonSize.sm,
        expanded: !_useDesktopObservationDialog,
        variant: FxButtonVariant.outline,
        onPressed: saving ? null : () =>
            requestEntryClose(entryContext, setEntryState),
      );
      final saveButton = FxButton(
        label: saving ? '保存中…' : '保存观察',
        size: FxButtonSize.sm,
        expanded: !_useDesktopObservationDialog,
        onPressed: saving || resultUnknown ? null : saveObservation,
      );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            if (!_useDesktopObservationDialog) ...[
              // The existing FxCard and borderless FxInput form one compact
              // workspace; optional attributes live inside the same outline.
              FxCard(
                key: const ValueKey('observation.mobile.composer'),
                padding: EdgeInsets.zero,
                borderRadius: SlowlightRadius.xl,
                border: Border.all(color: fxBorder(entryContext)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FxInput(
                      controller: controller,
                      enabled: !saving,
                      // Focus the existing editor when opening the Android
                      // observation sheet; do not change the Sheet styling.
                      autofocus: true,
                      plain: true,
                      showPlainFocusUnderline: false,
                      contentPadding: const EdgeInsets.all(SlowlightSpacing.xl),
                      minLines: 3,
                      maxLines: 4,
                      placeholder: '写下此刻的观察，只描述真实发生的事…',
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SlowlightSpacing.md, 0,
                        SlowlightSpacing.md, SlowlightSpacing.md,
                      ),
                      child: Wrap(
                        spacing: SlowlightSpacing.xs,
                        runSpacing: SlowlightSpacing.xs,
                        children: [
                          FxButton(
                            key: const ValueKey('observation.mobile.dimensionTrigger'),
                            label: selectedDimension == null
                                ? '◫ 未归类'
                                : (DimensionCatalog.all
                                    .where((d) => d.keyValue == selectedDimension)
                                    .map((d) => '${d.icon} ${d.name}')
                                    .firstOrNull ?? '◫ 未归类'),
                            variant: FxButtonVariant.secondary,
                            size: FxButtonSize.sm,
                            onPressed: saving ? null : () {
                              FocusScope.of(entryContext).unfocus();
                              setEntryState(() => mobileExpandedSection =
                                  mobileExpandedSection == 'dimensions'
                                      ? '' : 'dimensions');
                            },
                          ),
                          FxButton(
                            key: const ValueKey('observation.mobile.tagsTrigger'),
                            label: canonicalTags.isEmpty
                                ? '# 添加标签'
                                : canonicalTags.length == 1
                                    ? '#${canonicalTags.single.name}'
                                    : '# ${canonicalTags.length} 个标签',
                            variant: FxButtonVariant.secondary,
                            size: FxButtonSize.sm,
                            onPressed: saving ? null : () {
                              FocusScope.of(entryContext).unfocus();
                              setEntryState(() => mobileExpandedSection =
                                  mobileExpandedSection == 'tags' ? '' : 'tags');
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (mobileExpandedSection == 'dimensions') ...[
                const SizedBox(height: SlowlightSpacing.md),
                Text(
                  '归属维度（可选）',
                  style: SlowlightTypography.componentFieldLabel(entryContext)
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: SlowlightSpacing.md),
                Wrap(
                  key: const ValueKey('observation.mobile.dimensions'),
                  spacing: SlowlightSpacing.md,
                  runSpacing: SlowlightSpacing.md,
                  children: [
                    FxChoiceChip(
                      label: '未归类',
                      selected: selectedDimension == null,
                      onTap: saving ? null : () => setEntryState(() {
                        selectedDimension = null;
                        mobileExpandedSection = '';
                      }),
                    ),
                    for (final dimension in DimensionCatalog.all)
                      FxChoiceChip(
                        label: '${dimension.icon} ${dimension.name}',
                        selected: selectedDimension == dimension.keyValue,
                        onTap: saving ? null : () => setEntryState(() {
                          selectedDimension = dimension.keyValue;
                          mobileExpandedSection = '';
                        }),
                      ),
                  ],
                ),
              ],
              if (mobileExpandedSection == 'tags') ...[
                const SizedBox(height: SlowlightSpacing.md),
            TagPicker(
              label: '标签（可选）',
              enabled: !saving,
              selectedTags: canonicalTags,
              allowCreation: _useDesktopObservationDialog,
              showEmptyOption: _useDesktopObservationDialog,
              onChanged: (value) => setEntryState(() => canonicalTags = value),
            ),
            if (!_useDesktopObservationDialog) ...[
              const SizedBox(height: SlowlightSpacing.xs),
              if (inlineTagOpen)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: SlowlightSpacing.md,
                      runSpacing: SlowlightSpacing.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
                          child: FxInput(
                            key: const ValueKey('observation.mobile.tagName'),
                            controller: inlineTagName,
                            autofocus: true,
                            enabled: !saving && !inlineTagSaving &&
                                !inlineTagResultUnknown,
                            maxLength: 20,
                            placeholder: '输入标签名称',
                          ),
                        ),
                        FxButton(
                          label: inlineTagSaving
                              ? (inlineTagResultUnknown ? '核对中…' : '添加中…')
                              : (inlineTagResultUnknown ? '核对标签' : '添加'),
                          size: FxButtonSize.sm,
                          variant: FxButtonVariant.outline,
                          onPressed: saving || inlineTagSaving
                              ? null
                              : () => inlineTagResultUnknown
                                  ? reconcileInlineTag(entryContext, setEntryState)
                                  : createInlineTag(entryContext, setEntryState),
                        ),
                        FxButton(
                          label: '取消',
                          size: FxButtonSize.sm,
                          variant: FxButtonVariant.ghost,
                          onPressed: inlineTagSaving || inlineTagResultUnknown
                              ? null
                              : () => setEntryState(() {
                                    inlineTagOpen = false;
                                    inlineTagError = null;
                                    inlineTagName.clear();
                                  }),
                        ),
                      ],
                    ),
                    if (inlineTagError != null)
                      Text(
                        inlineTagError!,
                        style: SlowlightTypography.caption(entryContext)
                            .copyWith(color: theme.colorScheme.error),
                      ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: FxButton(
                    label: '＋ 新建标签',
                    variant: FxButtonVariant.ghost,
                    size: FxButtonSize.sm,
                    onPressed: saving
                        ? null
                        : () => setEntryState(() => inlineTagOpen = true),
                  ),
                ),
            ],
              ],
            ] else ...[
            FxInput(
              controller: controller,
              autofocus: true,
              enabled: !saving,
              minLines: 2,
              maxLines: 4,
              placeholder: '写下此刻的观察，只描述真实发生的事…',
            ),
            const SizedBox(height: 12),
            if (_useDesktopObservationDialog) ...[
              TagChoiceField(
                label: '历史观察分类（兼容）',
                tags: tags,
                selectedTagId: selectedTagId,
                enabled: !saving,
                onChanged: (id) => setEntryState(() {
                  selectedTagId = id;
                  final match = tags.where((tag) => tag.id == id);
                  if (match.isNotEmpty && match.first.dimensionKey != null) {
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
              const SizedBox(height: SlowlightSpacing.xl),
            ],
            Text(
                '归属维度（可选）',
                style: SlowlightTypography.componentFieldLabel(entryContext)
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: SlowlightSpacing.md),
              Wrap(
                key: ValueKey(_useDesktopObservationDialog
                    ? 'observation.desktop.dimensions'
                    : 'observation.mobile.dimensions'),
                spacing: SlowlightSpacing.md,
                runSpacing: SlowlightSpacing.md,
                children: [
                  FxChoiceChip(
                    label: '未归类',
                    selected: selectedDimension == null,
                    onTap: saving ? null : () =>
                        setEntryState(() => selectedDimension = null),
                  ),
                  for (final dimension in DimensionCatalog.all)
                    FxChoiceChip(
                      label: '${dimension.icon} ${dimension.name}',
                      selected: selectedDimension == dimension.keyValue,
                      onTap: saving ? null : () => setEntryState(
                        () => selectedDimension = dimension.keyValue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: SlowlightSpacing.xl),
            TagPicker(
              label: '标签（可选）',
              enabled: !saving,
              selectedTags: canonicalTags,
              allowCreation: _useDesktopObservationDialog,
              showEmptyOption: _useDesktopObservationDialog,
              onChanged: (value) => setEntryState(() => canonicalTags = value),
            ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: SlowlightTypography.caption(
                  entryContext,
                ).copyWith(color: theme.colorScheme.error),
              ),
            ],
                ],
              ),
            ),
          ),
          const SizedBox(height: SlowlightSpacing.md),
          FxSeparator.horizontal(height: 1, color: fxDivider(entryContext)),
          const SizedBox(height: SlowlightSpacing.md),
          if (_useDesktopObservationDialog)
              FxDialogActions(
                actions: [
                  FxButton(
                    label: '取消',
                    size: FxButtonSize.sm,
                    variant: FxButtonVariant.outline,
                    onPressed: saving
                        ? null
                        : () => requestEntryClose(entryContext, setEntryState),
                  ),
                  saveButton,
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(flex: 10, child: mobileCancelButton),
                  const SizedBox(width: SlowlightSpacing.md),
                  Expanded(flex: 18, child: saveButton),
                ],
              ),
        ],
      );
    }

    Future<bool?> showDesktopDialog() {
      return FxDialog.show<bool>(
        context: context,
        title: '记录观察',
        width: 520,
        // The footer already owns Cancel; avoid an extra corner close action.
        showCloseButton: false,
        barrierDismissible: false,
        child: StatefulBuilder(
          builder: (dialogContext, setDialogState) => PopScope(
            // Desktop cancellation and Escape must share the same draft
            // protection as the Android editor, including unknown results.
            canPop: allowEditorPop,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) requestEntryClose(dialogContext, setDialogState);
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .72,
              ),
              child: buildFields(dialogContext, setDialogState),
            ),
          ),
        ),
      );
    }

    BuildContext? activeSheetContext;
    StateSetter? activeSheetSetState;

    Future<bool?> showMobileSheet() {
      return FxSheet.show<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        showCloseButton: false,
        draggable: false,
        onDismissRequested: () async {
          final owner = activeSheetContext;
          final update = activeSheetSetState;
          if (owner != null && update != null && owner.mounted) {
            await requestEntryClose(owner, update);
          }
        },
        isDismissible: false,
        padding: EdgeInsets.zero,
        backgroundColor: fxSurface(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SlowlightRadius.xl),
          ),
        ),
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            activeSheetContext = sheetContext;
            activeSheetSetState = setSheetState;
            return PopScope(
              canPop: allowEditorPop,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) requestEntryClose(sheetContext, setSheetState);
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * .88,
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    // The shared grip already occupies the 44dp top zone.
                    // Align the title directly below it, as in #mObs.
                    padding: const EdgeInsets.fromLTRB(
                      SlowlightSpacing.xxxl,
                      0,
                      SlowlightSpacing.xxxl,
                      SlowlightSpacing.xxxl,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '记录观察',
                          key: const ValueKey('observation.mobile.title'),
                          style: SlowlightTypography.cardTitle(sheetContext)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: SlowlightSpacing.xl),
                        Flexible(
                          child: buildFields(sheetContext, setSheetState),
                        ),
                      ],
                    ),
                  ),
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
    inlineTagName.dispose();
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
    var resultUnknown = false;
    var allowPop = false;
    var closing = false;
    String? error;

    Future<void> requestClose(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (saving || closing || allowPop) return;
      final dirty =
          controller.text.trim().isNotEmpty || canonicalTags.isNotEmpty;
      if (dirty || resultUnknown) {
        closing = true;
        try {
          final discard = await FxDialog.confirm(
            context: dialogContext,
            title: resultUnknown ? '想法保存结果未确认' : '放弃未保存的想法？',
            content: resultUnknown
                ? '这次保存可能已经成功，请先到回顾核对，避免再次创建重复记录。'
                : '关闭后会丢失本次尚未保存的内容。',
            confirmText: resultUnknown ? '返回核对' : '放弃修改',
            destructive: !resultUnknown,
          draftDiscard: !resultUnknown,
          );
          if (discard != true || !dialogContext.mounted) return;
        } finally {
          closing = false;
        }
      }
      if (!dialogContext.mounted) return;
      setDialogState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialogContext.mounted) {
          Navigator.of(dialogContext, rootNavigator: true).pop(false);
        }
      });
    }

    final saved = await FxDialog.show<bool>(
      context: context,
      title: '写下想法',
      width: 520,
      barrierDismissible: false,
      showCloseButton: false,
      child: StatefulBuilder(
        builder: (dialogContext, setState) {
          return PopScope(
            canPop: allowPop,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) requestClose(dialogContext, setState);
            },
            child: SingleChildScrollView(
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
                            : () => requestClose(dialogContext, setState),
                      ),
                      FxButton(
                        label: saving ? '保存中…' : '保存',
                        onPressed: saving || resultUnknown
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
                                    setState(() => allowPop = true);
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (dialogContext.mounted) {
                                        Navigator.of(dialogContext, rootNavigator: true)
                                            .pop(true);
                                      }
                                    });
                                  }
                                } catch (_) {
                                  if (!dialogContext.mounted) return;
                                  // A Cloud write may succeed before its response
                                  // or local cache update fails. Never replay it.
                                  setState(() {
                                    saving = false;
                                    resultUnknown = true;
                                    error = '保存结果未确认，请先到回顾核对，避免重复记录。';
                                  });
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    controller.dispose();
    return saved == true;
  }
}
