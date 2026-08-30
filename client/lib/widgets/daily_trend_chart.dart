import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../ui/app_theme.dart';
import '../ui/fx.dart';

/// 每日趋势折线图
class DailyTrendChart extends StatefulWidget {
  const DailyTrendChart({super.key});

  @override
  State<DailyTrendChart> createState() => _DailyTrendChartState();
}

class _DailyTrendChartState extends State<DailyTrendChart> {
  bool _loading = true;
  List<Map<String, dynamic>> _days = [];
  String _metric = 'focus_minutes';

  static const _metrics = {
    'focus_minutes': {'label': '专注分钟', 'color': Color(0xFF52C41A)},
    'task_completed': {'label': '完成任务', 'color': Color(0xFF1890FF)},
    'completion_rate': {'label': '完成率%', 'color': Color(0xFFFAAD14)},
    'habit_checked': {'label': '习惯打卡', 'color': Color(0xFFFF6B6B)},
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final days = await ApiService.getDailyTrend(days: 7);
      if (mounted) {
        setState(() {
          _days = days;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FxCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '最近 7 天趋势',
                style: SlowlightTypography.cardTitle(
                  context,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  _metrics.entries.map((entry) {
                    final selected = _metric == entry.key;
                    final color = entry.value['color'] as Color;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FxChip(
                        label: entry.value['label'] as String,
                        variant:
                            selected
                                ? FxChipVariant.primary
                                : FxChipVariant.outline,
                        backgroundColor: selected ? color : Colors.transparent,
                        foregroundColor:
                            selected
                                ? AppTheme.white
                                : theme.colorScheme.onSurfaceVariant,
                        onTap: () => setState(() => _metric = entry.key),
                      ),
                    );
                  }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const SizedBox(
              height: 120,
              child: Center(child: FxCircularProgress()),
            )
          else if (_days.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  '数据积累中',
                  style: SlowlightTypography.secondary(
                    context,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            SizedBox(height: 150, child: _buildChart(theme)),
        ],
      ),
    );
  }

  Widget _buildChart(ThemeData theme) {
    final values = _days.map((d) => (_getMetricValue(d)).toDouble()).toList();
    if (values.isEmpty) return const SizedBox.shrink();
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final chartMax = maxVal > 0 ? maxVal : 1.0;
    final color = _metrics[_metric]!['color'] as Color;

    return CustomPaint(
      painter: _TrendLinePainter(
        values: values,
        maxValue: chartMax,
        color: color,
        labels: _days.map((d) => d['date'] as String).toList(),
        theme: theme,
      ),
      size: const Size(double.infinity, 150),
    );
  }

  int _getMetricValue(Map<String, dynamic> d) {
    switch (_metric) {
      case 'focus_minutes':
        return d['focus_minutes'] ?? 0;
      case 'task_completed':
        return d['task_completed'] ?? 0;
      case 'completion_rate':
        return d['completion_rate'] ?? 0;
      case 'habit_checked':
        return d['habit_checked'] ?? 0;
      default:
        return 0;
    }
  }
}

class _TrendLinePainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final Color color;
  final List<String> labels;
  final ThemeData theme;

  _TrendLinePainter({
    required this.values,
    required this.maxValue,
    required this.color,
    required this.labels,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final padding = const EdgeInsets.only(
      left: 8,
      right: 8,
      top: 16,
      bottom: 28,
    );
    final chartW = size.width - padding.left - padding.right;
    final chartH = size.height - padding.top - padding.bottom;
    final pointCount = values.length;
    final stepX = pointCount > 1 ? chartW / (pointCount - 1) : 0.0;

    final gridPaint =
        Paint()
          ..color = theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
          ..strokeWidth = 0.5;
    for (int i = 0; i < 4; i++) {
      final y = padding.top + chartH * i / 3;
      canvas.drawLine(
        Offset(padding.left, y),
        Offset(size.width - padding.right, y),
        gridPaint,
      );
    }

    final linePaint =
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

    final path = Path();
    final points = <Offset>[];
    for (int i = 0; i < pointCount; i++) {
      final x = padding.left + stepX * i;
      final y = padding.top + chartH * (1 - values[i] / maxValue);
      points.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final fillPath =
        Path.from(path)
          ..lineTo(points.last.dx, padding.top + chartH)
          ..lineTo(points.first.dx, padding.top + chartH)
          ..close();
    final fillPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.2),
              color.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(0, padding.top, size.width, chartH));
    canvas.drawPath(fillPath, fillPaint);

    final dotPaint = Paint()..color = color;
    final dotBorderPaint =
        Paint()
          ..color = AppTheme.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
    for (final point in points) {
      canvas.drawCircle(point, 4, dotBorderPaint);
      canvas.drawCircle(point, 3, dotPaint);
    }

    final textStyle = TextStyle(
      fontSize: AppTheme.textXs,
      height: 1.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    for (int i = 0; i < pointCount; i++) {
      final x = padding.left + stepX * i;
      final label = labels[i].length >= 10 ? labels[i].substring(5) : labels[i];
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, padding.top + chartH + 6));
    }

    final valueStyle = TextStyle(
      fontSize: AppTheme.textXs,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: color,
    );
    for (int i = 0; i < pointCount; i++) {
      if (values[i] == 0) continue;
      final point = points[i];
      final tp = TextPainter(
        text: TextSpan(text: values[i].toInt().toString(), style: valueStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(point.dx - tp.width / 2, point.dy - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter old) {
    if (old.color != color || old.maxValue != maxValue) return true;
    if (old.values.length != values.length) return true;
    for (int i = 0; i < values.length; i++) {
      if (old.values[i] != values[i]) return true;
    }
    return false;
  }
}
