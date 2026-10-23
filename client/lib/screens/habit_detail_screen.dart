import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/habit.dart';
import '../services/api_service.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';
import '../widgets/habit_heatmap.dart';

/// 兼容旧页面；正式习惯入口已集中在 HabitToolScreen。
///
/// 习惯日历应使用 HabitLog.date，不能把补卡当天错误记成录入时间。
DateTime habitLogCalendarDay(Map<String, dynamic> log) {
  final date = DateTime.tryParse(log['date']?.toString() ?? '');
  if (date != null) return DateTime(date.year, date.month, date.day);
  final createdAt = DateTime.tryParse(
    log['created_at']?.toString() ?? '',
  )?.toLocal();
  if (createdAt == null) throw const FormatException('习惯记录日期无效');
  return DateTime(createdAt.year, createdAt.month, createdAt.day);
}

class HabitDetailScreen extends StatefulWidget {
  final Habit habit;
  final Future<Map<String, dynamic>> Function(int habitId, String month)?
  logsLoader;

  const HabitDetailScreen({super.key, required this.habit, this.logsLoader});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  bool _isLoading = true;
  bool _loadError = false;
  List<Map<String, dynamic>> _logs = [];
  int _totalCheckIns = 0;
  double _completionRate = 0.0;

  @override
  void initState() {
    super.initState();
    _loadHabitLogs();
  }

  Future<void> _loadHabitLogs() async {
    setState(() {
      _isLoading = true;
      _loadError = false;
    });
    try {
      final now = DateTime.now();
      final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final data = widget.logsLoader == null
          ? await ApiService.getHabitLogs(widget.habit.id, month: monthStr)
          : await widget.logsLoader!(widget.habit.id, monthStr);
      final logs =
          (data['logs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final uniqueDays = logs.map(habitLogCalendarDay).toSet().length;

      if (!mounted) return;
      setState(() {
        _logs = logs;
        _totalCheckIns = logs.length;
        _completionRate = daysInMonth > 0 ? uniqueDays / daysInMonth : 0;
        _isLoading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = true;
      });
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
            Text('编辑打卡记录', style: SlowlightTypography.cardTitle(modalContext)),
            const SizedBox(height: 16),
          ],
          FxInput(controller: note, label: '备注', placeholder: '记录这次打卡'),
          const SizedBox(height: 12),
          FxInput(
            controller: duration,
            label: '时长（分钟）',
            keyboardType: TextInputType.number,
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
                  onPressed:
                      () => Navigator.pop(modalContext, {
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
    final result =
        mobile
            ? await FxSheet.show<Map<String, dynamic>>(
                context: context,
                isScrollControlled: true,
                builder: (sheetContext) => SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    child: editor(sheetContext, showTitle: true),
                  ),
                ),
              )
            : await FxDialog.show<Map<String, dynamic>>(
              context: context,
              title: '编辑打卡记录',
              child: Builder(
                builder:
                    (dialogContext) => editor(dialogContext, showTitle: false),
              ),
            );
    note.dispose();
    duration.dispose();
    if (result == null || !mounted) return;
    try {
      await ApiService.updateHabitLog(
        widget.habit.id,
        log['id'] as int,
        result,
      );
      await _loadHabitLogs();
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(context, Text('保存失败：$e'));
      }
    }
  }

  Future<void> _deleteLog(Map<String, dynamic> log) async {
    final confirmed = await FxDialog.confirm(
      context: context, title: '撤销这条记录',
      content: '仅撤销这条记录，不影响当天其他记录。',
      confirmText: '撤销记录', destructive: true);
    if (confirmed != true) return;
    try {
      await ApiService.deleteHabitLog(widget.habit.id, log['id'] as int);
      await _loadHabitLogs();
      if (mounted) FxNotice.showContent(context, const Text('记录已撤销'));
    } catch (error) {
      if (mounted) FxNotice.showContent(context,
        Text('撤销结果未确认，请重新加载核对：$error'),
        variant: FxNoticeVariant.destructive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final habitColor = ColorUtils.safeParse(habit.color);
    final checkInDates = _logs.map(habitLogCalendarDay).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '${habit.icon} ${habit.name}',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: FxCircularProgress())
                      : _loadError
                      ? Center(
                          child: FxEmptyState(
                            icon: LucideIcons.triangleAlert,
                            title: '打卡记录暂时不可用',
                            subtitle: '数据读取失败，请重试。',
                            action: FxButton(
                              label: '重新加载',
                              variant: FxButtonVariant.secondary,
                              onPressed: _loadHabitLogs,
                            ),
                          ),
                        )
                      : FxRefresh(
                        onRefresh: _loadHabitLogs,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 20,
                          ),
                          children: [
                            _statsRow(habit, habitColor),
                            const SizedBox(height: 24),
                            FxCard(
                              padding: const EdgeInsets.all(16),
                              child: HabitHeatmap(
                                checkInDates: checkInDates,
                                color: habitColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '最近打卡记录',
                              style: SlowlightTypography.cardTitle(
                                context,
                              ).copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _logs.isEmpty
                                ? FxCard(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 32,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        habit.icon,
                                        style: SlowlightTypography.hero(
                                          context,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '暂无打卡记录',
                                        style: SlowlightTypography.secondary(
                                          context,
                                        ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                )
                                : FxCard(
                                  padding: EdgeInsets.zero,
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: _logs.length.clamp(0, 30),
                                    separatorBuilder:
                                        (_, __) => FxSeparator.horizontal(
                                          color: fxDivider(context),
                                          height: 1,
                                        ),
                                    itemBuilder:
                                        (context, index) =>
                                            _logRow(_logs[index], habitColor),
                                  ),
                                ),
                          ],
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(Habit habit, Color habitColor) {
    final largeText =
        MediaQuery.textScalerOf(context).scale(SlowlightTypography.bodySize) >=
        SlowlightTypography.bodySize * 1.5;
    final cards = [
      _StatCard(
        emoji: '🔥',
        value: '${habit.streakCount}',
        label: '连续',
        color: habitColor,
      ),
      _StatCard(
        emoji: '✅',
        value: '$_totalCheckIns',
        label: '总计',
        color: habitColor,
      ),
      _StatCard(
        emoji: '📊',
        value: '${(_completionRate * 100).toStringAsFixed(0)}%',
        label: '完成率',
        color: habitColor,
      ),
    ];
    if (largeText) {
      return Column(
        children: cards
            .map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: card,
              ),
            )
            .toList(growable: false),
      );
    }
    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 10),
        Expanded(child: cards[1]),
        const SizedBox(width: 10),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _logRow(Map<String, dynamic> log, Color habitColor) {
    final checkedAt = DateTime.tryParse(log['occurred_at']?.toString() ?? '')?.toLocal();
    final logDate = habitLogCalendarDay(log);
    final note = log['note'] as String? ?? '';
    final dMin = log['duration_min'] as int? ?? 0;
    final period = log['period'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      checkedAt == null ? '${logDate.month}月${logDate.day}日 · 时间未记录'
                           : _formatDateTime(logDate, checkedAt),
                      style: SlowlightTypography.secondary(context).copyWith(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (log['count_value'] != null)
                       Text('${log['count_value']} ${widget.habit.recordUnit}',
                          style: SlowlightTypography.caption(context)),
                     if (dMin > 0)
                       Text(
                        '$dMin 分钟',
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    if (period.isNotEmpty)
                      Text(
                        _periodLabel(period),
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: SlowlightTypography.secondary(
                      context,
                    ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (widget.habit.allowMultiplePerDay)
             FxIconButton(icon: LucideIcons.trash2,
                tooltip: '撤销这条记录',
                onPressed: () => _deleteLog(log)),
           FxIconButton(
             tooltip: '编辑记录',
            icon: Icons.edit_outlined,
            iconSize: 18,
            onPressed: () => _editLog(log),
          ),
        ],
      ),
    );
  }

  String _periodLabel(String period) {
    const labels = {
      'morning': '☀️ 早晨',
      'afternoon': '🌤 下午',
      'evening': '🌆 傍晚',
      'night': '🌙 晚间',
    };
    return labels[period] ?? '';
  }

  String _formatDateTime(DateTime date, DateTime createdAt) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }
}

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
    return FxCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: SlowlightTypography.hero(context)),
          const SizedBox(height: 8),
          Text(
            value,
            style: SlowlightTypography.pageTitle(
              context,
            ).copyWith(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: SlowlightTypography.caption(
              context,
            ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
