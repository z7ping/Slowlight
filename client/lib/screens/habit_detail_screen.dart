import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../utils/color_utils.dart';
import '../widgets/habit_heatmap.dart';

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
      final data = await ApiService.getHabitLogs(
        widget.habit.id,
        month: monthStr,
      );
      final logs =
          (data['logs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final uniqueDays =
          logs
              .map((log) => DateTime.parse(log['created_at'] as String))
              .map(
                (d) =>
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
              )
              .toSet()
              .length;

      if (!mounted) return;
      setState(() {
        _logs = logs;
        _totalCheckIns = logs.length;
        _completionRate = daysInMonth > 0 ? uniqueDays / daysInMonth : 0;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
            ? await showModalBottomSheet<Map<String, dynamic>>(
              context: context,
              isScrollControlled: true,
              builder:
                  (sheetContext) => Padding(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final habitColor = ColorUtils.safeParse(habit.color);
    final checkInDates =
        _logs
            .map((log) => DateTime.parse(log['created_at'] as String))
            .toList();

    return Scaffold(
      backgroundColor: AppTheme.warmWhite,
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
                                color: AppTheme.warmDark,
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
                                        ).copyWith(color: AppTheme.warmGray500),
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
                                          color: AppTheme.warmBorder,
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
    final checkedAt = DateTime.parse(log['created_at'] as String);
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
                      _formatDateTime(checkedAt),
                      style: SlowlightTypography.secondary(context).copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppTheme.warmDark,
                      ),
                    ),
                    if (dMin > 0)
                      Text(
                        '$dMin 分钟',
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: AppTheme.warmGray500),
                      ),
                    if (period.isNotEmpty)
                      Text(
                        _periodLabel(period),
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: AppTheme.warmGray500),
                      ),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: SlowlightTypography.secondary(
                      context,
                    ).copyWith(color: AppTheme.warmGray500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
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

  String _formatDateTime(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
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
            ).copyWith(color: AppTheme.warmGray500),
          ),
        ],
      ),
    );
  }
}
