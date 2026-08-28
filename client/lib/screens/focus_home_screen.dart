import 'dart:math' as math;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/habit.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../navigation/home_navigation_state.dart';
import '../repositories/habit_repository.dart';
import '../services/data_service.dart';
import '../services/notification_service.dart';
import '../services/tray_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../ui/widgets/slowlight_logo.dart';
import '../widgets/dashboard/dashboard.dart';
import '../widgets/habit_checkin_dialog.dart';
import '../widgets/reflection_composer.dart';
import '../widgets/sync_status_badge.dart';
import '../widgets/task_detail_sheet.dart';
import 'calendar_screen.dart';
import 'habit_tool_screen.dart';
import 'list_manage_screen.dart';
import 'pomodoro_screen.dart';
import 'quadrant_screen.dart';
import 'reminder_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'stats_screen.dart';
import 'system_tag_screen.dart';
import 'task_create_sheet.dart';
import 'task_tool_screen.dart';
import 'time_distribution_screen.dart';
import 'today_review_screen.dart';
import 'weekly_review_screen.dart';

/// Slowlight 主壳层。桌面严格使用高保真原型的 232px 左侧栏；
/// 主内容页自己承担页面头部，不再叠加一层通用顶栏。
class FocusHomeScreen extends StatefulWidget {
  const FocusHomeScreen({super.key});

  @override
  State<FocusHomeScreen> createState() => _FocusHomeScreenState();
}

class _FocusHomeScreenState extends State<FocusHomeScreen> {
  HomeNavigationState _navigation = const HomeNavigationState.today();
  List<TodoList> _lists = const [];
  List<Task> _tasks = const [];
  List<Habit> _habits = const [];
  bool _loading = true;
  bool _organizeToolsExpanded = false;
  bool _shortcutModifierPressed = false;
  int _dashboardRefreshTick = 0;
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'Slowlight global shortcuts',
  );
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();
  Offset _fabDragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _reload();
    NotificationService().checkAndScheduleReminders();
    TrayService().loadAfterLogin();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingTask());
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  bool _handleKeyboardShortcut(KeyEvent event) {
    final key = event.logicalKey;
    final isModifier = key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
    if (isModifier) {
      if (event is KeyDownEvent) _shortcutModifierPressed = true;
      if (event is KeyUpEvent) _shortcutModifierPressed = false;
      return false;
    }
    if (event is! KeyDownEvent || key != LogicalKeyboardKey.keyK) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifierPressed = _shortcutModifierPressed ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    if (!modifierPressed || !mounted) return false;
    _openSearch();
    return true;
  }

  Future<void> _reload() async {
    try {
      final results = await Future.wait<dynamic>([
        DataService().getLists(),
        DataService().getTodayTasks(),
        HabitRepository().getAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _lists = results[0] as List<TodoList>;
        _tasks = results[1] as List<Task>;
        _habits = results[2] as List<Habit>;
        _loading = false;
        _dashboardRefreshTick++;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('数据加载失败');
    }
  }

  Future<void> _openPendingTask() async {
    final taskId = NotificationService.pendingTaskId;
    if (taskId == null) return;
    NotificationService.pendingTaskId = null;
    Task? task;
    for (final item in _tasks) {
      if (item.id == taskId) {
        task = item;
        break;
      }
    }
    if (task == null) {
      await _reload();
      for (final item in _tasks) {
        if (item.id == taskId) {
          task = item;
          break;
        }
      }
    }
    if (task != null && mounted) _openTask(task);
  }

  void _openPrimary(HomePrimarySection section) {
    setState(() {
      _navigation = _navigation.openPrimary(section);
      _organizeToolsExpanded = false;
    });
    if (section == HomePrimarySection.today) _reload();
  }

  bool _isOrganizeTool(HomeToolSection tool) => switch (tool) {
        HomeToolSection.lists || HomeToolSection.observationTags => true,
        _ => false,
      };

  bool get _isReviewContext =>
      _navigation.primary == HomePrimarySection.review &&
      (_navigation.tool == null ||
          _navigation.tool == HomeToolSection.stats ||
          _navigation.tool == HomeToolSection.weeklyReview ||
          _navigation.tool == HomeToolSection.timeDistribution);

  void _openTool(HomeToolSection tool) {
    setState(() {
      _navigation = _navigation.openTool(tool);
      _organizeToolsExpanded = _isOrganizeTool(tool);
    });
  }

  void _closeTool() {
    setState(() {
      _navigation = _navigation.closeTool();
      _organizeToolsExpanded = false;
    });
  }

  void _openMobileTools() {
    // 工具菜单改为左侧滑出抽屉（替代自下而上的全屏面板）
    _mobileScaffoldKey.currentState?.openDrawer();
  }

  Future<void> _toggleTask(Task task) async {
    try {
      if (task.isCompleted) {
        await DataService().uncompleteTask(task.id, null);
      } else {
        await DataService().completeTask(task.id, null);
      }
      await _reload();
    } catch (_) {
      _message('任务状态更新失败');
    }
  }

  Future<void> _toggleHabit(Habit habit) async {
    final repository = HabitRepository();
    try {
      if (habit.checkedToday) {
        final confirmed = await FxDialog.confirm(
          context: context,
          title: '取消打卡',
          content: '确定取消今天「${habit.name}」的打卡？连续天数将重新计算。',
          confirmText: '取消打卡',
        );
        if (confirmed != true) return;
        await repository.uncheckIn(habit.id);
        _message('已取消「${habit.name}」今天的记录');
        await _reload();
        return;
      }
      int? durationMin;
      String? period;
      String note = '';
      if (habit.showCheckinDialog) {
        final detail = await HabitCheckinDialog.show(context, habit: habit);
        if (detail == null) return;
        durationMin = detail['duration_min'] as int?;
        period = detail['period']?.toString();
        note = detail['note']?.toString() ?? '';
      }
      await repository.checkIn(
        habit.id,
        durationMin: durationMin,
        period: period,
        note: note,
      );
      _message('已记录「${habit.name}」');
      await _reload();
    } catch (_) {
      _message('习惯状态更新失败');
    }
  }

  Future<void> _openDetailedHabitCheckin(Habit habit) async {
    if (habit.checkedToday) {
      _message('今天已记录；当前暂不支持编辑打卡详情');
      return;
    }
    final detail = await HabitCheckinDialog.show(context, habit: habit);
    if (detail == null) return;
    try {
      await HabitRepository().checkIn(
        habit.id,
        durationMin: detail['duration_min'] as int?,
        period: detail['period']?.toString(),
        note: detail['note']?.toString() ?? '',
      );
      _message('已记录「${habit.name}」');
      await _reload();
    } catch (e) {
      _message(e.toString().contains('已打卡') ? '今天已经记录过' : '习惯状态更新失败');
    }
  }

  void _openTask(Task task) {
    TaskDetailSheet.show(
      context,
      task: task,
      lists: _lists,
      onChanged: _reload,
    );
  }

  void _quickAdd() {
    TaskCreateSheet.showQuickCreate(context, onCreated: _reload);
  }

  Future<void> _openSearch() {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  Future<void> _writeObservation() async {
    final saved = await ReflectionComposer.show(
      context,
      entryType: 'observation',
      prompt: '今天有什么值得留下的观察？',
      contextData: const {'source': 'today'},
    );
    if (saved) {
      _message('观察已保存');
      await _reload();
    }
  }

  Future<void> _startFocus() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PomodoroScreen()),
    );
    if (mounted) await _reload();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 1024;
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _buildContent();

    if (desktop) {
      return _shortcutRegion(Scaffold(
        body: Row(
          children: [
            SizedBox(width: 232, child: _navigationPanel(closeDrawer: false)),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: content),
          ],
        ),
      ));
    }

    final theme = Theme.of(context);
    return _shortcutRegion(Scaffold(
      key: _mobileScaffoldKey,
      drawer: Drawer(
        width: math.min(304, MediaQuery.sizeOf(context).width * 0.84),
        backgroundColor: theme.colorScheme.surface,
        child: SafeArea(child: _navigationPanel(closeDrawer: true)),
      ),
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 16,
        title: Text(
          _navigation.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: _navigation.isTool
            ? IconButton(
                icon: const Icon(LucideIcons.chevronLeft, size: 20),
                tooltip: '返回',
                onPressed: _closeTool,
              )
            : IconButton(
                icon: const Icon(LucideIcons.menu, size: 20),
                tooltip: '工具',
                onPressed: _openMobileTools,
              ),
        actions: [
          if (_navigation.isToday) ...[
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: const Icon(LucideIcons.pencil, size: 18),
                tooltip: '写下观察',
                onPressed: _writeObservation,
              ),
            ),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: const Icon(LucideIcons.plus, size: 20),
                tooltip: '记录任务',
                onPressed: _quickAdd,
              ),
            ),
          ],
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
        ),
      ),
      body: content,
      bottomNavigationBar:
          _navigation.isTool ? null : _mobileBottomNavigation(),
      floatingActionButton:
          _navigation.isToday ? _mobileQuickAddButton() : null,
    ));
  }

  Widget _shortcutRegion(Widget child) {
    return Focus(
      key: const ValueKey('global-search-shortcuts'),
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyboardShortcut(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: child,
    );
  }

  Widget _mobileBottomNavigation() {
    final theme = Theme.of(context);
    final today = _navigation.primary == HomePrimarySection.today;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            _mobileBottomNavigationItem(
              icon: LucideIcons.sun,
              label: '今天',
              selected: today,
              onTap: () => _openPrimary(HomePrimarySection.today),
            ),
            _mobileBottomNavigationItem(
              icon: LucideIcons.bookOpen,
              label: '回顾',
              selected: !today,
              onTap: () => _openPrimary(HomePrimarySection.review),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileBottomNavigationItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final color =
        selected ? activePalette.accent : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTheme.textXs,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileQuickAddButton() {
    return GestureDetector(
      onPanUpdate: _onFabPanUpdate,
      child: Transform.translate(
        offset: _fabDragOffset,
        child: Tooltip(
          message: '快速记录任务（按住可拖动）',
          child: Material(
            color: activePalette.accent,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: .18),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _quickAdd,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(LucideIcons.plus, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 拖动 FAB 重定位；边界钳制在屏幕内（留出边距），拖动不影响点按。
  void _onFabPanUpdate(DragUpdateDetails details) {
    final size = MediaQuery.sizeOf(context);
    const fabSize = 48.0;
    const edge = 12.0;
    final maxDx = -(size.width - fabSize - edge * 2);
    final maxDy = -(size.height * 0.72);
    setState(() {
      _fabDragOffset = Offset(
        (_fabDragOffset.dx + details.delta.dx).clamp(maxDx, edge),
        (_fabDragOffset.dy + details.delta.dy).clamp(maxDy, edge),
      );
    });
  }

  Widget _buildContent() {
    final tool = _navigation.tool;
    if (tool != null) {
      return switch (tool) {
        HomeToolSection.tasks => const TaskToolScreen(),
        HomeToolSection.habits => const HabitToolScreen(),
        HomeToolSection.quadrant => const QuadrantScreen(),
        HomeToolSection.calendar => const CalendarScreen(),
        HomeToolSection.lists => const ListManageScreen(),
        HomeToolSection.observationTags => const SystemTagScreen(),
        HomeToolSection.stats => const StatsScreen(),
        HomeToolSection.weeklyReview => const WeeklyReviewScreen(),
        HomeToolSection.timeDistribution => const TimeDistributionScreen(),
      };
    }
    return switch (_navigation.primary) {
      HomePrimarySection.today => DashboardBody(
          tasks: _tasks,
          habits: _habits,
          refreshTick: _dashboardRefreshTick,
          onTaskTap: _openTask,
          onTaskToggle: _toggleTask,
          onHabitToggle: _toggleHabit,
          onHabitLongPress: _openDetailedHabitCheckin,
          onViewAllTasks: () => _openTool(HomeToolSection.tasks),
          onViewAllHabits: () => _openTool(HomeToolSection.habits),
          onQuickAdd: _quickAdd,
          onWriteObservation: _writeObservation,
          onStartFocus: _startFocus,
          onRefresh: _reload,
        ),
      HomePrimarySection.review => const TodayReviewScreen(),
    };
  }

  Widget _navigationPanel({bool closeDrawer = true}) {
    void selectPrimary(HomePrimarySection section) {
      if (closeDrawer) Navigator.pop(context);
      _openPrimary(section);
    }

    void selectTool(HomeToolSection tool) {
      if (closeDrawer) Navigator.pop(context);
      _openTool(tool);
    }

    void openPage(Widget page) {
      if (closeDrawer) Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    final theme = Theme.of(context);
    final showPanelBrand = closeDrawer || kIsWeb || !Platform.isWindows;
    return SafeArea(
      child: Column(
        children: [
          if (showPanelBrand)
            Padding(
              padding: EdgeInsets.fromLTRB(18, closeDrawer ? 6 : 14, 10, 6),
              child: Row(
                children: [
                  const SlowlightLogo(size: 28),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '所行映我 · Slowlight',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (closeDrawer)
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: '关闭',
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              showPanelBrand ? 0 : 10,
              10,
              10,
            ),
            child: _searchEntry(
              showShortcut: !closeDrawer,
              onTap: () => openPage(const SearchScreen()),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _navItem(
                  icon: LucideIcons.sun,
                  label: '今天',
                  selected: _navigation.isToday,
                  onTap: () => selectPrimary(HomePrimarySection.today),
                ),
                _navItem(
                  icon: LucideIcons.bookOpen,
                  label: '回顾',
                  selected: _isReviewContext,
                  onTap: () => selectPrimary(HomePrimarySection.review),
                ),
                _navSectionLabel('记录工具'),
                _navItem(
                  icon: LucideIcons.listTodo,
                  label: '任务',
                  selected: _navigation.tool == HomeToolSection.tasks,
                  onTap: () => selectTool(HomeToolSection.tasks),
                ),
                _navItem(
                  icon: LucideIcons.layoutGrid,
                  label: '四象限',
                  selected: _navigation.tool == HomeToolSection.quadrant,
                  onTap: () => selectTool(HomeToolSection.quadrant),
                ),
                _navItem(
                  icon: LucideIcons.repeat2,
                  label: '习惯',
                  selected: _navigation.tool == HomeToolSection.habits,
                  onTap: () => selectTool(HomeToolSection.habits),
                ),
                _navItem(
                  icon: LucideIcons.timer,
                  label: '专注',
                  onTap: () => openPage(const PomodoroScreen()),
                ),
                if (!kIsWeb &&
                    (Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS))
                  _navItem(
                    icon: LucideIcons.coffee,
                    label: '休息提醒',
                    onTap: () => openPage(const ReminderScreen()),
                  ),
                _navItem(
                  icon: LucideIcons.calendarDays,
                  label: '日历',
                  selected: _navigation.tool == HomeToolSection.calendar,
                  onTap: () => selectTool(HomeToolSection.calendar),
                ),
                const SizedBox(height: 6),
                _organizeToolsToggle(),
                if (_organizeToolsExpanded) ...[
                  _navItem(
                    icon: LucideIcons.folder,
                    label: '清单',
                    selected: _navigation.tool == HomeToolSection.lists,
                    onTap: () => selectTool(HomeToolSection.lists),
                  ),
                  _navItem(
                    icon: LucideIcons.tag,
                    label: '观察标签',
                    selected:
                        _navigation.tool == HomeToolSection.observationTags,
                    onTap: () => selectTool(HomeToolSection.observationTags),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: SyncStatusBadge(showHealthy: true, showLocal: true),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _navItem(
                        icon: LucideIcons.settings,
                        label: '设置',
                        onTap: () => openPage(const SettingsScreen()),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: '关于',
                        icon: const Icon(LucideIcons.circleHelp, size: 18),
                        onPressed: () => openPage(const AboutScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _organizeToolsToggle() {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: () => setState(
        () => _organizeToolsExpanded = !_organizeToolsExpanded,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '组织工具',
                  style: TextStyle(
                    fontSize: AppTheme.textXs,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                _organizeToolsExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchEntry({
    required bool showShortcut,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.search,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '搜索',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (showShortcut)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Text(
                    'Ctrl K',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 5),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTheme.textXs,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    final accent = activePalette.accent;
    return ListTile(
      minTileHeight: 44,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(icon, size: 18),
      title: Text(label, style: const TextStyle(fontSize: AppTheme.textSm)),
      selected: selected,
      selectedColor: accent,
      selectedTileColor: accent.withValues(alpha: .12),
      iconColor: theme.colorScheme.onSurfaceVariant,
      textColor: theme.colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      onTap: onTap,
    );
  }
}
