import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/habit_heatmap.dart';
import '../utils/color_utils.dart';

class HabitDetailScreen extends StatefulWidget {
  final Habit habit;

  const HabitDetailScreen({super.key, required this.habit});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];
  int _totalCheckIns = 0;
  double _completionRate = 0.0;

  @override
  void initState() {
    super.initState();
    _loadHabitLogs();
  }

  Future<void> _loadHabitLogs() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final data =
          await ApiService.getHabitLogs(widget.habit.id, month: monthStr);
      final logs =
          (data['logs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      // 计算当月天数用于完成率
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final uniqueDays = logs
          .map((log) => DateTime.parse(log['created_at'] as String))
          .map((d) =>
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}')
          .toSet()
          .length;

      setState(() {
        _logs = logs;
        _totalCheckIns = logs.length;
        _completionRate = daysInMonth > 0 ? uniqueDays / daysInMonth : 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editLog(Map<String, dynamic> log) async {
    final note = TextEditingController(text: log['note'] as String? ?? '');
    final duration = TextEditingController(text: '${log['duration_min'] ?? 0}');

    Widget editor(BuildContext modalContext, {required bool showTitle}) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            Text(
              '编辑打卡记录',
              style: Theme.of(modalContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '时长（分钟）'),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FxButton(
                  label: '取消',
                  variant: FxButtonVariant.outline,
                  onPressed: () => Navigator.pop(modalContext),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FxButton(
                  label: '保存',
                  onPressed: () => Navigator.pop(modalContext, {
                    'note': note.text,
                    'duration_min': int.tryParse(duration.text) ?? 0,
                  }),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final mobile = MediaQuery.sizeOf(context).width < 600;
    final result = mobile
        ? await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            isScrollControlled: true,
            builder: (sheetContext) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: editor(sheetContext, showTitle: true),
                ),
              ),
            ),
          )
        : await FxDialog.show<Map<String, dynamic>>(
            context: context,
            title: '编辑打卡记录',
            child: Builder(
              builder: (dialogContext) =>
                  editor(dialogContext, showTitle: false),
            ),
          );
    note.dispose();
    duration.dispose();
    if (result == null || !mounted) return;
    try {
      await ApiService.updateHabitLog(
          widget.habit.id, log['id'] as int, result);
      await _loadHabitLogs();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final habitColor = ColorUtils.safeParse(habit.color);

    // 将 log 日期转为 DateTime 列表（用于热力图）
    final checkInDates = _logs
        .map((log) => DateTime.parse(log['created_at'] as String))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${habit.icon} ${habit.name}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '返回',
        ),
      ),
      backgroundColor: AppTheme.warmWhite,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHabitLogs,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                children: [
                  // ═══ 顶部统计卡片 ═══
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          emoji: '🔥',
                          value: '${habit.streakCount}',
                          label: '连续',
                          color: habitColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          emoji: '✅',
                          value: '$_totalCheckIns',
                          label: '总计',
                          color: habitColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          emoji: '📊',
                          value:
                              '${(_completionRate * 100).toStringAsFixed(0)}%',
                          label: '完成率',
                          color: habitColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ═══ 热力图 ═══
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.warmBorder),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: HabitHeatmap(
                      checkInDates: checkInDates,
                      color: habitColor,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ═══ 最近打卡记录 ═══
                  Text(
                    '最近打卡记录',
                    style: TextStyle(
                      fontSize: AppTheme.textLg,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warmDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _logs.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.warmBorder),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          child: Column(
                            children: [
                              Text(
                                habit.icon,
                                style: const TextStyle(
                                    fontSize: AppTheme.textXl, height: 1.2),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '暂无打卡记录',
                                style: TextStyle(
                                  fontSize: AppTheme.textMd,
                                  height: 1.5,
                                  color: AppTheme.warmGray500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.warmBorder),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _logs.length.clamp(0, 30),
                            separatorBuilder: (_, __) => Divider(
                              color: AppTheme.warmBorder,
                              height: 1,
                            ),
                            itemBuilder: (context, index) {
                              final log = _logs[index];
                              final checkedAt =
                                  DateTime.parse(log['created_at'] as String);
                              final note = log['note'] as String? ?? '';
                              final dMin = log['duration_min'] as int? ?? 0;
                              final period = log['period'] as String? ?? '';

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: habitColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                _formatDateTime(checkedAt),
                                                style: TextStyle(
                                                  fontSize: AppTheme.textMd,
                                                  height: 1.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppTheme.warmDark,
                                                ),
                                              ),
                                              if (dMin > 0) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '$dMin 分钟',
                                                  style: TextStyle(
                                                    fontSize: AppTheme.textXs,
                                                    color: AppTheme.warmGray500,
                                                  ),
                                                ),
                                              ],
                                              if (period.isNotEmpty) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  _periodLabel(period),
                                                  style: TextStyle(
                                                    fontSize: AppTheme.textXs,
                                                    color: AppTheme.warmGray500,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (note.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              note,
                                              style: TextStyle(
                                                fontSize: AppTheme.textMd,
                                                height: 1.5,
                                                color: AppTheme.warmGray500,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '编辑记录',
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18),
                                      onPressed: () => _editLog(log),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  String _periodLabel(String period) {
    const labels = {
      'morning': '☀️ 早晨',
      'afternoon': '🌤 下午',
      'evening': '🌆 傍晚',
      'night': '🌙 晚间'
    };
    return labels[period] ?? '';
  }

  String _formatDateTime(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }
}

/// 统计卡片组件
class _StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warmBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji,
              style: const TextStyle(fontSize: AppTheme.textXl, height: 1.2)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: AppTheme.textXl,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTheme.textXs,
              height: 1.4,
              color: AppTheme.warmGray500,
            ),
          ),
        ],
      ),
    );
  }
}
