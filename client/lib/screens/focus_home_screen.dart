import 'dart:math' as math;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../main.dart' show authStateNotifier;
import '../models/habit.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../navigation/home_navigation_state.dart';
import '../repositories/habit_repository.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
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
  final Set<String> _coreLoading = {'清单', '任务', '习惯'};
  final Set<String> _coreErrors = {};
  final Set<int> _pendingHabitActions = {};
  int _loadVersion = 0;
  GlobalKey _workspaceKey = GlobalKey(debugLabel: '回顾工作区');
  bool _reviewOpened = false;
  bool _organizeToolsExpanded = false;
  late Future<Map<String, String>> _accountFuture;
  bool _shortcutModifierPressed = false;
  int _dashboardRefreshTick = 0;
  final FocusNode _shortcutFocusNode = FocusNode(
    debugLabel: 'Slowlight global shortcuts',
  );
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();
  // FAB 的实际布局坐标（相对于手机内容区域）；为空时停靠右下角。
  Offset? _fabPosition;
  DateTime? _lastAndroidBackAt;

  @override
  void initState() {
    super.initState();
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
    authStateNotifier.removeListener(_resetWorkspace);
    DataModeManager().removeListener(_resetWorkspace);
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
    final version = ++_loadVersion;
    if (mounted)
      setState(() {
        _coreLoading.addAll(['清单', '任务', '习惯']);
        _coreErrors.clear();
      });
    Future<void> load<T>(
        String name, Future<T> Function() read, void Function(T) apply) async {
      try {
        final value = await read();
        if (!mounted || version != _loadVersion) return;
        setState(() => apply(value));
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

  void _openPrimary(HomePrimarySection section) {
    setState(() {
      _navigation = _navigation.openPrimary(section);
      if (section == HomePrimarySection.review) _reviewOpened = true;
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

  void _handleAndroidBack(bool didPop) {
    if (didPop) return;

    final scaffold = _mobileScaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      scaffold?.closeDrawer();
      return;
    }
    if (_navigation.isTool) {
      _closeTool();
      return;
    }

    final now = DateTime.now();
    final lastBackAt = _lastAndroidBackAt;
    if (lastBackAt == null ||
        now.difference(lastBackAt) > const Duration(seconds: 2)) {
      _lastAndroidBackAt = now;
      FxNotice.clear(context);
      FxNotice.showContent(
        context,
        Text('再按一次退出 Slowlight'),
        duration: Duration(seconds: 2),
      );
      return;
    }

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
              _lastAndroidBackAt = null;
              _refreshAccount();
            }
          },
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
              style: SlowlightTypography.componentPageTitle(context),
            ),
            leading: _navigation.isTool
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: FxSeparator.horizontal(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          body: _mobileTodayBody(content),
          bottomNavigationBar:
              _navigation.isTool ? null : _mobileBottomNavigation(),
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
      child: FxInkWell(
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
                    fontSize: SlowlightTypography.captionSize,
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
            Positioned.fill(child: content),
            if (_navigation.isToday)
              Positioned(
                left: left,
                top: top,
                child: _mobileQuickAddButton(
                  onPanUpdate: (details) {
                    setState(() {
                      final current = _fabPosition ?? Offset(left, top);
                      _fabPosition = Offset(
                        (current.dx + details.delta.dx)
                            .clamp(0.0, maxLeft)
                            .toDouble(),
                        (current.dy + details.delta.dy).clamp(0.0, maxTop).toDouble(),
                      );
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _mobileQuickAddButton({
    required GestureDragUpdateCallback onPanUpdate,
  }) {
    return GestureDetector(
      onPanUpdate: onPanUpdate,
      child: FxTooltip(
        message: '快速添加任务（按住可拖动）',
        child: Material(
          color: activePalette.accent,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: .18),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: FxInkWell(
            onTap: _quickAdd,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(LucideIcons.plus, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspace() {
    final showingReview = _navigation.tool == null &&
        _navigation.primary == HomePrimarySection.review;
    // 首次进入回顾才加载；离开时保留输入、未知结果和进行中的保存。
    // 账号/数据模式切换会整体换 key，避免跨账号复用草稿。
    return IndexedStack(
      key: _workspaceKey,
      index: showingReview ? 1 : 0,
      children: [
        showingReview ? const SizedBox.shrink() : _buildContent(),
        _reviewOpened ? const TodayReviewScreen() : const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildContent() {
    final tool = _navigation.tool;
    if (tool != null) {
      return switch (tool) {
        HomeToolSection.tasks => const TaskToolScreen(),
        HomeToolSection.habits =>
          const HabitToolScreen(titleProvidedByShell: true),
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
          tasksLoading: _coreLoading.contains('任务'),
          habitsLoading: _coreLoading.contains('习惯'),
          tasksError: _coreErrors.contains('任务'),
          habitsError: _coreErrors.contains('习惯'),
          listsError: _coreErrors.contains('清单'),
          habits: _habits,
          refreshTick: _dashboardRefreshTick,
          onTaskTap: _openTask,
          onTaskToggle: _toggleTask,
          onHabitToggle: _toggleHabit,
          onHabitLongPress: _openDetailedHabitCheckin,
          onViewAllTasks: () => _openTool(HomeToolSection.tasks),
          onViewAllHabits: () => _openTool(HomeToolSection.habits),
          onViewReview: () => _openPrimary(HomePrimarySection.review),
          onQuickAdd: _quickAdd,
          onWriteObservation: _writeObservation,
          onStartFocus: _startFocus,
          onRefresh: _reload,
        ),
      HomePrimarySection.review => const TodayReviewScreen(),
    };
  }

  Future<Map<String, String>> _loadAccountDisplay() async {
    if (DataModeManager().isLocal) {
      return {'name': '本地使用', 'status': '记录保存在本机'};
    }
    if (!await AuthService.isLoggedIn()) {
      return {'name': '未登录', 'status': '点击查看账号'};
    }
    final User? user = await AuthService.getUser();
    // 侧边栏始终优先显示本机已确认的账号信息，不等待网络查询。
    // 最近登录方式并不等于绑定状态，绑定详情只在账号页向服务端确认。
    final method = await AuthService.getLastLoginMethod();
    final status = method == 'github' ? '通过 GitHub 登录 · 云端' : '云端已登录';
    return {
      'name': user?.nickname.isNotEmpty == true
          ? user!.nickname
          : (user?.username ?? '已登录'),
      'status': status,
    };
  }

  void _refreshAccount() {
    if (mounted) setState(() { _accountFuture = _loadAccountDisplay(); });
  }

  void _resetWorkspace() {
    if (!mounted) return;
    setState(() {
      _accountFuture = _loadAccountDisplay();
      _workspaceKey = GlobalKey(debugLabel: '回顾工作区');
      _reviewOpened = _navigation.tool == null &&
          _navigation.primary == HomePrimarySection.review;
      _lists = const [];
      _tasks = const [];
      _habits = const [];
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
          onTap: () =>
              openPage(const SettingsScreen(initialSection: 'account')),
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
                    label: '标签',
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
                  style: TextStyle(
                    fontSize: SlowlightTypography.captionSize,
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
                  style: TextStyle(
                    fontSize: SlowlightTypography.secondarySize,
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
                    style: TextStyle(
                      fontSize: SlowlightTypography.captionSize,
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
          fontSize: SlowlightTypography.captionSize,
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
          style: const TextStyle(fontSize: SlowlightTypography.secondarySize)),
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
