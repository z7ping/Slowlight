import 'dart:async';
import 'dart:math' as math;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../main.dart' show authStateNotifier;
import '../models/habit.dart';
import '../models/reflection_entry.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../navigation/home_navigation_state.dart';
import '../repositories/habit_repository.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/app_error_logger.dart';
import '../services/data_mode_manager.dart';
import '../services/data_service.dart';
import '../services/notification_service.dart';
import '../services/tray_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../ui/widgets/slowlight_logo.dart';
import '../widgets/dashboard/dashboard.dart';
import '../widgets/habit_checkin_flow.dart';
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
import 'task_tool_screen.dart';
import 'time_distribution_screen.dart';
import 'today_review_screen.dart';
import 'weekly_review_screen.dart';

/// 侧边栏只展示本机缓存的账号信息，不进行云端会话判定。
/// 读取侧栏、打开抽屉或进入账号页都不能触发 AuthGate 的登录重置。
/// 服务端资料、密码状态和 GitHub 绑定失败由账号页各自显示未知状态。
@visibleForTesting
Future<Map<String, String>> readCachedSidebarAccountSummary() async {
  if (DataModeManager().isLocal) {
    return {'name': '本地使用', 'status': '记录保存在本机'};
  }
  // Only read credentials; isLoggedIn() may refresh the access token and is
  // deliberately reserved for AuthGate / explicit mode switching.
  final token = await AuthService.getToken(source: 'sidebar');
  if (token == null || token.startsWith('local:')) {
    return {'name': '账号状态待确认', 'status': '请进入账号页检查'};
  }
  final User? user = await AuthService.getUser();
  if (user == null) {
    return {'name': '账号信息待确认', 'status': '请进入账号页检查'};
  }
  final method = await AuthService.getLastLoginMethod();
  return {
    'name': user.nickname.trim().isNotEmpty ? user.nickname.trim() : user.username,
    'status': method == 'github'
        ? '最近通过 GitHub 登录 · 云端'
        : '云端账号 · 本机资料',
  };
}

/// Slowlight 主壳层。桌面严格使用高保真原型的 232px 左侧栏；
/// 主内容页自己承担页面头部，不再叠加一层通用顶栏。
class FocusHomeScreen extends StatefulWidget {
  const FocusHomeScreen({super.key});

  @override
  State<FocusHomeScreen> createState() => _FocusHomeScreenState();
}

class _FocusHomeScreenState extends State<FocusHomeScreen>
    with WidgetsBindingObserver {
  HomeNavigationState _navigation = const HomeNavigationState.today();
  List<TodoList> _lists = const [];
  List<Task> _tasks = const [];
  List<Habit> _habits = const [];
  final Set<String> _coreLoading = {'清单', '任务', '习惯'};
  final Set<String> _coreErrors = {};
  // Once a source has loaded, retain its rows during silent refresh.
  final Set<String> _coreLoaded = {};
  final Set<int> _pendingHabitActions = {};
  final Set<int> _pendingTaskActions = {};
  int _loadVersion = 0;
  GlobalKey _workspaceKey = GlobalKey(debugLabel: '回顾工作区');
  GlobalKey<TaskToolScreenState> _taskToolKey = GlobalKey<TaskToolScreenState>();
  final GlobalKey<HabitToolScreenState> _habitToolKey = GlobalKey<HabitToolScreenState>();
  int _habitToolFilter = 0;
  final ValueNotifier<int> _listCreateRequest = ValueNotifier<int>(0);
  final ValueNotifier<int> _tagCreateRequest = ValueNotifier<int>(0);
  bool _navigating = false;
  bool _reviewOpened = false;
  bool _quadrantOpened = false;
  bool _habitsOpened = false;
  bool _calendarOpened = false;
  int _quadrantActivation = 0;
  int _calendarActivation = 0;
  HomeNavigationState _mobileReturnTab = const HomeNavigationState.today();
  bool _organizeToolsExpanded = false;
  bool _openHabitEditorOnEnter = false;
  int? _searchFocusHabitId;
  ReflectionEntry? _searchFocusObservation;
  int _searchFocusObservationRequest = 0;
  late Future<Map<String, String>> _accountFuture;
  bool _shortcutModifierPressed = false;
  int _dashboardRefreshTick = 0;
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'Slowlight global shortcuts',
  );
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();
  final CalendarHeaderController _calendarHeaderController =
      CalendarHeaderController();
  // FAB 的实际布局坐标（相对于手机内容区域）；为空时停靠右下角。
  Offset? _fabPosition;
  bool _fabAutoHidden = false;
  DateTime? _lastAndroidBackAt;
  Object? _exitNoticeId;
  DateTime _knownToday = DateUtils.dateOnly(DateTime.now());
  Timer? _nextDayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextDayRefresh();
    _accountFuture = _loadAccountDisplay();
    authStateNotifier.addListener(_resetWorkspace);
    DataModeManager().addListener(_resetWorkspace);
    _reload();
    NotificationService().checkAndScheduleReminders();
    TrayService().loadAfterLogin();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingTask());
  }

  @override
  void dispose() {
    _nextDayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    authStateNotifier.removeListener(_resetWorkspace);
    DataModeManager().removeListener(_resetWorkspace);
    _shortcutFocusNode.dispose();
    _calendarHeaderController.dispose();
    _listCreateRequest.dispose();
    _tagCreateRequest.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshIfNewDay();
    _scheduleNextDayRefresh();
  }

  void _refreshIfNewDay() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(_knownToday, today)) return;
    _knownToday = today;
    // Day-scoped tasks, habit check-ins, the Today date and timeline all
    // need fresh facts after midnight, even without user navigation.
    _reload();
  }

  void _scheduleNextDayRefresh() {
    _nextDayTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _nextDayTimer = Timer(
      nextDay.difference(now) + const Duration(milliseconds: 100),
      () {
        if (!mounted) return;
        _refreshIfNewDay();
        _scheduleNextDayRefresh();
      },
    );
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
    _knownToday = DateUtils.dateOnly(DateTime.now());
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        for (final name in ['清单', '任务', '习惯']) {
          if (_coreLoaded.contains(name)) {
            _coreLoading.remove(name);
          } else {
            _coreLoading.add(name);
          }
        }
        _coreErrors.clear();
      });
    }
    Future<void> load<T>(
        String name, Future<T> Function() read, void Function(T) apply) async {
      try {
        final value = await read();
        if (!mounted || version != _loadVersion) return;
        setState(() {
          apply(value);
          _coreLoaded.add(name);
          _coreErrors.remove(name);
        });
      } catch (_) {
        if (!mounted || version != _loadVersion) return;
        setState(() => _coreErrors.add(name));
      } finally {
        if (mounted && version == _loadVersion) {
          setState(() => _coreLoading.remove(name));
        }
      }
    }

    await Future.wait([
      load('清单', DataService().getLists, (value) => _lists = value),
      load('任务', DataService().getTodayTasks, (value) => _tasks = value),
      load('习惯', HabitRepository().getAll, (value) => _habits = value),
    ]);
    if (mounted && version == _loadVersion)
      setState(() => _dashboardRefreshTick++);
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

  Future<void> _openPrimary(HomePrimarySection section) async {
    await _navigate(_navigation.openPrimary(section));
    if (!mounted || _navigation.tool != null || _navigation.primary != section) {
      return;
    }
    // A blocked transition must not discard the selected search observation.
    if (_searchFocusObservation != null) {
      setState(() => _searchFocusObservation = null);
    }
  }

  Future<void> _navigate(HomeNavigationState next) async {
    if (_navigating) return;
    final previous = _navigation;
    if (previous.primary == next.primary && previous.tool == next.tool) {
      _dismissExitPrompt();
      if (next.isToday) _reload();
      return;
    }
    _navigating = true;
    try {
      if (previous.tool == HomeToolSection.tasks &&
          next.tool != HomeToolSection.tasks &&
          !await (_taskToolKey.currentState?.confirmLeaveTool() ??
              Future<bool>.value(true))) return;
      if (!mounted) return;
      _dismissExitPrompt();
      setState(() {
        _navigation = next;
        if (next.showsMobileBottomBar) _mobileReturnTab = next;
        if (next.isReview) _reviewOpened = true;
        if (next.tool == HomeToolSection.quadrant) {
          _quadrantOpened = true;
          _quadrantActivation++;
        }
        if (next.tool == HomeToolSection.habits) _habitsOpened = true;
        if (next.tool == HomeToolSection.calendar) {
          _calendarOpened = true;
          _calendarActivation++;
        }
        if (next.isToday) _fabAutoHidden = false;
        _organizeToolsExpanded =
            next.tool != null && _isOrganizeTool(next.tool!);
      });
      if (next.isToday && !previous.isToday) _reload();
    } finally {
      _navigating = false;
    }
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

  Future<void> _openTool(HomeToolSection tool) =>
      _navigate(_navigation.openTool(tool));

  /// KPI destinations use the existing shell navigation (and its draft guard).
  void _navigateFromStats(StatsDestination destination) {
    switch (destination) {
      case StatsDestination.tasks:
        unawaited(_openTool(HomeToolSection.tasks));
        break;
      case StatsDestination.habits:
        unawaited(_openTool(HomeToolSection.habits));
        break;
      case StatsDestination.focus:
        unawaited(_startFocus());
        break;
      case StatsDestination.review:
        unawaited(_openPrimary(HomePrimarySection.review));
        break;
      case StatsDestination.timeDistribution:
        unawaited(_openTool(HomeToolSection.timeDistribution));
        break;
    }
  }

  Future<void> _navigateFromTimeDistribution(
      TimeDistributionDestination destination) async {
    switch (destination) {
      case TimeDistributionDestination.focus:
        await _startFocus();
        break;
      case TimeDistributionDestination.tags:
        await _openTool(HomeToolSection.observationTags);
        break;
    }
  }

  Future<void> _createHabitFromToday() async {
    if (_navigating) return;
    // A pinned HabitToolScreen may already be mounted offstage. A createOnOpen
    // flag is only consumed by initState; call the existing editor instead.
    final alreadyMounted = _habitToolKey.currentState != null;
    setState(() => _openHabitEditorOnEnter = !alreadyMounted);
    try {
      await _openTool(HomeToolSection.habits);
      if (alreadyMounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _navigation.tool == HomeToolSection.habits) {
            _habitToolKey.currentState?.createHabit();
          }
        });
      }
    } finally {
      // Only the first build of the tool screen receives the create intent.
      // Returning to the same tool later must not reopen the editor.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _openHabitEditorOnEnter = false);
      });
    }
  }

  Future<void> _closeTool() => _navigate(
        !ResponsiveLayout.isDesktopOrWider(context) &&
                !_navigation.showsMobileBottomBar
            ? _mobileReturnTab
            : _navigation.closeTool(),
      );

  void _openMobileTools() {
    // 工具菜单改为左侧滑出抽屉（替代自下而上的全屏面板）
    _mobileScaffoldKey.currentState?.openDrawer();
  }

  void _dismissExitPrompt() {
    _lastAndroidBackAt = null;
    final id = _exitNoticeId;
    _exitNoticeId = null;
    if (mounted && id != null) {
      // Do not clear business notices such as a task-completion Undo action.
      unawaited(FxNotice.dismiss(context, id));
    }
  }

  void _handleAndroidBack(bool didPop) {
    if (didPop) return;

    final scaffold = _mobileScaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      scaffold?.closeDrawer();
      return;
    }
    if (_navigation.isTool && !_navigation.showsMobileBottomBar) {
      _closeTool();
      return;
    }

    final now = DateTime.now();
    final lastBackAt = _lastAndroidBackAt;
    if (lastBackAt == null ||
        now.difference(lastBackAt) > const Duration(seconds: 2)) {
      _dismissExitPrompt();
      _lastAndroidBackAt = now;
      _exitNoticeId = FxNotice.showContent(
        context,
        const Text('再按一次退出 Slowlight'),
        duration: const Duration(seconds: 2),
      );
      return;
    }

    _dismissExitPrompt();
    SystemNavigator.pop();
  }

  Widget _androidBackScope(Widget child) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleAndroidBack(didPop),
      child: child,
    );
  }

  Future<void> _toggleTask(Task task) async {
    if (!_pendingTaskActions.add(task.id)) return;
    final wasCompleted = task.isCompleted;
    try {
      if (wasCompleted) {
        await DataService().uncompleteTask(task.id, null);
      } else {
        await DataService().completeTask(task.id, null);
      }
      await _reload();
      if (!mounted) return;
      FxNotice.showContent(
        context,
        Text(wasCompleted ? '已恢复待办' : '任务已完成'),
        variant: FxNoticeVariant.success,
        duration: wasCompleted || task.isRepeat
            ? const Duration(milliseconds: 2500)
            : const Duration(seconds: 8),
        placement: wasCompleted || task.isRepeat
            ? FxNoticePlacement.top
            : FxNoticePlacement.undo,
        // 完成重复任务可能已生成下一周期，不能用简单 toggle 伪装撤销。
        action: wasCompleted || task.isRepeat
            ? null
            : FxNoticeAction(
                label: '撤销',
                onPressed: () => _undoTaskCompletion(task.id),
              ),
      );
    } catch (_) {
      _message('任务操作结果未确认，请核对任务状态');
    } finally {
      _pendingTaskActions.remove(task.id);
    }
  }

  Future<void> _undoTaskCompletion(int taskId) async {
    if (!_pendingTaskActions.add(taskId)) return;
    try {
      await DataService().uncompleteTask(taskId, null);
      await _reload();
      _message('已恢复待办');
    } catch (_) {
      _message('撤销结果未确认，请查看任务状态');
    } finally {
      _pendingTaskActions.remove(taskId);
    }
  }

  Future<void> _toggleHabit(Habit habit) =>
      _runHabitAction(habit, detailed: false);

  Future<void> _openDetailedHabitCheckin(Habit habit) =>
      _runHabitAction(habit, detailed: true);

  Future<void> _runHabitAction(Habit habit, {required bool detailed}) async {
    if (!_pendingHabitActions.add(habit.id)) return;
    try {
      if (habit.checkedToday && !habit.allowMultiplePerDay) {
        if (detailed) {
          _message('今天已记录；请在习惯详情中查看');
          return;
        }
        final confirmed = await FxDialog.confirm(
            context: context,
            title: '取消打卡',
            content: '确定取消今天「${habit.name}」的打卡？连续天数将重新计算。',
            confirmText: '取消打卡');
        if (confirmed != true) return;
        await HabitRepository().uncheckIn(habit.id);
        _message('已取消「${habit.name}」今天的记录');
      } else {
        final saved = await recordHabit(context,
            habit: habit, detailed: detailed, submit: (value) async {
          await HabitRepository().checkIn(
            habit.id,
            durationMin: value['duration_min'] as int?,
            countValue: value['count_value'] as int?,
            occurredAt: value['occurred_at'] as String?,
            period: value['period'] as String?,
            note: value['note'] as String? ?? '',
            clientKey: value['client_key'] as String?,
          );
        });
        if (!saved) return;
        _message('已记录「${habit.name}」');
      }
      await _reload();
    } catch (error) {
      _message('操作结果未确认，请重新加载核对：$error');
    } finally {
      _pendingHabitActions.remove(habit.id);
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
    TaskDetailSheet.showCreate(
      context,
      lists: _lists.isEmpty ? null : _lists,
      onChanged: _reload,
    );
  }

  Future<void> _openSearchReflection(ReflectionEntry entry) async {
    await _navigate(_navigation.openPrimary(HomePrimarySection.review));
    if (!mounted || !_navigation.isReview) return;
    setState(() {
      // The prototype pins observations only. Replies open the review page.
      _searchFocusObservation =
          entry.entryType == 'observation' ? entry : null;
      _searchFocusObservationRequest++;
    });
  }

  Future<void> _openSearch() {
    _dismissExitPrompt();
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (searchContext) => SearchScreen(
          onOpenHabit: (habit) {
            Navigator.of(searchContext).pop();
            if (!mounted) return;
            setState(() => _searchFocusHabitId = habit.id);
            unawaited(_openTool(HomeToolSection.habits));
          },
          onOpenReflection: (entry) {
            Navigator.of(searchContext).pop();
            unawaited(_openSearchReflection(entry));
          },
        ),
      ),
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
    FxNotice.showContent(context, Text(text));
  }

  @override
  Widget build(BuildContext context) {
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    final content = _buildWorkspace();

    if (desktop) {
      return _shortcutRegion(
        Scaffold(
          body: Row(
            children: [
              SizedBox(width: 232, child: _navigationPanel(closeDrawer: false)),
              FxSeparator.vertical(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return _shortcutRegion(
      _androidBackScope(
        Scaffold(
          key: _mobileScaffoldKey,
          drawerEnableOpenDragGesture: true,
          // Android 全面屏返回手势会占用最外侧约 24dp；扩大应用内边缘区，
          // 让用户可以从系统手势区内侧稳定右滑打开抽屉。
          drawerEdgeDragWidth: 72,
          onDrawerChanged: (isOpened) {
            if (isOpened) {
              _dismissExitPrompt();
              _refreshAccount();
            }
          },
          drawer: Drawer(
            // The single Android prototype uses 78% of the viewport.
            width: MediaQuery.sizeOf(context).width * 0.78,
            shape: const RoundedRectangleBorder(),
            backgroundColor: theme.colorScheme.surface,
            child: SafeArea(child: _navigationPanel(closeDrawer: true)),
          ),
          appBar: AppBar(
            // 主导航靠表面与正文间距分层，不绘制底线或滚动阴影。
            scrolledUnderElevation: 0,
            toolbarHeight: 48,
            titleSpacing: 8,
            title: _navigation.tool == HomeToolSection.calendar
                ? CalendarMonthTitle(controller: _calendarHeaderController)
                : Text(
                    _navigation.title,
                    style: SlowlightTypography.componentPageTitle(context),
                  ),
            leading: !_navigation.showsMobileBottomBar
                ? FxIconButton(
                    icon: LucideIcons.chevronLeft,
                    iconSize: 20,
                    tooltip: '返回',
                    onPressed: _closeTool,
                  )
                : FxIconButton(
                    icon: LucideIcons.menu,
                    iconSize: 20,
                    tooltip: '工具',
                    onPressed: _openMobileTools,
                  ),
            actions: [
              if (_navigation.tool == HomeToolSection.calendar)
                CalendarHeaderActions(controller: _calendarHeaderController),
              if (_navigation.tool == HomeToolSection.lists ||
                  _navigation.tool == HomeToolSection.observationTags)
                FxButton(
                  label: '新建',
                  icon: LucideIcons.plus,
                  size: FxButtonSize.sm,
                  onPressed: () {
                    if (_navigation.tool == HomeToolSection.lists) {
                      _listCreateRequest.value++;
                    } else {
                      _tagCreateRequest.value++;
                    }
                  },
                ),
              if (_navigation.tool == HomeToolSection.habits)
                FxMenu<int>(
                  key: const ValueKey('habits.filter.menu'),
                  tooltip: '筛选习惯',
                  onSelected: (value) {
                    setState(() => _habitToolFilter = value);
                    _habitToolKey.currentState?.setFilter(value);
                  },
                  itemBuilder: (_) => [
                    FxMenuItem(value: 0, child: Text(_habitToolFilter == 0 ? '✓ 全部' : '全部')),
                    FxMenuItem(value: 1, child: Text(_habitToolFilter == 1 ? '✓ 今日未记录' : '今日未记录')),
                    FxMenuItem(value: 2, child: Text(_habitToolFilter == 2 ? '✓ 今日有记录' : '今日有记录')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(LucideIcons.listFilter,
                        size: SlowlightIconSize.md,
                        color: _habitToolFilter == 0
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.primary),
                  ),
                ),
              if (_navigation.isToday) ...[
                FxIconButton(
                  icon: LucideIcons.pencil,
                  iconSize: 18,
                  tooltip: '记录观察',
                  onPressed: _writeObservation,
                ),
              ],
              const SizedBox(width: 4),
            ],
          ),
          body: _mobileTodayBody(content),
          bottomNavigationBar:
              _navigation.showsMobileBottomBar ? _mobileBottomNavigation() : null,
        ),
      ),
    );
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
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('home.bottom-nav'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            _mobileBottomNavigationItem(
              itemKey: const ValueKey('home.bottom-nav.today'),
              icon: LucideIcons.sun,
              label: '今天',
              selected: _navigation.isToday,
              onTap: () => _openPrimary(HomePrimarySection.today),
            ),
            _mobileBottomNavigationItem(
              itemKey: const ValueKey('home.bottom-nav.quadrant'),
              icon: LucideIcons.layoutGrid,
              label: '四象限',
              selected: _navigation.tool == HomeToolSection.quadrant,
              onTap: () => _openTool(HomeToolSection.quadrant),
            ),
            _mobileBottomNavigationItem(
              itemKey: const ValueKey('home.bottom-nav.habits'),
              icon: LucideIcons.repeat2,
              label: '习惯',
              selected: _navigation.tool == HomeToolSection.habits,
              onTap: () => _openTool(HomeToolSection.habits),
            ),
            _mobileBottomNavigationItem(
              itemKey: const ValueKey('home.bottom-nav.calendar'),
              icon: LucideIcons.calendarDays,
              label: '日历',
              selected: _navigation.tool == HomeToolSection.calendar,
              onTap: () => _openTool(HomeToolSection.calendar),
            ),
            _mobileBottomNavigationItem(
              itemKey: const ValueKey('home.bottom-nav.review'),
              icon: LucideIcons.bookOpen,
              label: '回顾',
              selected: _navigation.isReview,
              onTap: () => _openPrimary(HomePrimarySection.review),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileBottomNavigationItem({
    required Key itemKey,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final color =
        selected ? activePalette.accent : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        child: FxInkWell(
          key: itemKey,
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? activePalette.accent.withValues(alpha: .12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(SlowlightRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 将悬浮按钮真正布局在移动后的坐标，而不是只平移其绘制位置。
  ///
  /// Scaffold.floatingActionButton + Transform.translate 只能改变绘制位置；
  /// 拖动到原布局区域外后，祖先的命中测试区域仍停留在原位置，导致无法点击。
  /// 把按钮放在 body 的 Stack 中，Positioned 同时更新绘制与命中测试位置。
  Widget _mobileTodayBody(Widget content) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const fabSize = 48.0;
        const edge = 16.0;
        final maxLeft = math.max(0.0, constraints.maxWidth - fabSize);
        final maxTop = math.max(0.0, constraints.maxHeight - fabSize);
        final initial = _fabPosition ??
            Offset(
              math.max(0.0, maxLeft - edge),
              math.max(0.0, maxTop - edge),
            );
        final left = initial.dx.clamp(0.0, maxLeft).toDouble();
        final top = initial.dy.clamp(0.0, maxTop).toDouble();

        return Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  // Floating quick-add must not cover the buttons beneath it
                  // while the user is moving through the Today workspace.
                  final direction = notification.direction;
                  if (!_navigation.isToday ||
                      direction == ScrollDirection.idle) return false;
                  final hide = direction == ScrollDirection.reverse;
                  if (_fabAutoHidden != hide && mounted) {
                    setState(() => _fabAutoHidden = hide);
                  }
                  return false;
                },
                child: content,
              ),
            ),
            if (_navigation.tool == HomeToolSection.habits)
              Positioned(
                right: 16,
                bottom: 16,
                child: _mobileQuickAddButton(
                  tooltip: '添加习惯',
                  onTap: () => _habitToolKey.currentState?.createHabit(),
                ),
              ),
            if (_navigation.isToday)
              Positioned(
                left: left,
                top: top,
                child: IgnorePointer(
                  key: const ValueKey('today.fab.pointer'),
                  ignoring: _fabAutoHidden,
                  child: AnimatedSlide(
                    offset: _fabAutoHidden
                        ? const Offset(0, 0.25)
                        : Offset.zero,
                    duration: MediaQuery.of(context).disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _fabAutoHidden ? 0 : 1,
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child: _mobileQuickAddButton(
                      onPanUpdate: (details) {
                        setState(() {
                          // A previous wider viewport can leave the stored
                          // position outside the current layout. Clamp it
                          // before applying the next drag delta, otherwise
                          // the button appears stuck at the narrow edge.
                          final stored = _fabPosition ?? Offset(left, top);
                          final current = Offset(
                            stored.dx.clamp(0.0, maxLeft).toDouble(),
                            stored.dy.clamp(0.0, maxTop).toDouble(),
                          );
                          _fabPosition = Offset(
                            (current.dx + details.delta.dx)
                                .clamp(0.0, maxLeft)
                                .toDouble(),
                            (current.dy + details.delta.dy)
                                .clamp(0.0, maxTop)
                                .toDouble(),
                          );
                        });
                      },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _mobileQuickAddButton({
    GestureDragUpdateCallback? onPanUpdate,
    VoidCallback? onTap,
    String tooltip = '快速添加任务（按住可拖动）',
  }) {
    return GestureDetector(
      onPanUpdate: onPanUpdate,
      child: FxTooltip(
        message: tooltip,
        child: Material(
          color: Theme.of(context).colorScheme.onSurface,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: .14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlowlightRadius.xl),
          ),
          clipBehavior: Clip.antiAlias,
          child: FxInkWell(
            onTap: onTap ?? _quickAdd,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                LucideIcons.plus,
                color: Theme.of(context).colorScheme.surface,
                size: SlowlightIconSize.xl,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspace() {
    final tool = _navigation.tool;
    final showingReview = tool == null &&
        _navigation.primary == HomePrimarySection.review;
    final quadrant = tool == HomeToolSection.quadrant;
    final habits = tool == HomeToolSection.habits;
    final calendar = tool == HomeToolSection.calendar;
    final otherTool = tool != null && !quadrant && !habits && !calendar;
    // Keep the five pinned destinations mounted while moving between tabs.
    return IndexedStack(
      key: _workspaceKey,
      index: quadrant ? 2 : habits ? 3 : calendar ? 4 : otherTool ? 5 : showingReview ? 1 : 0,
      children: [
        _buildTodayDashboard(),
        _reviewOpened
            ? TodayReviewScreen(
                focusObservation: _searchFocusObservation,
                focusRequestId: _searchFocusObservationRequest,
                onStatsNavigate: _navigateFromStats,
                onTimeDistributionNavigate: _navigateFromTimeDistribution,
              )
            : const SizedBox.shrink(),
        _quadrantOpened
            ? QuadrantScreen(refreshTick: _quadrantActivation)
            : const SizedBox.shrink(),
        _habitsOpened
            ? _buildToolContent(HomeToolSection.habits)
            : const SizedBox.shrink(),
        _calendarOpened ? _calendarContent() : const SizedBox.shrink(),
        otherTool ? _buildToolContent(tool!) : const SizedBox.shrink(),
      ],
    );
  }

  // Keep the same Today element mounted across Today / Review tab changes.
  // Recreating DashboardBody would restart its loaders and reset expansion state.
  Widget _buildTodayDashboard() => DashboardBody(
    tasks: _tasks,
    tasksLoading: _coreLoading.contains('任务'),
    habitsLoading: _coreLoading.contains('习惯'),
    tasksError: _coreErrors.contains('任务'),
    habitsError: _coreErrors.contains('习惯'),
    listsError: _coreErrors.contains('清单'),
    habits: _habits,
    refreshTick: _dashboardRefreshTick,
    onTaskTap: _openTask,
    onTaskToggle: _toggleTask,
    onTaskSwipeComplete: _toggleTask,
    onHabitToggle: _toggleHabit,
    onHabitLongPress: _openDetailedHabitCheckin,
    onViewAllTasks: () => _openTool(HomeToolSection.tasks),
    onViewAllHabits: () => _openTool(HomeToolSection.habits),
    onCreateHabit: _createHabitFromToday,
    onViewReview: () => _openPrimary(HomePrimarySection.review),
    onQuickAdd: _quickAdd,
    onWriteObservation: _writeObservation,
    onStartFocus: _startFocus,
    onRefresh: _reload,
  );

  Widget _calendarContent() => CalendarScreen(
        headerController: _calendarHeaderController,
        headerInAppBar: !ResponsiveLayout.isDesktopOrWider(context),
        refreshTick: _calendarActivation,
      );

  Widget _buildToolContent(HomeToolSection tool) => switch (tool) {
    HomeToolSection.tasks => TaskToolScreen(key: _taskToolKey),
    HomeToolSection.habits =>
      HabitToolScreen(
        key: _habitToolKey,
        initialFilter: _habitToolFilter,
        titleProvidedByShell: true,
        createOnOpen: _openHabitEditorOnEnter,
        focusHabitId: _searchFocusHabitId,
      ),
    HomeToolSection.quadrant => const QuadrantScreen(),
    HomeToolSection.calendar => _calendarContent(),
    HomeToolSection.lists => ListManageScreen(
        createRequest: ResponsiveLayout.isDesktopOrWider(context)
            ? null : _listCreateRequest,
      ),
    HomeToolSection.observationTags => SystemTagScreen(
        createRequest: ResponsiveLayout.isDesktopOrWider(context)
            ? null : _tagCreateRequest,
      ),
    HomeToolSection.stats => StatsScreen(onNavigate: _navigateFromStats),
    HomeToolSection.weeklyReview => const WeeklyReviewScreen(),
    HomeToolSection.timeDistribution => TimeDistributionScreen(
      titleProvidedByShell: !ResponsiveLayout.isDesktopOrWider(context),
      onNavigate: _navigateFromTimeDistribution,
    ),
  };

  Future<Map<String, String>> _loadAccountDisplay() =>
      readCachedSidebarAccountSummary();

  void _refreshAccount() {
    if (mounted) setState(() { _accountFuture = _loadAccountDisplay(); });
  }

  void _resetWorkspace() {
    if (!mounted) return;
    setState(() {
      _accountFuture = _loadAccountDisplay();
      _workspaceKey = GlobalKey(debugLabel: '回顾工作区');
      _taskToolKey = GlobalKey<TaskToolScreenState>();
      _reviewOpened = _navigation.isReview;
      _quadrantOpened = _navigation.tool == HomeToolSection.quadrant;
      _habitsOpened = _navigation.tool == HomeToolSection.habits;
      _calendarOpened = _navigation.tool == HomeToolSection.calendar;
      _quadrantActivation = 0;
      _calendarActivation = 0;
      _mobileReturnTab = _navigation.showsMobileBottomBar
          ? _navigation
          : HomeNavigationState(primary: _navigation.primary);
      _searchFocusObservation = null;
      _searchFocusObservationRequest = 0;
      _lists = const [];
      _tasks = const [];
      _habits = const [];
      _coreLoaded.clear();
      _coreLoading.addAll(['清单', '任务', '习惯']);
      _coreErrors.clear();
    });
    _reload();
  }

  Widget _accountEntry(void Function(Widget) openPage) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, String>>(
      future: _accountFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ??
            (snapshot.hasError ? {'name': '账号状态暂不可用', 'status': '点击查看'} : null);
        return FxInkWell(
          key: const ValueKey('home.account_entry'),
          onTap: () {
            unawaited(AppErrorLogger.instance.write(
              source: 'AuthNavigation',
              error: 'account_entry.opened',
            ));
            openPage(const SettingsScreen(initialSection: 'account'));
          },
          borderRadius: BorderRadius.circular(SlowlightRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  Icon(LucideIcons.userRound, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          data?['name'] ?? '读取账号中…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SlowlightTypography.secondary(context)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          data?['status'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SlowlightTypography.caption(context).copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronRight,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        );
      },
    );
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
      Navigator.push(context, MaterialPageRoute(builder: (_) => page))
          .then((_) => _refreshAccount());
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
                    FxIconButton(
                      icon: LucideIcons.x,
                      iconSize: 20,
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(10, showPanelBrand ? 0 : 10, 10, 10),
            child: _searchEntry(
              showShortcut: !closeDrawer,
              onTap: () {
                if (closeDrawer) Navigator.pop(context);
                unawaited(_openSearch());
              },
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
                if (closeDrawer)
                  _navSectionLabel('组织工具')
                else
                  _organizeToolsToggle(),
                // Android shows both entries; Windows retains its toggle.
                if (closeDrawer || _organizeToolsExpanded) ...[
                  _navItem(
                    icon: LucideIcons.folder,
                    label: '清单',
                    selected: _navigation.tool == HomeToolSection.lists,
                    onTap: () => selectTool(HomeToolSection.lists),
                  ),
                  _navItem(
                    icon: LucideIcons.tag,
                    label: closeDrawer ? '标签' : '观察标签',
                    selected:
                        _navigation.tool == HomeToolSection.observationTags,
                    onTap: () => selectTool(HomeToolSection.observationTags),
                  ),
                ],
              ],
            ),
          ),
          FxSeparator.horizontal(
            height: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _accountEntry(openPage),
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
                    FxIconButton(
                      icon: LucideIcons.circleHelp,
                      iconSize: 18,
                      tooltip: '关于',
                      onPressed: () => openPage(const AboutScreen()),
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
    return FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap: () =>
          setState(() => _organizeToolsExpanded = !_organizeToolsExpanded),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '组织工具',
                  style: SlowlightTypography.caption(context).copyWith(
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
      child: FxInkWell(
        borderRadius: BorderRadius.circular(SlowlightRadius.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(SlowlightRadius.md),
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
                  style: SlowlightTypography.secondary(context).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (showShortcut)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(SlowlightRadius.sm),
                  ),
                  child: Text(
                    'Ctrl K',
                    style: SlowlightTypography.caption(context).copyWith(
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
        style: SlowlightTypography.caption(context).copyWith(
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
    return FxListTile(
      minTileHeight: 44,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(icon, size: 18),
      title: Text(label,
          style: SlowlightTypography.secondary(context)),
      selected: selected,
      selectedColor: accent,
      selectedTileColor: accent.withValues(alpha: .12),
      iconColor: theme.colorScheme.onSurfaceVariant,
      textColor: theme.colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SlowlightRadius.md),
      ),
      onTap: onTap,
    );
  }
}
