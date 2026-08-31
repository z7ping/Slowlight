import 'package:flutter/material.dart';

import '../services/api/analytics_api.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// 可嵌入的时间分布组件（无 Scaffold/AppBar）
class TimeDistributionEmbed extends StatefulWidget {
  final bool dense;
  const TimeDistributionEmbed({super.key, this.dense = false});

  @override
  State<TimeDistributionEmbed> createState() => _TimeDistributionEmbedState();
}

class _TimeDistributionEmbedState extends State<TimeDistributionEmbed> {
  bool _loading = true;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await AnalyticsApi.getTimeDistribution();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: FxCircularProgress(strokeWidth: 2));
    }
    final totalMin = (_data['total_min'] as num?)?.toInt() ?? 0;
    final tags =
        (_data['tags'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final byDay =
        (_data['by_day'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    if (tags.isEmpty) {
      return Center(
        child: Text(
          '暂无专注数据',
          style: SlowlightTypography.secondary(
            context,
          ).copyWith(color: AppTheme.warmGray400),
        ),
      );
    }
    final h = (totalMin / 60).floor();
    final m = totalMin % 60;
    final pad = widget.dense ? 12.0 : 16.0;

    return FxRefresh(
      onRefresh: _loadData,
      color: AppTheme.primary,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 92),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  '近 7 天总投入',
                  style: TextStyle(
                    fontSize: SlowlightTypography.buttonSize,
                    color: AppTheme.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  h > 0 ? '$h 小时 $m 分钟' : '$m 分钟',
                  style: const TextStyle(
                    fontSize: SlowlightTypography.sectionTitleSize,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '覆盖 ${tags.length} 个维度',
                  style: const TextStyle(
                    fontSize: SlowlightTypography.captionSize,
                    color: AppTheme.white60,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '时间分布',
                  style: SlowlightTypography.secondary(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warmDark,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: CustomPaint(
                      painter: _PieChartPainter(
                        tags: tags,
                        totalMin: totalMin,
                        colors: [
                          AppTheme.primary,
                          AppTheme.success,
                          AppTheme.warning,
                          AppTheme.priorityHigh,
                          AppTheme.warmGray400,
                          AppTheme.warmGray300,
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...tags.asMap().entries.map((entry) {
                  final tag = entry.value;
                  final color =
                      [
                        AppTheme.primary,
                        AppTheme.success,
                        AppTheme.warning,
                        AppTheme.priorityHigh,
                        AppTheme.warmGray400,
                        AppTheme.warmGray300,
                      ][entry.key % 6];
                  final percent = (tag['percent'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${tag['icon'] ?? ''} ${tag['name'] ?? ''}',
                          style: SlowlightTypography.secondary(
                            context,
                          ).copyWith(color: AppTheme.warmDark),
                        ),
                        const Spacer(),
                        Text(
                          '${percent.toStringAsFixed(0)}%',
                          style: SlowlightTypography.secondary(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600, color: color),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (byDay.isNotEmpty)
            FxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '每日明细',
                    style: SlowlightTypography.secondary(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warmDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...byDay.map((day) {
                    final dayMin = (day['total_min'] as num?)?.toInt() ?? 0;
                    final workCount = (day['work_count'] as num?)?.toInt() ?? 0;
                    final pct = totalMin > 0 ? dayMin / totalMin : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              _weekdayLabel(day['date'] ?? ''),
                              style: SlowlightTypography.caption(
                                context,
                              ).copyWith(color: AppTheme.warmGray500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FxProgress(
                              value: pct,
                              height: 6,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 55,
                            child: Text(
                              '${dayMin}分钟',
                              style: SlowlightTypography.caption(
                                context,
                              ).copyWith(color: AppTheme.warmGray500),
                              textAlign: TextAlign.end,
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '$workCount次',
                              style: SlowlightTypography.caption(
                                context,
                              ).copyWith(color: AppTheme.warmGray400),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _weekdayLabel(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
      if (diff == 0) return '今天';
      if (diff == 1) return '昨天';
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return weekdays[d.weekday - 1];
    } catch (e) {
      return dateStr;
    }
  }
}

class _PieChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> tags;
  final int totalMin;
  final List<Color> colors;

  _PieChartPainter({
    required this.tags,
    required this.totalMin,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const innerRadius = 55.0;
    double startAngle = -3.1415926535897932 / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < tags.length; i++) {
      final pct = (tags[i]['percent'] as num?)?.toDouble() ?? 0;
      final sweepAngle = (pct / 100) * 2 * 3.1415926535897932;
      paint.color = colors[i % colors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      startAngle += sweepAngle;
    }

    paint.color = AppTheme.warmWhite;
    canvas.drawCircle(center, innerRadius, paint);

    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: '$totalMin',
        style: TextStyle(
          fontSize: SlowlightTypography.sectionTitleSize,
          fontWeight: FontWeight.bold,
          color: AppTheme.warmDark,
        ),
        children: [
          TextSpan(
            text: '\n分钟',
            style: TextStyle(
              fontSize: SlowlightTypography.captionSize,
              fontWeight: FontWeight.normal,
              color: AppTheme.warmGray500,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
