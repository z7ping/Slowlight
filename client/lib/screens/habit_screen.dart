import 'package:flutter/material.dart';
import '../widgets/habit_checkin_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../ui/fx.dart';
import '../models/habit.dart';
import '../services/api_service.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/widgets/fx_input.dart';
import '../ui/widgets/fx_switch.dart';
import '../widgets/habit_heatmap.dart';
import '../utils/color_utils.dart';

class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  List<Habit> _habits = [];
  bool _isLoading = true;
  // 正在动画的习惯 ID
  final Set<int> _animatingIds = {};
  // 内嵌展开状态
  int? _expandedHabitId;
  List<Map<String, dynamic>> _expandedHabitLogs = [];
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    try {
      final data = await ApiService.getHabits();
      setState(() {
        _habits = data.map((json) => Habit.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('加载习惯失败');
    }
  }

  Future<void> _checkIn(Habit habit) async {
    int? durationMin;
    String? period;
    String? note;

    // 仅当习惯启用了打卡弹窗时才弹出日志填写弹窗
    if (habit.showCheckinDialog) {
      final result = await HabitCheckinDialog.show(
        context,
        habit: habit,
      );
      // 用户关闭弹窗（null）则不打卡
      if (result == null) return;
      durationMin = result['duration_min'] as int?;
      period = result['period'] as String?;
      note = result['note'] as String?;
    }

    // 触发动画
    setState(() => _animatingIds.add(habit.id));

    try {
      final result = await ApiService.checkInHabit(habit.id,
          note: note ?? '',
          durationMin: durationMin ?? 0,
          period: period ?? '');
      if (mounted) {
        _showSuccess('打卡成功！🔥 ${result['streak_count']}天连续');
      }
      // 延迟刷新，让动画播放完
      await Future.delayed(const Duration(milliseconds: 600));
      _loadHabits();
    } catch (e) {
      _showError(e.toString().contains('已打卡') ? '今天已打卡' : '打卡失败');
    } finally {
      if (mounted) setState(() => _animatingIds.remove(habit.id));
    }
  }

  Future<void> _createHabit() async {
    final result = await showShadDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _CreateHabitDialog(),
    );

    if (result != null) {
      try {
        await ApiService.createHabit(
          name: result['name'],
          icon: result['icon'],
          color: result['color'],
          frequency: result['frequency'],
          targetDays: result['target_days'] ?? 0,
          systemTagId: result['system_tag_id'],
          preferredPeriod: result['preferred_period'] ?? '',
          durationMin: result['duration_min'] ?? 0,
          generateTask: result['generate_task'] ?? false,
          showCheckinDialog: result['show_checkin_dialog'] ?? false,
          specificTime: result['specific_time'] ?? '',
          reminderAt: result['reminder_at'] ?? {},
        );
        _loadHabits();
      } catch (e) {
        _showError('创建失败');
      }
    }
  }

  Future<void> _backfillCheckIn(Habit habit) async {
    final date = await showFxDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 1)),
      firstDate: habit.createdAt,
      lastDate: DateTime.now(),
      title: '选择要补卡的日期',
    );
    if (date == null) return;

    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    // 弹出日志填写弹窗
    final dialogResult = await HabitCheckinDialog.show(
      context,
      habit: habit,
    );
    if (dialogResult == null) return;

    try {
      final result = await ApiService.checkInHabit(
        habit.id,
        date: dateStr,
        durationMin: dialogResult['duration_min'] as int? ?? 0,
        period: dialogResult['period'] as String? ?? '',
        note: dialogResult['note'] as String? ?? '',
      );
      _showSuccess('补卡成功，已记录 ${result['streak_count']}天连续');
      _loadHabits();
    } catch (e) {
      _showError(e.toString().contains('已打卡') ? '该日期已打卡' : '补卡失败');
    }
  }

  Future<void> _deleteHabit(Habit habit) async {
    final confirm = await FxDialog.confirm(
      context: context,
      title: '确认删除',
      content: '确定删除「${habit.name}」及所有打卡记录？',
      confirmText: '删除',
      destructive: true,
    );

    if (confirm == true) {
      try {
        // 本地优先删除习惯
        try {
          await DataService().deleteHabit(habit.id, habit.id);
        } catch (e) {
          await ApiService.deleteHabit(habit.id);
        }
        _loadHabits();
      } catch (e) {
        _showError('删除失败');
      }
    }
  }

  Future<void> _uncheckIn(Habit habit) async {
    final confirm = await FxDialog.confirm(
      context: context,
      title: '取消打卡',
      content: '确定取消今天「${habit.name}」的打卡？连续天数将重新计算。',
      confirmText: '取消打卡',
    );

    if (confirm == true) {
      try {
        final result = await ApiService.uncheckInHabit(habit.id);
        if (mounted) {
          _showSuccess('已取消打卡，连续天数: ${result['streak_count']}');
        }
        _loadHabits();
        // 刷新展开面板的打卡记录
        if (_expandedHabitId == habit.id) {
          _toggleHabitDetail(habit); // 先关闭
          _toggleHabitDetail(habit); // 再打开刷新
        }
      } catch (e) {
        _showError(e.toString().contains('未打卡') ? '今天还没有打卡' : '取消打卡失败');
      }
    }
  }

  Future<void> _editHabit(Habit habit) async {
    final result = await showShadDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _CreateHabitDialog(habit: habit),
    );

    if (result != null) {
      try {
        await ApiService.updateHabit(habit.id, {
          'name': result['name'],
          'icon': result['icon'],
          'color': result['color'],
          'frequency': result['frequency'],
          'target_days': result['target_days'] ?? 0,
          'system_tag_id': result['system_tag_id'],
          'preferred_period': result['preferred_period'] ?? '',
          'duration_min': result['duration_min'] ?? 0,
          'generate_task': result['generate_task'] ?? false,
          'specific_time': result['specific_time'] ?? '',
          'reminder_at': result['reminder_at'] ?? {},
        });
        _loadHabits();
      } catch (e) {
        _showError('编辑失败');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.priorityHigh),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.success),
    );
  }

  void _toggleHabitDetail(Habit habit) async {
    if (_expandedHabitId == habit.id) {
      setState(() {
        _expandedHabitId = null;
        _expandedHabitLogs = [];
      });
      return;
    }
    setState(() {
      _expandedHabitId = habit.id;
      _loadingDetail = true;
    });
    try {
      final now = DateTime.now();
      final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final data = await ApiService.getHabitLogs(habit.id, month: monthStr);
      if (mounted && _expandedHabitId == habit.id) {
        setState(() {
          _expandedHabitLogs = (data['logs'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          _loadingDetail = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Widget _buildInlineDetail(Habit habit, Color color) {
    if (_loadingDetail) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final checkInDates = _expandedHabitLogs
        .map((log) => DateTime.parse(log['created_at'] as String))
        .toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 热力图
          HabitHeatmap(checkInDates: checkInDates, color: color),
          if (_expandedHabitLogs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('最近打卡记录',
                style: TextStyle(
                  fontSize: AppTheme.textMd,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warmDark,
                )),
            const SizedBox(height: 8),
            ..._expandedHabitLogs.take(5).map((log) {
              final checkedAt = DateTime.parse(log['created_at'] as String);
              final note = log['note'] as String? ?? '';
              final dMin = log['duration_min'] as int? ?? 0;
              final period = log['period'] as String? ?? '';
              final m = checkedAt.month.toString().padLeft(2, '0');
              final d = checkedAt.day.toString().padLeft(2, '0');
              final h = checkedAt.hour.toString().padLeft(2, '0');
              final min = checkedAt.minute.toString().padLeft(2, '0');
              // 判断是否是今天的记录
              final now = DateTime.now();
              final todayStr =
                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
              final logDate = log['date'] as String? ?? '';
              final isToday = logDate == todayStr;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('$m-$d $h:$min',
                                  style: TextStyle(
                                    fontSize: AppTheme.textMd,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.warmDark,
                                  )),
                              if (dMin > 0) ...[
                                const SizedBox(width: 6),
                                Text('$dMin 分钟',
                                    style: TextStyle(
                                      fontSize: AppTheme.textXs,
                                      color: AppTheme.warmGray500,
                                    )),
                              ],
                              if (period.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _periodLabel(period),
                              ],
                            ],
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(note,
                                style: TextStyle(
                                  fontSize: AppTheme.textSm,
                                  color: AppTheme.warmGray500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 4),
                      FxInkWell(
                        onTap: () => _uncheckIn(habit),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.cancel_outlined,
                              size: 18,
                              color:
                                  AppTheme.priorityHigh.withValues(alpha: 0.7)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
          // 操作按钮栏
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _editHabit(habit),
                icon: Icon(Icons.edit_outlined,
                    size: 18, color: AppTheme.warmGray500),
                label: Text('编辑',
                    style: TextStyle(
                        fontSize: AppTheme.textMd,
                        color: AppTheme.warmGray500)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (_expandedHabitLogs.isEmpty) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _deleteHabit(habit),
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.priorityHigh),
                  label: Text('删除',
                      style: TextStyle(
                          fontSize: AppTheme.textMd,
                          color: AppTheme.priorityHigh)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _periodLabel(String period) {
    const labels = {
      'morning': '☀️ 早晨',
      'afternoon': '🌤 下午',
      'evening': '🌆 傍晚',
      'night': '🌙 晚间'
    };
    final label = labels[period] ?? '';
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(label,
        style:
            TextStyle(fontSize: AppTheme.textXs, color: AppTheme.warmGray500));
  }

  /// 判断当前是否嵌入在 Tab 中（Navigator 只有 1 层则说明是内嵌）
  bool get _isEmbedded => Navigator.of(context).canPop() == false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎯 习惯打卡'),
        // 内嵌 Tab 时不显示返回按钮（没有上一级可 pop）
        automaticallyImplyLeading: !_isEmbedded,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            onPressed: _isLoading ? null : _loadHabits,
          ),
        ],
        leading: _isEmbedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: '返回',
              ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _habits.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadHabits,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _habits.length,
                    itemBuilder: (context, index) {
                      final habit = _habits[index];
                      return _buildHabitCard(habit);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createHabit,
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.warmWhite,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
                child: Text('🎯', style: TextStyle(fontSize: 36, height: 1.2))),
          ),
          const SizedBox(height: 24),
          Text(
            '还没有习惯',
            style: TextStyle(
              fontSize: AppTheme.textXl,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '点击 + 添加第一个习惯',
            style: TextStyle(color: AppTheme.warmGray500),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitCard(Habit habit) {
    final habitColor = ColorUtils.safeParse(habit.color);
    final isAnimating = _animatingIds.contains(habit.id);
    final isAchieved =
        habit.targetDays > 0 && habit.streakCount >= habit.targetDays;
    final isExpanded = _expandedHabitId == habit.id;

    return Column(
      children: [
        Container(
          margin: EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isExpanded
                    ? habitColor.withValues(alpha: 0.4)
                    : AppTheme.warmBorder,
                width: isExpanded ? 1.5 : 1),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: FxInkWell(
              onTap: () => _toggleHabitDetail(habit),
              onLongPress: () => _deleteHabit(habit),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // 图标 — 打卡动画
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.elasticOut,
                      width: isAnimating ? 64 : 56,
                      height: isAnimating ? 64 : 56,
                      decoration: BoxDecoration(
                        color: habitColor.withValues(
                            alpha: isAnimating ? 0.2 : 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: TextStyle(fontSize: isAnimating ? 32 : 28),
                          child: Text(habit.icon),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    // 信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(habit.name,
                              style: TextStyle(
                                fontSize: AppTheme.textLg,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                                height: 1.3,
                              )),
                          const SizedBox(height: 4),
                          Text(habit.frequencyText,
                              style: TextStyle(
                                  color: AppTheme.warmGray500,
                                  fontSize: AppTheme.textMd,
                                  height: 1.5)),
                        ],
                      ),
                    ),
                    // 连续天数 pill badge
                    if (habit.streakCount > 0)
                      Container(
                        margin: EdgeInsets.only(right: 12),
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAchieved
                              ? AppTheme.priorityLow.withValues(alpha: 0.1)
                              : AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(isAchieved ? '🏆' : '🔥',
                              style: TextStyle(
                                  fontSize: AppTheme.textMd, height: 1.5)),
                          SizedBox(width: 4),
                          Text(
                            habit.targetDays > 0
                                ? '${habit.streakCount}/${habit.targetDays}天'
                                : '${habit.streakCount}天',
                            style: TextStyle(
                              fontSize: AppTheme.textMd,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                              color: isAchieved
                                  ? AppTheme.priorityLow
                                  : AppTheme.primary,
                            ),
                          ),
                        ]),
                      ),
                    // 补卡按钮
                    FxInkWell(
                      onTap: () => _backfillCheckIn(habit),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.warmWhite,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppTheme.warmBorder, width: 1),
                        ),
                        child: Icon(Icons.history,
                            size: 18, color: AppTheme.warmGray500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 打卡按钮
                    FxInkWell(
                      onTap: () => _checkIn(habit),
                      borderRadius: BorderRadius.circular(12),
                      splashColor: habitColor.withValues(alpha: 0.15),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isAnimating
                              ? habitColor
                              : habitColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isAnimating
                              ? Icons.check
                              : Icons.check_circle_outline,
                          size: 24,
                          color: isAnimating ? AppTheme.white : habitColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 内嵌详情
        if (isExpanded) _buildInlineDetail(habit, habitColor),
        SizedBox(height: 12),
      ],
    );
  }
}
// ═══════════════════════════════════════════
// 创建习惯对话框 — 含模板库
// ═══════════════════════════════════════════

/// 习惯模板数据
class _HabitTemplate {
  final String name;
  final String icon;
  final String color;
  const _HabitTemplate(this.name, this.icon, this.color);
}

const _templates = [
  _HabitTemplate('早起', '🌅', '#fa8c16'),
  _HabitTemplate('喝水', '💧', '#1890ff'),
  _HabitTemplate('运动', '💪', '#52c41a'),
  _HabitTemplate('阅读', '📚', '#722ed1'),
  _HabitTemplate('冥想', '🧘', '#13c2c2'),
  _HabitTemplate('早睡', '💤', '#2f54eb'),
  _HabitTemplate('写作', '✍️', '#eb2f96'),
  _HabitTemplate('跑步', '🏃', '#f5222d'),
  _HabitTemplate('记账', '💰', '#faad14'),
  _HabitTemplate('学英语', '🌍', '#1890ff'),
  _HabitTemplate('不吃零食', '🚫', '#ff4d4f'),
  _HabitTemplate('整理房间', '🏠', '#52c41a'),
];

class _CreateHabitDialog extends StatefulWidget {
  final Habit? habit;
  const _CreateHabitDialog({this.habit});

  @override
  State<_CreateHabitDialog> createState() => _CreateHabitDialogState();
}

class _CreateHabitDialogState extends State<_CreateHabitDialog> {
  final _nameController = TextEditingController();
  String _selectedIcon = '✅';
  String _selectedColor = '#52c41a';
  String _frequency = 'daily';
  int _repeatInterval = 1;
  Set<int> _selectedWeekdays = {};
  int _targetDays = 0; // 0=无限制
  bool _showTemplates = true;
  bool _showAdvanced = false;

  // 新字段
  int? _selectedSystemTagId;
  String _preferredPeriod = '';
  int _durationMin = 0;
  bool _generateTask = false;
  bool _showCheckinDialog = false;
  List<Map<String, dynamic>> _systemTags = [];
  bool _loadingTags = true;

  // 新增字段：计划时间 + 提醒
  String _specificTime = '';
  TimeOfDay? _reminderTime;

  final _icons = [
    '✅',
    '💪',
    '📚',
    '🏃',
    '🧘',
    '💧',
    '🍎',
    '💤',
    '📝',
    '🎯',
    '✍️',
    '🌍'
  ];
  final _colors = [
    '#52c41a',
    '#1890ff',
    '#722ed1',
    '#eb2f96',
    '#fa8c16',
    '#13c2c2',
    '#f5222d',
    '#2f54eb'
  ];
  final _periods = [
    {'value': '', 'label': '不限'},
    {'value': 'morning', 'label': '🌅 早晨'},
    {'value': 'afternoon', 'label': '☀️ 下午'},
    {'value': 'evening', 'label': '🌆 傍晚'},
    {'value': 'night', 'label': '🌙 晚间'},
  ];

  @override
  void initState() {
    super.initState();
    // 编辑模式：预填字段
    final h = widget.habit;
    if (h != null) {
      _nameController.text = h.name;
      _selectedIcon = h.icon;
      _selectedColor = h.color;
      _frequency = h.frequency;
      _repeatInterval = 1;
      _selectedWeekdays = {};
      _targetDays = h.targetDays;
      _selectedSystemTagId = h.systemTagId;
      _specificTime = h.specificTime;
      _preferredPeriod = h.preferredPeriod;
      _durationMin = h.durationMin;
      _generateTask = h.generateTask;
      _showCheckinDialog = h.showCheckinDialog;
      _showTemplates = false;
      if (h.reminderAt.containsKey('hour') &&
          h.reminderAt.containsKey('minute')) {
        _reminderTime = TimeOfDay(
          hour: h.reminderAt['hour'] as int,
          minute: h.reminderAt['minute'] as int,
        );
      }
    }
    _loadSystemTags();
  }

  Future<void> _loadSystemTags() async {
    try {
      final tags = await ApiService.getSystemTags();
      if (mounted) {
        setState(() {
          _systemTags = tags;
          _loadingTags = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTags = false);
    }
  }

  void _useTemplate(_HabitTemplate t) {
    setState(() {
      _nameController.text = t.name;
      _selectedIcon = t.icon;
      _selectedColor = t.color;
      _showTemplates = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Text(widget.habit != null ? '编辑习惯' : '添加习惯'),
      description: null,
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 模板库
              if (_showTemplates) ...[
                _buildSectionLabel('⚡', '快速添加'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _templates.map((t) {
                    return FxInkWell(
                      onTap: () => _useTemplate(t),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: ColorUtils.safeParse(t.color)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppTheme.warmBorder, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.icon,
                                style: const TextStyle(
                                    fontSize: AppTheme.textLg, height: 1.3)),
                            const SizedBox(width: 4),
                            Text(
                              t.name,
                              style: TextStyle(
                                fontSize: AppTheme.textMd,
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                                color: ColorUtils.safeParse(t.color),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ShadButton.ghost(
                    onPressed: () => setState(() => _showTemplates = false),
                    child: const Text('自定义',
                        style:
                            TextStyle(fontSize: AppTheme.textMd, height: 1.5)),
                  ),
                ),
              ],

              if (!_showTemplates) ...[
                FxInput(
                  controller: _nameController,
                  label: '习惯名称',
                  placeholder: '例如：早起、运动、阅读',
                  autofocus: true,
                ),
                const SizedBox(height: 20),
                _buildSectionLabel('📝', '选择图标'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _icons.map((icon) {
                    final isSelected = _selectedIcon == icon;
                    return FxInkWell(
                      onTap: () => setState(() => _selectedIcon = icon),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 150),
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryLight
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primary
                                : AppTheme.warmBorder,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(icon,
                            style: const TextStyle(fontSize: 24, height: 1.2)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                _buildSectionLabel('🎨', '选择颜色'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _colors.map((color) {
                    final isSelected = _selectedColor == color;
                    final c = ColorUtils.safeParse(color);
                    return FxInkWell(
                      onTap: () => setState(() => _selectedColor = color),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 150),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.warmDark
                                : Colors.transparent,
                            width: isSelected ? 3 : 0,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                size: 18, color: AppTheme.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                _buildSectionLabel('📅', '频率'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _frequency,
                  decoration: const InputDecoration(labelText: '频率'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('每天')),
                    DropdownMenuItem(value: 'weekly', child: Text('每周')),
                    DropdownMenuItem(value: 'monthly', child: Text('每月')),
                    DropdownMenuItem(value: 'yearly', child: Text('每年')),
                  ],
                  onChanged: (v) => setState(() {
                    _frequency = v!;
                    if (v != 'weekly') _selectedWeekdays.clear();
                  }),
                ),
                // 重复间隔
                if (_frequency != 'none') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('每',
                          style: TextStyle(
                              color: AppTheme.warmGray500,
                              fontSize: AppTheme.textMd)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: FxInput(
                          controller: TextEditingController(
                              text: _repeatInterval.toString()),
                          keyboardType: TextInputType.number,
                          onChanged: (v) =>
                              _repeatInterval = int.tryParse(v) ?? 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_frequencyUnit,
                          style: TextStyle(
                              color: AppTheme.warmGray500,
                              fontSize: AppTheme.textMd)),
                    ],
                  ),
                ],
                // 周几选择
                if (_frequency == 'weekly') ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _weekdayButton(1, '一'),
                      _weekdayButton(2, '二'),
                      _weekdayButton(3, '三'),
                      _weekdayButton(4, '四'),
                      _weekdayButton(5, '五'),
                      _weekdayButton(6, '六'),
                      _weekdayButton(7, '日'),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // 目标天数
                _buildSectionLabel('🏆', '目标天数（可选）'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _targetChip(0, '无限制'),
                    _targetChip(7, '7天'),
                    _targetChip(21, '21天'),
                    _targetChip(30, '30天'),
                    _targetChip(66, '66天'),
                    _targetChip(100, '100天'),
                  ],
                ),
                const SizedBox(height: 8),
                // 系统标签
                _buildSectionLabel('🏷️', '分类标签'),
                const SizedBox(height: 10),
                if (_loadingTags)
                  const SizedBox(
                      height: 32,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)))
                else if (_systemTags.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('无'),
                        selected: _selectedSystemTagId == null,
                        onSelected: (_) =>
                            setState(() => _selectedSystemTagId = null),
                      ),
                      ...{for (final t in _systemTags) t['id']: t}
                          .values
                          .map((tag) {
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(tag['icon'] ?? '🏷️'),
                              const SizedBox(width: 4),
                              Text(tag['name'] ?? ''),
                            ],
                          ),
                          selected: _selectedSystemTagId == tag['id'],
                          onSelected: (_) =>
                              setState(() => _selectedSystemTagId = tag['id']),
                        );
                      }),
                    ],
                  )
                else
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '暂无分类标签，可在“系统标签”页面添加',
                      style: TextStyle(
                          fontSize: AppTheme.textSm,
                          height: 1.5,
                          color: AppTheme.warmGray400),
                    ),
                  ),
                const SizedBox(height: 16),
                // 预期时长
                _buildSectionLabel('⏱️', '预期时长（分钟）'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _durationChip(0, '不限'),
                    _durationChip(15, '15分钟'),
                    _durationChip(30, '30分钟'),
                    _durationChip(60, '1小时'),
                  ],
                ),
                SizedBox(height: 16),
                // 自动生成任务
                Row(
                  children: [
                    Expanded(
                        child: Text('自动生成每日任务',
                            style: TextStyle(
                                fontSize: AppTheme.textMd,
                                height: 1.5,
                                color: AppTheme.warmGray500))),
                    FxSwitch(
                      value: _generateTask,
                      onChanged: (v) => setState(() => _generateTask = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('打卡弹窗',
                          style: TextStyle(
                              fontSize: AppTheme.textMd,
                              height: 1.5,
                              color: AppTheme.warmDark)),
                    ),
                    Text('打卡时弹窗填写日志',
                        style: TextStyle(
                            fontSize: AppTheme.textXs,
                            height: 1.4,
                            color: AppTheme.warmGray500)),
                    const SizedBox(width: 8),
                    FxSwitch(
                      value: _showCheckinDialog,
                      onChanged: (v) => setState(() => _showCheckinDialog = v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 计划时间
                _buildSectionLabel('⏰', '计划时间（可选）'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ..._periods.map((p) {
                      final isSelected = _specificTime == p['value'];
                      return ChoiceChip(
                        label: Text(p['label']!),
                        selected: isSelected,
                        onSelected: (_) => setState(() {
                          _specificTime = isSelected ? '' : p['value']!;
                        }),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 16),
                // 提醒时间
                _buildSectionLabel('🔔', '提醒时间（可选）'),
                const SizedBox(height: 10),
                FxInkWell(
                  onTap: () async {
                    final time =
                        await _showCustomTimePicker(context, _reminderTime);
                    if (time != null) {
                      setState(() => _reminderTime = time);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.warmWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.warmBorder, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_none,
                            size: 20, color: AppTheme.warmGray500),
                        const SizedBox(width: 12),
                        Text(
                          _reminderTime != null
                              ? '${_reminderTime!.hour.toString().padLeft(2, '0')}:${_reminderTime!.minute.toString().padLeft(2, '0')}'
                              : '选择提醒时间',
                          style: TextStyle(
                            fontSize: AppTheme.textMd,
                            height: 1.5,
                            color: _reminderTime != null
                                ? Theme.of(context).colorScheme.onSurface
                                : AppTheme.warmGray400,
                          ),
                        ),
                        const Spacer(),
                        if (_reminderTime != null)
                          FxInkWell(
                            onTap: () => setState(() => _reminderTime = null),
                            child: Icon(Icons.close,
                                size: 18, color: AppTheme.warmGray400),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 保存按钮
                FxButton(
                  label: widget.habit != null ? '保存修改' : '创建习惯',
                  icon: Icons.check,
                  expanded: true,
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty) return;
                    Navigator.pop(context, {
                      'name': _nameController.text.trim(),
                      'icon': _selectedIcon,
                      'color': _selectedColor,
                      'frequency': _frequency,
                      'repeat_interval': _repeatInterval,
                      'repeat_days': _selectedWeekdays.toList()..sort(),
                      'target_days': _targetDays,
                      'system_tag_id': _selectedSystemTagId,
                      'preferred_period': _specificTime,
                      'duration_min': _durationMin,
                      'generate_task': _generateTask,
                      'show_checkin_dialog': _showCheckinDialog,
                      'specific_time': _specificTime,
                      'reminder_at': _reminderTime != null
                          ? {
                              'hour': _reminderTime!.hour,
                              'minute': _reminderTime!.minute
                            }
                          : <String, dynamic>{},
                    });
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ShadButton.ghost(
                    onPressed: () => setState(() => _showTemplates = true),
                    child: const Text('← 返回模板',
                        style:
                            TextStyle(fontSize: AppTheme.textMd, height: 1.5)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ), // Material
      actions: [
        ShadButton.ghost(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }

  Widget _buildSectionLabel(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: TextStyle(fontSize: AppTheme.textLg, height: 1.3)),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: AppTheme.textMd,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _targetChip(int days, String label) {
    final isSelected = _targetDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _targetDays = days),
    );
  }

  Widget _durationChip(int minutes, String label) {
    final isSelected = _durationMin == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _durationMin = minutes),
    );
  }

  String get _frequencyUnit {
    switch (_frequency) {
      case 'daily':
        return '天';
      case 'weekly':
        return '周';
      case 'monthly':
        return '月';
      case 'yearly':
        return '年';
      default:
        return '天';
    }
  }

  Widget _weekdayButton(int day, String label) {
    final isSelected = _selectedWeekdays.contains(day);
    return FxGestureDetector(
      onTap: () => setState(() {
        if (isSelected) {
          _selectedWeekdays.remove(day);
        } else {
          _selectedWeekdays.add(day);
        }
      }),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppTheme.primary : AppTheme.warmWhite,
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.warmBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTheme.textXs,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? AppTheme.white : AppTheme.warmGray500,
          ),
        ),
      ),
    );
  }

  /// 自定义时间选择器 — 比 Material 的好看
  Future<TimeOfDay?> _showCustomTimePicker(
      BuildContext context, TimeOfDay? initial) async {
    int selectedHour = initial?.hour ?? 8;
    int selectedMinute = initial?.minute ?? 0;

    return showDialog<TimeOfDay>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.warmWhite,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.access_time, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  const Text('选择时间',
                      style: TextStyle(
                          fontSize: AppTheme.textLg,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 时间预览
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 24),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w300,
                          color: AppTheme.primary,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 小时
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('小时',
                          style: TextStyle(
                              fontSize: AppTheme.textXs,
                              color: AppTheme.warmGray400)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List.generate(24, (i) {
                        final isSelected = selectedHour == i;
                        return FxGestureDetector(
                          onTap: () => setDialogState(() => selectedHour = i),
                          child: Container(
                            width: 40,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.warmWhite,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primary
                                    : AppTheme.warmBorder,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              i.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: AppTheme.textSm,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppTheme.white
                                    : AppTheme.warmGray500,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    // 分钟
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('分钟',
                          style: TextStyle(
                              fontSize: AppTheme.textXs,
                              color: AppTheme.warmGray400)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
                          .map((i) {
                        final isSelected = selectedMinute == i;
                        return FxGestureDetector(
                          onTap: () => setDialogState(() => selectedMinute = i),
                          child: Container(
                            width: 40,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.warmWhite,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primary
                                    : AppTheme.warmBorder,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              i.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: AppTheme.textSm,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppTheme.white
                                    : AppTheme.warmGray500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child:
                      Text('取消', style: TextStyle(color: AppTheme.warmGray400)),
                ),
                FxButton(
                  label: '确定',
                  onPressed: () => Navigator.pop(ctx,
                      TimeOfDay(hour: selectedHour, minute: selectedMinute)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 公开方法：显示创建习惯对话框（供 home_screen 等外部调用）
Future<Map<String, dynamic>?> showCreateHabitDialog(BuildContext context) {
  return showShadDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => const _CreateHabitDialog(),
  );
}
