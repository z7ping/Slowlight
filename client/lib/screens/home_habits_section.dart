import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/habit_checkin_dialog.dart';
import '../utils/color_utils.dart';

/// 习惯打卡区域组件
class HomeHabitsSection extends StatefulWidget {
  final List<Map<String, dynamic>> habits;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRefresh;

  const HomeHabitsSection({
    super.key,
    required this.habits,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onRefresh,
  });

  @override
  State<HomeHabitsSection> createState() => _HomeHabitsSectionState();
}

class _HomeHabitsSectionState extends State<HomeHabitsSection> {
  int? _expandedHabitId;
  Map<String, dynamic>? _expandedHabitLogs;
  bool _loadingDetail = false;

  void _toggleHabitDetail(Map<String, dynamic> habit) async {
    final id = (habit['id'] as num).toInt();
    if (_expandedHabitId == id) {
      setState(() {
        _expandedHabitId = null;
        _expandedHabitLogs = null;
      });
      return;
    }
    setState(() {
      _expandedHabitId = id;
      _loadingDetail = true;
    });
    try {
      final now = DateTime.now();
      final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final data = await ApiService.getHabitLogs(id, month: monthStr);
      if (mounted && _expandedHabitId == id) {
        setState(() {
          _expandedHabitLogs = data;
          _loadingDetail = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  String _periodLabel(String period) {
    const labels = {'morning': '☀️ 早晨', 'afternoon': '🌤 下午', 'evening': '🌆 傍晚', 'night': '🌙 晚间'};
    return labels[period] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warmGray300.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warmBorder.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FxInkWell(
            onTap: widget.onToggleExpanded,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.expanded ? 8 : 0),
              child: Row(
                children: [
                  Icon(Icons.repeat, size: 14, color: AppTheme.warmGray400),
                  const SizedBox(width: 4),
                  Text(
                    '习惯 ${widget.habits.length} 项',
                    style: TextStyle(fontSize: AppTheme.textMd, height: 1.4, fontWeight: FontWeight.w600, color: AppTheme.warmGray500),
                  ),
                  const Spacer(),
                  Icon(
                    widget.expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: AppTheme.warmGray400,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded) ...[
            if (widget.habits.isNotEmpty)
              ...widget.habits.map((habit) {
                final color = ColorUtils.safeParse(habit['color'] ?? '#52c41a');
                final now = DateTime.now();
                final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                final checkedToday = habit['checked_today'] == true;
                final streak = habit['streak_count'] ?? 0;
                final showDialog = habit['show_checkin_dialog'] == true || habit['show_checkin_dialog'] == 1;
                final habitId = (habit['id'] as num).toInt();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: FxInkWell(
                    onTap: () async {
                      if (checkedToday) {
                        final confirm = await FxDialog.confirm(
                          context: context,
                          title: '取消打卡',
                          content: '确定取消今天「${habit['name']}」的打卡？连续天数将重新计算。',
                          confirmText: '取消打卡',
                        );
                        if (confirm == true) {
                          try {
                            await ApiService.uncheckInHabit(habitId);
                            widget.onRefresh();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已取消「${habit['name']}」的打卡'), duration: const Duration(seconds: 2)),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('取消失败：${e.toString()}'), backgroundColor: Theme.of(context).colorScheme.error),
                              );
                            }
                          }
                        }
                        return;
                      }
                      // 根据设置决定是否弹窗
                      if (showDialog) {
                        final result = await HabitCheckinDialog.show(context, habit: Habit.fromJson(habit));
                        if (result == null || !mounted) return;
                        try {
                          await ApiService.checkInHabit(habitId,
                            durationMin: result['duration_min'] as int,
                            period: result['period'] as String,
                            note: result['note'] as String? ?? '',
                          );
                          widget.onRefresh();
                          if (mounted) {
                            _showCheckinSuccess(context, habit['name'] as String);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('打卡失败：${e.toString()}'), backgroundColor: Theme.of(context).colorScheme.error),
                            );
                          }
                        }
                        return;
                      }
                      // 快速打卡
                      try {
                        await ApiService.checkInHabit(habitId,
                          durationMin: habit['duration_min'] as int? ?? 0,
                          period: habit['preferred_period'] as String? ?? '',
                        );
                        widget.onRefresh();
                        if (mounted) {
                          _showCheckinSuccess(context, habit['name'] as String);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('打卡失败：${e.toString()}'), backgroundColor: Theme.of(context).colorScheme.error),
                          );
                        }
                      }
                    },
                    onLongPress: () async {
                      // 长按弹窗可填日志（无论 quick 还是 dialog 模式）
                      final h = Habit.fromJson(habit);
                      final result = await HabitCheckinDialog.show(context, habit: h);
                      if (result == null || !mounted) return;
                      try {
                        await ApiService.checkInHabit(habitId,
                          durationMin: result['duration_min'] as int,
                          period: result['period'] as String,
                          note: result['note'] as String? ?? '',
                        );
                        widget.onRefresh();
                        if (mounted) {
                          _showCheckinSuccess(context, habit['name'] as String);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('打卡失败：${e.toString()}'), backgroundColor: Theme.of(context).colorScheme.error),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedOpacity(
                      opacity: checkedToday ? 0.75 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: checkedToday
                              ? Border(left: BorderSide(color: color, width: 3))
                              : null,
                        ),
                        padding: EdgeInsets.only(left: checkedToday ? 4 : 7),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: checkedToday ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(child: Text(habit['icon'] ?? '✅', style: const TextStyle(fontSize: AppTheme.textMd))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                habit['name'] ?? '',
                                style: TextStyle(
                                  fontSize: AppTheme.textMd, height: 1.4,
                                  color: AppTheme.textColor(context),
                                  decoration: checkedToday ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            if (streak > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  '🔥$streak',
                                  style: TextStyle(fontSize: AppTheme.textXs, color: AppTheme.warmGray400),
                                ),
                              ),
                            Icon(
                              checkedToday ? Icons.check_circle : Icons.check_circle_outline,
                              size: 20,
                              color: checkedToday ? color : AppTheme.warmGray300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              })
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Text('暂无习惯，去习惯页添加 🌱',
                      style: TextStyle(fontSize: AppTheme.textMd, color: AppTheme.warmGray400, height: 1.4)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 习惯详情里用的小统计卡片
class _MiniStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _MiniStat({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: AppTheme.textMd, height: 1.2)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: AppTheme.textLg, fontWeight: FontWeight.w700, color: AppTheme.warmDark)),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: AppTheme.textXs, color: AppTheme.warmGray500)),
      ],
    );
  }
}

/// 打卡成功动画
void _showCheckinSuccess(BuildContext context, String habitName) {
  // 显示全屏动画覆盖层
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _CheckinAnimation(
      habitName: habitName,
      onComplete: () => entry.remove(),
    ),
  );
  Overlay.of(context).insert(entry);
}

class _CheckinAnimation extends StatefulWidget {
  final String habitName;
  final VoidCallback onComplete;

  const _CheckinAnimation({
    required this.habitName,
    required this.onComplete,
  });

  @override
  State<_CheckinAnimation> createState() => _CheckinAnimationState();
}

class _CheckinAnimationState extends State<_CheckinAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    ));

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return IgnorePointer(
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Container(
              color: Colors.black.withValues(alpha: 0.3 * _opacityAnimation.value),
              child: Center(
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🎉', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 16),
                        Text(
                          '打卡成功',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.habitName,
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
