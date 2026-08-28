import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/api/analytics_api.dart';
import '../theme/app_theme.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';

const _chartColors = [
  AppTheme.chartGreen,
  AppTheme.chartBlue,
  AppTheme.chartYellow,
  AppTheme.chartRed,
  AppTheme.chartPurple,
  AppTheme.chartCyan,
];

class TimeDistributionScreen extends StatefulWidget {
  const TimeDistributionScreen({super.key});

  @override
  State<TimeDistributionScreen> createState() => _TimeDistributionScreenState();
}

class _TimeDistributionScreenState extends State<TimeDistributionScreen> {
  bool _loading = true;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await AnalyticsApi.getTimeDistribution();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final totalMin = (_data['total_min'] as num?)?.toInt() ?? 0;
    final tags = (_data['tags'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 72),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '时间分配',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '最近 7 天 · 看见时间实际流向了哪里',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: '刷新',
                          onPressed: _loadData,
                          icon: const Icon(LucideIcons.refreshCw, size: 17),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: HfStatCell(
                          value: '$totalMin',
                          label: '总专注时长',
                          suffix: ' 分钟',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: HfStatCell(
                          value: '${tags.length}',
                          label: '覆盖分类',
                          suffix: ' 个',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 700;
                      final pie = _distributionCard(tags);
                      final daily = _dailyCard();
                      if (!wide) {
                        return Column(
                          children: [
                            pie,
                            const SizedBox(height: 14),
                            daily,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: pie),
                          const SizedBox(width: 14),
                          Expanded(child: daily),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _distributionCard(List<Map<String, dynamic>> source) {
    final theme = Theme.of(context);
    final tags = [...source]..sort(
        (a, b) => ((b['total_min'] as num?)?.toInt() ?? 0)
            .compareTo((a['total_min'] as num?)?.toInt() ?? 0),
      );

    return HfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HfSectionHeader(title: '维度分布'),
          const SizedBox(height: 14),
          if (tags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  '暂无专注数据',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  painter: _PieChartPainter(
                    values: tags
                        .map<double>(
                          (item) =>
                              (item['total_min'] as num?)?.toDouble() ?? 0,
                        )
                        .toList(growable: false),
                    colors: List.generate(
                      tags.length,
                      (index) => _chartColors[index % _chartColors.length],
                    ),
                    textColor: theme.colorScheme.onSurface,
                    secondaryTextColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ...tags.take(6).toList().asMap().entries.map((entry) {
              final tag = entry.value;
              final color = _chartColors[entry.key % _chartColors.length];
              final percent = (tag['percent'] as num?)?.toDouble() ?? 0;
              return Container(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tag['name']?.toString() ?? '未分类',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: AppTheme.textXs,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _dailyCard() {
    final theme = Theme.of(context);
    final byDay = (_data['by_day'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final maxMin = byDay.fold<int>(
      0,
      (max, item) => math.max(
        max,
        (item['total_min'] as num?)?.toInt() ?? 0,
      ),
    );

    return HfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HfSectionHeader(title: '每日专注'),
          const SizedBox(height: 14),
          if (byDay.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  '暂无每日记录',
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...byDay.map((day) {
              final min = (day['total_min'] as num?)?.toInt() ?? 0;
              final count = (day['work_count'] as num?)?.toInt() ?? 0;
              final ratio = maxMin > 0 ? min / maxMin : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        _weekdayLabel(day['date']?.toString() ?? ''),
                        style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: hfDivider(context),
                          color: activePalette.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: Text(
                        min > 0 ? '$min 分钟 · $count 次' : '—',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _weekdayLabel(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final current = DateTime(date.year, date.month, date.day);
      if (current == today) return '今天';
      if (current == today.subtract(const Duration(days: 1))) return '昨天';
      return '周${weekdays[date.weekday - 1]}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _PieChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color textColor;
  final Color secondaryTextColor;

  _PieChartPainter({
    required this.values,
    required this.colors,
    required this.textColor,
    required this.secondaryTextColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final innerRadius = radius * .58;
    var startAngle = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < values.length; index++) {
      if (values[index] <= 0) continue;
      final sweepAngle = values[index] / total * 2 * math.pi;
      paint.color = colors[index % colors.length];
      final path = Path();
      path.moveTo(
        center.dx + radius * math.cos(startAngle),
        center.dy + radius * math.sin(startAngle),
      );
      path.arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
      );
      path.lineTo(
        center.dx + innerRadius * math.cos(startAngle + sweepAngle),
        center.dy + innerRadius * math.sin(startAngle + sweepAngle),
      );
      path.arcTo(
        Rect.fromCircle(center: center, radius: innerRadius),
        startAngle + sweepAngle,
        -sweepAngle,
        false,
      );
      path.close();
      canvas.drawPath(path, paint);
      startAngle += sweepAngle;
    }

    final valuePainter = TextPainter(
      text: TextSpan(
        text: '${total.toInt()}',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    valuePainter.paint(
      canvas,
      Offset(
        center.dx - valuePainter.width / 2,
        center.dy - valuePainter.height / 2 - 6,
      ),
    );

    final unitPainter = TextPainter(
      text: TextSpan(
        text: '分钟',
        style: TextStyle(fontSize: 12, color: secondaryTextColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitPainter.paint(
      canvas,
      Offset(center.dx - unitPainter.width / 2, center.dy + 8),
    );
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.values.toString() != values.toString() ||
      oldDelegate.textColor != textColor ||
      oldDelegate.secondaryTextColor != secondaryTextColor;
}
