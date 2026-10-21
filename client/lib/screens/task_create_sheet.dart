import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';

import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';
import '../widgets/tag_choice_field.dart';
import '../widgets/task_schedule_fields.dart';
import 'add_task_screen.dart';

/// 任务快速记录入口。
class TaskCreateSheet extends StatefulWidget {
  final bool quickMode;
  final bool desktopDialog;
  final int? systemTagId;
  final String? systemTagName;
  final String initialPriority;
  final bool defaultDueToday;
  final VoidCallback? onCreated;

  const TaskCreateSheet({
    super.key,
    this.quickMode = false,
    this.desktopDialog = false,
    this.systemTagId,
    this.systemTagName,
    this.initialPriority = 'none',
    this.defaultDueToday = true,
    this.onCreated,
  });

  static bool _useDesktopDialog(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<void> showQuickCreate(
    BuildContext context, {
    int? systemTagId,
    String? systemTagName,
    String initialPriority = 'none',
    bool defaultDueToday = true,
    VoidCallback? onCreated,
  }) async {
    final editor = TaskCreateSheet(
      quickMode: true,
      desktopDialog: _useDesktopDialog(context),
      systemTagId: systemTagId,
      systemTagName: systemTagName,
      initialPriority: initialPriority,
      defaultDueToday: defaultDueToday,
      onCreated: onCreated,
    );

    if (_useDesktopDialog(context)) {
      await FxDialog.show<void>(
        context: context,
        title: '添加任务',
        width: 520,
        child: editor,
      );
      return;
    }

    await FxSheet.show<void>(
      context: context,
      // 快捷表单按内容高度展示；保留下滑关闭手势，
      // 键盘出现时仍由 FxSheet 统一避让，不自动扩展成全屏。
      isScrollControlled: true,
      draggable: true,
      showDragHandle: false,
      // ShadSheet 的默认内边距与表单自身边距叠加会使移动端内容过窄。
      // 快捷表单由自身统一控制间距，其他 Sheet 不受影响。
      padding: EdgeInsets.zero,
      builder: (_) => editor,
    );
  }

  /// 完整任务表单：桌面紧凑居中弹窗，移动端整页。
  static Future<bool?> showFullCreate(
    BuildContext context, {
    List<TodoList>? lists,
    int? selectedListId,
    DateTime? defaultDueDate,
    String initialTitle = '',
    String initialPriority = 'none',
    int? systemTagId,
    bool defaultToToday = true,
    String? initialDimensionKey,
    bool dimensionChanged = false,
  }) async {
    final resolvedLists = lists ?? await DataService().getLists();
    if (!context.mounted) return false;
    if (resolvedLists.isEmpty) {
      FxNotice.showContent(context, Text('请先创建一个清单'));
      return false;
    }

    // Android 大屏/平板仍按移动端交互展示完整页，不能按宽度伪装桌面。
    final desktop = _useDesktopDialog(context);
    final editor = AddTaskScreen(
      lists: resolvedLists,
      selectedListId: selectedListId ?? resolvedLists.first.id,
      defaultDueDate:
          defaultDueDate ?? (defaultToToday ? DateTime.now() : null),
      initialTitle: initialTitle,
      initialPriority: initialPriority,
      systemTagId: systemTagId,
      initialDimensionKey: initialDimensionKey,
      dimensionChanged: dimensionChanged,
      embedded: desktop,
    );

    if (!desktop) {
      return Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => editor),
      );
    }

    return FxDialog.raw<bool>(
      context: context,
      barrierColor: FxDialog.barrierColor,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return FxDialogSurface(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: fxSurface(dialogContext),
          surfaceTintColor: Colors.transparent,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlowlightRadius.xl),
            side: BorderSide(color: fxBorder(dialogContext)),
          ),
          child: SizedBox(
            width: (size.width - 48).clamp(0.0, 680.0),
            height: (size.height - 48).clamp(0.0, 520.0),
            child: editor,
          ),
        );
      },
    );
  }

  @override
  State<TaskCreateSheet> createState() => _TaskCreateSheetState();
}

class _TaskCreateSheetState extends State<TaskCreateSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsRepository = ObservationTagRepository();
  List<ObservationTag> _availableTags = const [];
  late int? _selectedTagId;
  bool _showLists = true;
  bool _showTags = true;
  List<TodoList> _lists = const [];
  int? _selectedListId;
  late DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _repeatType = 'none';
  final Set<int> _selectedWeekdays = {};
  int _reminderAdvanceMinutes = -1;
  late String _selectedPriority;
  bool _loadingLists = true;
  bool _listLoadFailed = false;
  bool _saving = false;
  String? _error;
  _MobileTaskPage? _mobilePage;
  String _mobileQuery = '';
  bool _mobileAutofocus = true;
  late DateTime _calendarFocusedDay;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.defaultDueToday ? _today() : null;
    _selectedPriority = _normalizePriority(widget.initialPriority);
    _selectedTagId = widget.systemTagId;
    _calendarFocusedDay = _dueDate ?? DateTime.now();
    _loadLists();
    _loadTags();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final lists = await DataService().getLists();
      if (!mounted) return;
      final inbox = _inboxOf(lists);
      setState(() {
        _lists = lists;
        _selectedListId = inbox?.id ?? (lists.isEmpty ? null : lists.first.id);
        _loadingLists = false;
        _listLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLists = false;
        _listLoadFailed = true;
      });
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _tagsRepository.getAll();
      if (mounted) setState(() => _availableTags = tags);
    } catch (_) {
      // 标签读取失败不影响无标签记录，也不清空预设关联。
    }
  }

  Widget _listLoadNotice() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '清单暂时无法加载，请重试后再添加任务。',
          style: SlowlightTypography.secondary(context).copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        FxButton(
          label: '重新加载清单',
          variant: FxButtonVariant.outline,
          size: FxButtonSize.sm,
          onPressed: _loadingLists ? null : () {
            setState(() => _loadingLists = true);
            _loadLists();
          },
        ),
      ],
    ),
  );

  TodoList? _inboxOf(List<TodoList> lists) {
    for (final list in lists) {
      if (list.isInbox) return list;
    }
    return null;
  }

  Widget _titleInput(
    BuildContext context, {
    bool multiline = false,
    EdgeInsets? contentPadding,
  }) => FxInput(
    controller: _titleController,
    // 快捷记录默认聚焦标题，移动端同时弹出键盘。
    autofocus: widget.desktopDialog || _mobileAutofocus,
    onPressedOutside: (_) => FocusScope.of(context).unfocus(),
    enabled: !_saving,
    keyboardType: multiline ? TextInputType.multiline : null,
    textInputAction:
        multiline ? TextInputAction.newline : TextInputAction.done,
    onSubmitted: multiline ? null : (_) => _createTask(),
    minLines: multiline ? 2 : null,
    maxLines: multiline ? 6 : 1,
    contentPadding: contentPadding,
    style: SlowlightTypography.body(context),
    placeholder: widget.desktopDialog
        ? '例如：整理今天的会议记录'
        : '要做什么？',
  );

  void _openMobilePage(_MobileTaskPage page) {
    FocusScope.of(context).unfocus();
    setState(() {
      _mobileAutofocus = false;
      _mobileQuery = '';
      _mobilePage = page;
      if (page == _MobileTaskPage.calendar) {
        _calendarFocusedDay = _dueDate ?? DateTime.now();
      }
    });
  }

  void _backMobilePage() => setState(() {
    _mobileQuery = '';
    _mobilePage = _mobilePage == _MobileTaskPage.calendar
        ? _MobileTaskPage.date
        : null;
  });

  Widget _mobileEditorContent(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.4;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            _titleInput(
              context,
              multiline: true,
              contentPadding: EdgeInsets.fromLTRB(
                14, 12, 14, compact ? 148 : 110,
              ),
            ),
            Positioned(
              left: 12, right: 12, bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: SlowlightSpacing.xs,
                      runSpacing: 0,
                      children: _mobilePropertyButtons(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _submitButton(),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
      const SizedBox(height: SlowlightSpacing.md),
      FxExpansionTile(
        key: const ValueKey('task-create-settings'),
        title: const Text('更多设置'),
        enabled: !_saving,
        tilePadding: const EdgeInsets.symmetric(vertical: 12),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [_advancedContent(context)],
      ),
      if (_listLoadFailed) _listLoadNotice(),
      if (_error != null) ...[
        const SizedBox(height: SlowlightSpacing.md),
        Text(
          _error!,
          style: SlowlightTypography.caption(context).copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    ],
  );

  Color? _selectedTagColor() {
    if (_selectedTagId == null) return null;
    for (final tag in _availableTags) {
      if (tag.id == _selectedTagId) {
        return ColorUtils.safeParse(tag.color, fallback: activePalette.accent);
      }
    }
    return activePalette.accent;
  }

  List<Widget> _mobilePropertyButtons() => [
    _mobileProperty(
      key: const ValueKey('task-property-list'),
      icon: LucideIcons.folder,
      category: '清单',
      label: _loadingLists ? '读取中' : _selectedListName(),
      showLabel: _selectedListId != null && !_loadingLists,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onTap: _loadingLists || _saving
          ? null : () => _openMobilePage(_MobileTaskPage.list),
    ),
    _mobileProperty(
      key: const ValueKey('task-property-date'),
      icon: LucideIcons.calendarDays,
      category: '日期',
      label: _dueDate == null ? '未安排'
          : _dueToday ? '今天'
          : _dueTomorrow ? '明天'
          : '${_dueDate!.month}/${_dueDate!.day}',
      showLabel: _dueDate != null,
      color: AppTheme.info,
      onTap: _saving ? null : () => _openMobilePage(_MobileTaskPage.date),
    ),
    _mobileProperty(
      key: const ValueKey('task-property-priority'),
      icon: LucideIcons.flag,
      category: '优先级',
      label: _selectedPriority == 'none'
          ? '无优先级' : _priorityLabel(_selectedPriority),
      showLabel: _selectedPriority != 'none',
      color: AppTheme.priorityColor(_selectedPriority),
      onTap: _saving ? null : () => _openMobilePage(_MobileTaskPage.priority),
    ),
    _mobileProperty(
      key: const ValueKey('task-property-tag'),
      icon: LucideIcons.tag,
      category: '标签',
      label: _selectedTagId == null ? '无标签' : _selectedTagName(),
      showLabel: _selectedTagId != null,
      color: _selectedTagColor() ??
          Theme.of(context).colorScheme.onSurfaceVariant,
      onTap: _saving ? null : () => _openMobilePage(_MobileTaskPage.tag),
    ),
  ];

  Widget _mobileProperty({
    required Key key,
    required IconData icon,
    required String category,
    required String label,
    required bool showLabel,
    required Color color,
    required VoidCallback? onTap,
  }) => Semantics(
    label: '$category：$label',
    button: true,
    child: showLabel
        ? FxChip(
            key: key,
            icon: icon,
            label: label,
            variant: FxChipVariant.secondary,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            foregroundColor: color,
            borderRadius: SlowlightRadius.md,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onTap: onTap,
          )
        : FxIconButton(
            key: key,
            icon: icon,
            iconSize: SlowlightIconSize.md,
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            tooltip: '$category：$label',
            onPressed: onTap,
          ),
  );

  String get _mobilePageTitle => switch (_mobilePage) {
    _MobileTaskPage.list => '选择清单',
    _MobileTaskPage.date => '安排日期',
    _MobileTaskPage.priority => '设置优先级',
    _MobileTaskPage.tag => '选择标签',
    _MobileTaskPage.calendar => '选择日期',
    null => '添加任务',
  };

  List<_QuickOption<Object>> _mobileOptions() => switch (_mobilePage) {
    _MobileTaskPage.list => [
      for (final list in _lists)
        _QuickOption<Object>(
          value: list.id, label: list.name,
          icon: LucideIcons.folder, emoji: list.icon,
        ),
    ],
    _MobileTaskPage.date => const [
      _QuickOption<Object>(value: 1, label: '今天', icon: LucideIcons.calendarCheck),
      _QuickOption<Object>(value: 3, label: '明天', icon: LucideIcons.calendarPlus),
      _QuickOption<Object>(
        value: 2, label: '选择其他日期',
        icon: LucideIcons.calendarRange, opensPicker: true,
      ),
      _QuickOption<Object>(value: 0, label: '不安排日期', icon: LucideIcons.calendarX),
    ],
    _MobileTaskPage.priority => const [
      _QuickOption<Object>(value: 'none', label: '无优先级', icon: LucideIcons.flag),
      _QuickOption<Object>(
        value: 'urgent_important', label: '高', icon: LucideIcons.flag,
        iconColor: AppTheme.priorityUrgentImportant,
      ),
      _QuickOption<Object>(
        value: 'important', label: '中', icon: LucideIcons.flag,
        iconColor: AppTheme.priorityImportant,
      ),
      _QuickOption<Object>(
        value: 'urgent', label: '低', icon: LucideIcons.flag,
        iconColor: AppTheme.priorityUrgent,
      ),
    ],
    _MobileTaskPage.tag => [
      const _QuickOption<Object>(value: -1, label: '无标签', icon: LucideIcons.tag),
      for (final tag in _availableTags)
        _QuickOption<Object>(
          value: tag.id, label: '#${tag.name}', icon: LucideIcons.tag,
          iconColor: ColorUtils.safeParse(
            tag.color, fallback: activePalette.accent,
          ),
        ),
    ],
    _ => const [],
  };

  Object? _selectedMobileValue() => switch (_mobilePage) {
    _MobileTaskPage.list => _selectedListId,
    _MobileTaskPage.date => _dueDate == null ? 0
        : _dueToday ? 1 : _dueTomorrow ? 3 : 2,
    _MobileTaskPage.priority => _selectedPriority,
    _MobileTaskPage.tag => _selectedTagId ?? -1,
    _ => null,
  };

  void _chooseMobileOption(Object value) {
    switch (_mobilePage) {
      case _MobileTaskPage.list:
        setState(() {
          _selectedListId = value as int;
          _mobilePage = null;
        });
      case _MobileTaskPage.date:
        if (value == 2) {
          _openMobilePage(_MobileTaskPage.calendar);
          return;
        }
        final today = _today();
        setState(() {
          _dueDate = switch (value) {
            1 => today,
            3 => DateTime(today.year, today.month, today.day + 1),
            _ => null,
          };
          _mobilePage = null;
        });
      case _MobileTaskPage.priority:
        setState(() {
          _selectedPriority = value as String;
          _mobilePage = null;
        });
      case _MobileTaskPage.tag:
        setState(() {
          final id = value as int;
          _selectedTagId = id == -1 ? null : id;
          _mobilePage = null;
        });
      case _MobileTaskPage.calendar:
      case null:
        break;
    }
  }

  Widget _mobilePickerContent(BuildContext context) {
    final isCalendar = _mobilePage == _MobileTaskPage.calendar;
    final options = _mobileOptions();
    final showSearch = (_mobilePage == _MobileTaskPage.list ||
        _mobilePage == _MobileTaskPage.tag) && options.length >= 8;
    final visible = _mobileQuery.isEmpty
        ? options
        : options.where(
            (item) => item.label.toLowerCase().contains(_mobileQuery),
          ).toList(growable: false);
    final height = math.min(
      MediaQuery.sizeOf(context).height * (isCalendar ? .68 : .55),
      isCalendar ? 440.0 : 66.0 + (showSearch ? 58.0 : 0) +
          visible.length * 48.0 +
          (_mobilePage == _MobileTaskPage.date ? 12.0 : 0),
    );
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            FxIconButton(
              key: const ValueKey('task-picker-back'),
              icon: LucideIcons.arrowLeft,
              tooltip: '返回',
              onPressed: _backMobilePage,
            ),
            const SizedBox(width: SlowlightSpacing.md),
            Expanded(child: Text(
              _mobilePageTitle,
              style: SlowlightTypography.cardTitle(context),
            )),
            // 外层 FxSheet 已有关闭按钮，此处禁止重复绘制。
            const SizedBox(width: 32),
          ]),
          const FxSeparator.horizontal(height: 12),
          if (showSearch) ...[
            FxInput(
              key: ValueKey('task-picker-search-${_mobilePage!.name}'),
              placeholder: _mobilePage == _MobileTaskPage.list
                  ? '搜索清单' : '搜索标签',
              leading: const Icon(
                LucideIcons.search, size: SlowlightIconSize.sm,
              ),
              onChanged: (value) => setState(
                () => _mobileQuery = value.trim().toLowerCase(),
              ),
            ),
            const SizedBox(height: SlowlightSpacing.md),
          ],
          Expanded(
            child: isCalendar
                ? SingleChildScrollView(
                    child: FxCalendar<Object>(
                      firstDay: _today().subtract(const Duration(days: 365)),
                      lastDay: _today().add(const Duration(days: 365 * 3)),
                      focusedDay: _calendarFocusedDay,
                      selectedDay: _dueDate,
                      eventLoader: (_) => const <Object>[],
                      onDaySelected: (day, focusedDay) => setState(() {
                        _dueDate = DateTime(day.year, day.month, day.day);
                        _calendarFocusedDay = focusedDay;
                        _mobilePage = null;
                      }),
                      onPageChanged: (day) => setState(
                        () => _calendarFocusedDay = day,
                      ),
                    ),
                  )
                : visible.isEmpty
                    ? Center(child: Text('没有匹配项',
                        style: SlowlightTypography.componentSecondary(context)))
                    : ListView.builder(
                        itemCount: visible.length,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemBuilder: (context, index) {
                          final option = visible[index];
                          final selected = _selectedMobileValue() == option.value;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_mobilePage == _MobileTaskPage.date &&
                                  index == visible.length - 1)
                                const FxSeparator.horizontal(height: 12),
                              FxListTile(
                                density: FxListTileDensity.compact,
                                minTileHeight: 48,
                                title: option.label,
                                leading: option.emoji == null
                                    ? Icon(option.icon, size: SlowlightIconSize.md)
                                    : Text(option.emoji!),
                                iconColor: option.iconColor,
                                trailing: selected
                                    ? const Icon(LucideIcons.check,
                                        size: SlowlightIconSize.md)
                                    : option.opensPicker
                                        ? const Icon(LucideIcons.chevronRight,
                                            size: SlowlightIconSize.sm)
                                        : null,
                                selected: selected,
                                selectedTileColor:
                                    activePalette.accent.withValues(alpha: .08),
                                onTap: () => _chooseMobileOption(option.value),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _editorContent(BuildContext context) {
    if (!widget.desktopDialog) return _mobileEditorContent(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleInput(context),
        const SizedBox(height: 12),
        if (_loadingLists)
          Text(
            '正在读取清单…',
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else ...[
          FxExpansionTile(
            key: const ValueKey('task-create-lists'),
            initiallyExpanded: true,
            enabled: !_saving,
            tilePadding: const EdgeInsets.symmetric(vertical: 12),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            onExpansionChanged: (expanded) => setState(() => _showLists = expanded),
            title: Text(_showLists ? '清单' : '清单 · ${_selectedListName()}'),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._lists.map(
                    (list) => _QuickChip(
                      text: '${list.icon} ${list.name}',
                      selected: _selectedListId == list.id,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedListId = list.id);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _QuickChip(
              icon: LucideIcons.calendarDays,
              text: _dueDate != null && !_dueToday
                  ? '${_dueDate!.month}/${_dueDate!.day}'
                  : '今天',
              selected: _dueDate != null,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _dueDate = _dueToday ? null : _today());
              },
            ),
            _QuickChip(
              icon: LucideIcons.flag,
              text: _selectedPriority == 'none'
                  ? '无优先级'
                  : '优先级：${_priorityLabel(_selectedPriority)}',
              selected: _selectedPriority != 'none',
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedPriority = _nextPriority(_selectedPriority);
                });
              },
            ),
            _QuickChip(
              icon: _showTags ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              text: _selectedTagName(),
              selected: _selectedTagId != null,
              onTap: () => setState(() => _showTags = !_showTags),
            ),
          ],
        ),
        if (_showTags) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          TagChoiceField(
            tags: _availableTags,
            selectedTagId: _selectedTagId,
            enabled: !_saving,
            onChanged: (id) => setState(() => _selectedTagId = id),
          ),
        ],
        FxExpansionTile(
          key: const ValueKey('task-create-settings'),
          title: const Text('更多设置'),
          enabled: !_saving,
          tilePadding: const EdgeInsets.symmetric(vertical: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [_advancedContent(context)],
        ),
        if (_listLoadFailed) _listLoadNotice(),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _advancedContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FxInput(
        controller: _descriptionController,
        enabled: !_saving,
        minLines: 1,
        maxLines: 3,
        placeholder: '描述（可选）',
        style: SlowlightTypography.componentSecondary(context),
      ),
      SizedBox(height: widget.desktopDialog ? 16 : 12),
      TaskScheduleFields(
        compact: !widget.desktopDialog,
        enabled: !_saving,
        dueDate: _dueDate,
        onDateChanged: (date) => setState(() => _dueDate = date),
        dueTime: _dueTime,
        onTimeChanged: (time) => setState(() => _dueTime = time),
        repeatType: _repeatType,
        onRepeatChanged: (value) => setState(() {
          _repeatType = value;
          if (value != 'weekly') _selectedWeekdays.clear();
        }),
        selectedWeekdays: _selectedWeekdays,
        onWeekdayToggled: (day) => setState(() {
          if (!_selectedWeekdays.add(day)) _selectedWeekdays.remove(day);
        }),
        reminderAdvanceMinutes: _reminderAdvanceMinutes,
        onReminderChanged: (value) => setState(() => _reminderAdvanceMinutes = value),
      ),
    ],
  );

  Widget _submitButton() => FxButton(
    label: _saving ? '添加中…' : '添加任务',
    size: widget.desktopDialog ? FxButtonSize.sm : FxButtonSize.md,
    onPressed: _saving ? null : _createTask,
  );

  Widget _editorActions() => FxDialogActions(actions: [_submitButton()]);

  @override
  Widget build(BuildContext context) {
    if (widget.desktopDialog) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: SingleChildScrollView(child: _editorContent(context))),
            const SizedBox(height: 12),
            _editorActions(),
          ],
        ),
      );
    }

    // 单一 FxSheet 内容切换，避免第二层弹窗和双关闭按钮。
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: _mobilePage != null
              ? _mobilePickerContent(context)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '添加任务',
                      style: SlowlightTypography.cardTitle(context)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.manual,
                        child: _editorContent(context),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _createTask() async {
    final title = _titleController.text.trim();
    if (_listLoadFailed || _loadingLists) {
      setState(() => _error = '清单尚未就绪，请先重新加载清单');
      return;
    }
    if (title.isEmpty || _saving) {
      if (title.isEmpty) setState(() => _error = '先写下要做的事情');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final notice = FxNotice.capture(context);
    final description = _descriptionController.text.trim();
    final dueTime = formatTaskDueTime(_dueTime);
    final repeatDays = formatTaskRepeatDays(_repeatType, _selectedWeekdays);
    final reminderAt = buildTaskReminderAt(
      dueDate: _dueDate,
      dueTime: _dueTime,
      advanceMinutes: _reminderAdvanceMinutes,
    );
    try {
      final systemTagId = _selectedTagId;
      final listId = _selectedListId;
      late Task task;
      if (listId == null) {
        task = await DataService().quickAddToInbox(
          title,
          systemTagId: systemTagId,
        );
        if (_selectedPriority != 'none' || _dueDate != null ||
            description.isNotEmpty || dueTime != null ||
            _repeatType != 'none' || _reminderAdvanceMinutes >= 0) {
          task = await DataService().updateTask(
            localId: task.id,
            listId: task.listId,
            title: task.title,
            description: description.isEmpty ? null : description,
            priority: _selectedPriority,
            dueDate: _dueDate,
            dueTime: dueTime,
            repeatType: _repeatType,
            repeatInterval: 1,
            repeatDays: repeatDays,
            reminderAt: reminderAt,
            reminderAdvanceMinutes: _reminderAdvanceMinutes < 0 ? 0 : _reminderAdvanceMinutes,
            tagIds: task.tags.map((tag) => tag.id).toList(growable: false),
            systemTagId: task.systemTagId,
            taskType: task.taskType,
            moodBefore: task.moodBefore,
            moodAfter: task.moodAfter,
            isMilestone: task.isMilestone,
            relatedQuestId: task.relatedQuestId,
            obsidianLink: task.obsidianLink,
            outputLevel: task.outputLevel,
          );
        }
      } else {
        task = await DataService().createTask(
          listId: listId,
          title: title,
          description: description.isEmpty ? null : description,
          priority: _selectedPriority,
          dueDate: _dueDate,
          dueTime: dueTime,
          repeatType: _repeatType,
          repeatInterval: 1,
          repeatDays: repeatDays,
          reminderAt: reminderAt,
          reminderAdvanceMinutes: _reminderAdvanceMinutes < 0 ? 0 : _reminderAdvanceMinutes,
          systemTagId: systemTagId,
        );
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      widget.onCreated?.call();
      Navigator.pop(context);
      notice.showContent(Text(_createdText(task)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '记录失败：$e';
      });
    }
  }

  bool get _dueToday {
    if (_dueDate == null) return false;
    final today = _today();
    return _dueDate!.year == today.year &&
        _dueDate!.month == today.month && _dueDate!.day == today.day;
  }

  bool get _dueTomorrow {
    if (_dueDate == null) return false;
    final today = _today();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    return _dueDate!.year == tomorrow.year &&
        _dueDate!.month == tomorrow.month &&
        _dueDate!.day == tomorrow.day;
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _selectedListName() {
    for (final list in _lists) {
      if (list.id == _selectedListId) return list.name;
    }
    return '收集箱';
  }

  String _createdText(Task task) {
    final listName = task.list?.name ?? _selectedListName();
    final dateText = _dueDate == null
        ? ''
        : _dueToday
            ? ' · 今天'
            : ' · ${_dueDate!.month}/${_dueDate!.day}';
    final priorityText =
        _selectedPriority == 'none'
            ? ''
            : ' · ${_priorityLabel(_selectedPriority)}';
    final tagText = _selectedTagId == null ? '' : ' · ${_selectedTagName()}';
    return '任务已添加到「$listName」$dateText$priorityText$tagText';
  }

  String _selectedTagName() {
    if (_selectedTagId == null) return '标签';
    for (final tag in _availableTags) {
      if (tag.id == _selectedTagId) return '#${tag.name}';
    }
    if (_selectedTagId == widget.systemTagId &&
        (widget.systemTagName ?? '').isNotEmpty) {
      return '#${widget.systemTagName}';
    }
    return '标签';
  }

  String _normalizePriority(String value) => switch (value) {
    'urgent_important' || 'important' || 'urgent' || 'none' => value,
    _ => 'none',
  };

  // 与完整表单的优先级选项保持同名，避免快捷记录出现冗长的第二行。
  String _priorityLabel(String value) => switch (value) {
    'urgent_important' => '高',
    'important' => '中',
    'urgent' => '低',
    _ => '无',
  };

  String _nextPriority(String value) => switch (value) {
    'none' => 'urgent_important',
    'urgent_important' => 'important',
    'important' => 'urgent',
    _ => 'none',
  };
}

class _QuickChip extends StatelessWidget {
  final IconData? icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _QuickChip({
    this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FxChoiceChip(
      label: text,
      icon: icon,
      selected: selected,
      selectionColor: activePalette.accent,
      onTap: onTap,
    );
  }
}

class _DefaultHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DefaultHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return FxChip(
      label: text,
      icon: icon,
      backgroundColor: fxSubtleSurface(context),
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      borderColor: fxBorder(context),
      borderRadius: 999,
    );
  }
}

enum _MobileTaskPage { list, date, priority, tag, calendar }

class _QuickOption<T> {
  final T value;
  final String label;
  final IconData icon;
  final String? emoji;
  final Color? iconColor;
  final bool opensPicker;

  const _QuickOption({
    required this.value,
    required this.label,
    required this.icon,
    this.emoji,
    this.iconColor,
    this.opensPicker = false,
  });
}
