import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/observation_tag.dart';
import '../models/tag.dart';
import '../repositories/tag_repository.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/data_service.dart';
import '../services/api/task_api.dart';

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
  final TagRepository? tagRepository;
  final DataService? dataService;

  const TaskCreateSheet({
    super.key,
    this.quickMode = false,
    this.desktopDialog = false,
    this.systemTagId,
    this.systemTagName,
    this.initialPriority = 'none',
    this.defaultDueToday = true,
    this.onCreated,
    this.tagRepository,
    this.dataService,
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
        showCloseButton: false,
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
      showCloseButton: false,
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
    final inboxes = resolvedLists.where((list) => list.isInbox);
    final defaultListId = inboxes.isEmpty
        ? resolvedLists.first.id
        : inboxes.first.id;
    final editor = AddTaskScreen(
      lists: resolvedLists,
      selectedListId: selectedListId ?? defaultListId,
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
  late final TagRepository _tagsRepository;
  late final DataService _dataService;
  Task? _pendingCreatedTask;
  bool _creationResultUnknown = false;
  bool _parentNotifiedOfCreation = false;
  List<Tag> _availableTags = const [];
  final Set<int> _selectedTagIds = {};
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
  bool _loadingTags = true;
  bool _tagLoadFailed = false;
  bool _saving = false;
  String? _error;
  _MobileTaskPage? _mobilePage;
  String _mobileQuery = '';
  bool _mobileAutofocus = true;
  late DateTime _calendarFocusedDay;

  @override
  void initState() {
    super.initState();
    _tagsRepository = widget.tagRepository ?? TagRepository();
    _dataService = widget.dataService ?? DataService();
    _dueDate = widget.defaultDueToday ? _today() : null;
    _selectedPriority = _normalizePriority(widget.initialPriority);
    // 旧 system_tag_id 独立透传，不混入 canonical 标签集合。
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
      final lists = await _dataService.getLists();
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
      final tags = await _tagsRepository.getTags();
      if (!mounted) return;
      setState(() {
        _availableTags = tags;
        _loadingTags = false;
        _tagLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 不将网络失败伪装成“没有标签”，已读取的数据仍保留。
      setState(() {
        _loadingTags = false;
        _tagLoadFailed = true;
      });
    }
  }

  Widget _tagLoadNotice() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '标签加载失败，可重试；不选标签仍可创建任务。',
        style: SlowlightTypography.secondary(context).copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: SlowlightSpacing.md),
      FxButton(
        key: const ValueKey('task-picker-retry-tags'),
        label: '重试加载标签',
        variant: FxButtonVariant.outline,
        size: FxButtonSize.sm,
        onPressed: _saving || _loadingTags ? null : () {
          setState(() => _loadingTags = true);
          _loadTags();
        },
      ),
    ],
  );

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
    // 选项明确切换页面时再收键盘；拖动表单留白不应让标题失焦。
    onPressedOutside: (_) {},
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
        if (_creationResultUnknown) _unknownResultRecovery(),
      ],
    ],
  );

  List<ObservationTag> get _tagOptions => [
    for (final tag in _availableTags)
      ObservationTag(id: tag.id, name: tag.name, color: tag.color, icon: ''),
  ];

  Color? _selectedTagColor() {
    if (_selectedTagIds.isEmpty) return null;
    for (final tag in _availableTags) {
      if (_selectedTagIds.contains(tag.id)) {
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
          ? '不重要 · 不紧急' : _priorityLabel(_selectedPriority),
      showLabel: _selectedPriority != 'none',
      color: AppTheme.priorityColor(_selectedPriority),
      onTap: _saving ? null : () => _openMobilePage(_MobileTaskPage.priority),
    ),
    _mobileProperty(
      key: const ValueKey('task-property-tag'),
      icon: LucideIcons.tag,
      category: '标签',
      label: _selectedTagIds.isEmpty ? '无标签' : _selectedTagName(),
      showLabel: _selectedTagIds.isNotEmpty,
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
      _QuickOption<Object>(value: 'none', label: '不重要 · 不紧急', icon: LucideIcons.flag),
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
    _MobileTaskPage.tag => null,
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
          if (id == -1) {
            _selectedTagIds.clear();
          } else if (!_selectedTagIds.add(id)) {
            _selectedTagIds.remove(id);
          }
          // 多选继续停留在选择页，由用户点「完成」返回。
        });
      case _MobileTaskPage.calendar:
      case null:
        break;
    }
  }

  Widget _mobileOptionTile(
    BuildContext context,
    _QuickOption<Object> option, {
    required bool compact,
  }) {
    final selected = _mobilePage == _MobileTaskPage.tag
        ? (option.value == -1 ? _selectedTagIds.isEmpty : _selectedTagIds.contains(option.value))
        : _selectedMobileValue() == option.value;
    return FxListTile(
      key: ValueKey('task-picker-option-${_mobilePage!.name}-${option.value}'),
      density: FxListTileDensity.compact,
      minTileHeight: 48,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? SlowlightSpacing.md : SlowlightSpacing.xl,
        vertical: compact ? SlowlightSpacing.xs : SlowlightSpacing.md,
      ),
      title: Text(
        option.label,
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: SlowlightTypography.componentSecondary(context).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      leading: option.emoji == null
          ? Icon(option.icon, size: SlowlightIconSize.md)
          : Text(option.emoji!),
      iconColor: option.iconColor,
      trailing: selected
          ? const Icon(LucideIcons.check, size: SlowlightIconSize.md)
          : option.opensPicker
              ? const Icon(LucideIcons.chevronRight, size: SlowlightIconSize.sm)
              : null,
      selected: selected,
      selectedTileColor: activePalette.accent.withValues(alpha: .08),
      onTap: () => _chooseMobileOption(option.value),
    );
  }

  Widget _mobilePickerContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCalendar = _mobilePage == _MobileTaskPage.calendar;
        final options = _mobileOptions();
        final showSearch = (_mobilePage == _MobileTaskPage.list ||
            _mobilePage == _MobileTaskPage.tag) && options.length >= 8;
        final visible = _mobileQuery.isEmpty
            ? options
            : options.where(
                (item) => item.label.toLowerCase().contains(_mobileQuery),
              ).toList(growable: false);
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final noTags = _mobilePage == _MobileTaskPage.tag &&
            _availableTags.isEmpty && !_loadingTags && !_tagLoadFailed;
        final tagStatus = _mobilePage == _MobileTaskPage.tag &&
            (_loadingTags || _tagLoadFailed);
        final availableHeight = math.min(
          constraints.maxHeight,
          MediaQuery.sizeOf(context).height * (isCalendar ? .68 : .55),
        );
        final commonHeight = 66.0 +
            (showSearch ? 58.0 : 0) +
            (noTags ? 28.0 : 0) +
            (tagStatus ? 84.0 : 0);
        final gridRows = (visible.length + 1) ~/ 2;
        // 双列必须实际放得下；短屏、键盘及大字体回退到可滚动单列。
        final twoColumns = !isCalendar && constraints.maxWidth >= 300 &&
            textScale < 1.4 && visible.length <= 8 &&
            commonHeight + gridRows * 56.0 <= availableHeight;
        final rows = twoColumns ? gridRows : visible.length;
        final height = math.min(
          availableHeight,
          isCalendar ? 440.0 : commonHeight + rows * 56.0,
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
                if (_mobilePage == _MobileTaskPage.tag)
                  FxButton(
                    label: '完成',
                    size: FxButtonSize.sm,
                    variant: FxButtonVariant.outline,
                    onPressed: _backMobilePage,
                  )
                else
                  FxIconButton(
                    icon: LucideIcons.x,
                    tooltip: '取消添加任务',
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  ),
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
              if (_mobilePage == _MobileTaskPage.tag && _loadingTags)
                Padding(
                  padding: const EdgeInsets.only(bottom: SlowlightSpacing.md),
                  child: Text(
                    '正在加载标签…',
                    style: SlowlightTypography.caption(context),
                  ),
                ),
              if (_mobilePage == _MobileTaskPage.tag && _tagLoadFailed)
                Padding(
                  padding: const EdgeInsets.only(bottom: SlowlightSpacing.md),
                  child: _tagLoadNotice(),
                ),
              if (noTags)
                Padding(
                  padding: const EdgeInsets.only(bottom: SlowlightSpacing.md),
                  child: Text(
                    '暂无标签，可直接不选标签',
                    style: SlowlightTypography.caption(context),
                  ),
                ),
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
                        ? Center(child: Text(
                                    '没有匹配项',
                                    style: SlowlightTypography.componentSecondary(context),
                                  ))
                        : twoColumns
                            ? GridView.builder(
                                        key: const ValueKey('task-picker-grid'),
                                        padding: EdgeInsets.zero,
                                        physics: const NeverScrollableScrollPhysics(),
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          crossAxisSpacing: SlowlightSpacing.md,
                                          mainAxisSpacing: SlowlightSpacing.md,
                                          mainAxisExtent: 48,
                                        ),
                                        itemCount: visible.length,
                                        itemBuilder: (context, index) =>
                                            _mobileOptionTile(
                                              context,
                                              visible[index],
                                              compact: true,
                                            ),
                                      )
                                    : ListView.builder(
                                        key: const ValueKey('task-picker-list'),
                                        padding: EdgeInsets.zero,
                                        itemCount: visible.length,
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior.onDrag,
                                        itemBuilder: (context, index) =>
                                            _mobileOptionTile(
                                              context,
                                              visible[index],
                                              compact: false,
                                            ),
                                      ),
              ),
            ],
          ),
        );
      },
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
                  ? '不重要 · 不紧急'
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
              selected: _selectedTagIds.isNotEmpty,
              onTap: () => setState(() => _showTags = !_showTags),
            ),
          ],
        ),
        if (_showTags) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          TagChoiceField(
            tags: _tagOptions,
            selectedTagIds: _selectedTagIds,
            label: '标签（可多选）',
            enabled: !_saving && !_loadingTags && !_tagLoadFailed,
            onMultipleChanged: (ids) => setState(() {
              _selectedTagIds..clear()..addAll(ids);
            }),
          ),
          if (_loadingTags)
            Text('正在读取标签…', style: SlowlightTypography.caption(context)),
          if (_tagLoadFailed) _tagLoadNotice(),
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
          if (_creationResultUnknown) _unknownResultRecovery(),
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

  Widget _unknownResultRecovery() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FxButton(
      label: '我已核对任务列表，仍需重试',
      variant: FxButtonVariant.outline,
      size: FxButtonSize.sm,
      onPressed: () => setState(() {
        _creationResultUnknown = false;
        _error = null;
      }),
    ),
  );

  Widget _submitButton() => FxButton(
    label: _saving ? '保存中…' : _pendingCreatedTask != null ? '重试保存其余设置' : '添加任务',
    size: widget.desktopDialog ? FxButtonSize.sm : FxButtonSize.md,
    onPressed: _saving || _creationResultUnknown ? null : _createTask,
  );

  Widget _editorActions() => FxDialogActions(actions: [
    FxButton(
      label: '取消',
      variant: FxButtonVariant.ghost,
      onPressed: _saving ? null : () => Navigator.of(context).pop(),
    ),
    _submitButton(),
  ]);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving && _mobilePage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving && _mobilePage != null) _backMobilePage();
      },
      child: _buildEditor(context),
    );
  }

  Widget _buildEditor(BuildContext context) {
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
                    Row(children: [
                      Expanded(child: Text(
                        '添加任务',
                        style: SlowlightTypography.cardTitle(context)
                            .copyWith(fontWeight: FontWeight.w700),
                      )),
                      FxIconButton(
                        icon: LucideIcons.x,
                        tooltip: '取消添加任务',
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      ),
                    ]),
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
      final systemTagId = widget.systemTagId;
      final tagIds = _selectedTagIds.toList(growable: false);
      final listId = _selectedListId;
      late Task task;
      if (listId == null || _pendingCreatedTask != null) {
        // 无清单时旧接口需先建收集箱任务；若后续附加属性失败，
        // 下次只能更新已存在的记录，绝不能再发起一次创建。
        task = _pendingCreatedTask ?? await _dataService.quickAddToInbox(
          title,
          systemTagId: systemTagId,
        );
        _pendingCreatedTask = task;
        if (!_parentNotifiedOfCreation) {
          _parentNotifiedOfCreation = true;
          widget.onCreated?.call();
        }
        if (_selectedPriority != 'none' || _dueDate != null ||
            description.isNotEmpty || tagIds.isNotEmpty || dueTime != null ||
            _repeatType != 'none' || _reminderAdvanceMinutes > 0) {
          task = await _dataService.updateTask(
            localId: task.id,
            listId: listId ?? task.listId,
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
            tagIds: {...task.tags.map((tag) => tag.id), ...tagIds}.toList(growable: false),
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
        task = await _dataService.createTask(
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
          tagIds: tagIds,
          systemTagId: systemTagId,
        );
      }
      _pendingCreatedTask = null;
      _creationResultUnknown = false;
      if (!mounted) return;
      HapticFeedback.lightImpact();
      if (!_parentNotifiedOfCreation) widget.onCreated?.call();
      Navigator.pop(context);
      notice.showContent(Text(_createdText(task)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        final confirmedFailure =
            e is TaskCreateException && e.confirmedNotCreated;
        _creationResultUnknown = _pendingCreatedTask == null && !confirmedFailure;
        _error = _pendingCreatedTask != null
            ? '任务已创建，但其余设置尚未保存。重试只会更新原任务，不会重复创建。'
            : confirmedFailure
                ? '创建失败：${(e as TaskCreateException).message}'
                : '创建结果未确认。请先查看任务列表确认是否已经生成，避免重复创建。';
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
    final tagText = _selectedTagIds.isEmpty ? '' : ' · ${_selectedTagName()}';
    return '任务已添加到「$listName」$dateText$priorityText$tagText';
  }

  String _selectedTagName() {
    if (_selectedTagIds.isEmpty) return '标签';
    if (_selectedTagIds.length > 1) return '${_selectedTagIds.length} 个标签';
    final id = _selectedTagIds.first;
    for (final tag in _availableTags) {
      if (tag.id == id) return '#${tag.name}';
    }
    return '1 个标签';
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
    _ => '不重要 · 不紧急',
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
