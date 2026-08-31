import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// 习惯滑动打卡组件
///
/// 支持两种打卡方式：
/// 1. 向左滑动（Dismissible）
/// 2. 点击右侧图标
///
/// 打卡成功后回调 [onCheckin]
class HabitCheckinWidget extends StatelessWidget {
  final Habit habit;
  final bool isCheckedToday;
  final VoidCallback? onCheckin;

  const HabitCheckinWidget({
    super.key,
    required this.habit,
    this.isCheckedToday = false,
    this.onCheckin,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('habit_${habit.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _checkIn(context);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppTheme.success,
        child: const Icon(Icons.check, color: Colors.white),
      ),
      child: FxListTile(
        leading: Text(habit.icon, style: const TextStyle(fontSize: SlowlightTypography.heroSize)),
        title: habit.name,
        subtitle: '连续 ${habit.streakCount} 天',
        trailing: FxIconButton(
          icon: isCheckedToday ? Icons.check_circle : Icons.circle_outlined,
          tooltip: isCheckedToday ? '今天已打卡' : '打卡',
          onPressed: () => _checkIn(context),
        ),
      ),
    );
  }

  Future<void> _checkIn(BuildContext context) async {
    try {
      await ApiService.checkInHabit(habit.id);
      onCheckin?.call();
    } catch (e) {
      if (context.mounted) {
        FxNotice.showContent(
          context,
          Text('打卡失败: $e'),
          variant: FxNoticeVariant.destructive,
        );
      }
    }
  }
}
