import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/habit.dart';
import '../services/api_service.dart';

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
        // 滑动时先确认打卡，返回 false 阻止 Dismissible 移除
        await _checkIn(context);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppTheme.success,
        child: const Icon(Icons.check, color: Colors.white),
      ),
      child: ListTile(
        leading: Text(habit.icon, style: const TextStyle(fontSize: 24)),
        title: Text(habit.name),
        subtitle: Text('连续 ${habit.streakCount} 天'),
        trailing: IconButton(
          icon: Icon(
            isCheckedToday ? Icons.check_circle : Icons.circle_outlined,
            color: isCheckedToday ? AppTheme.success : AppTheme.warmGray400,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打卡失败: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}
