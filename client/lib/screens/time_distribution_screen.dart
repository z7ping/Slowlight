import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/api/analytics_api.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

const _chartColors = [
  AppTheme.chartGreen,
  AppTheme.chartBlue,
  AppTheme.chartYellow,
  AppTheme.chartRed,
  AppTheme.chartPurple,
  AppTheme.chartCyan,
];

enum TimeDistributionDestination { focus, tags }

class TimeDistributionScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function()? dataLoader;
  final Future<void> Function(TimeDistributionDestination)? onNavigate;
  final bool titleProvidedByShell;

  const TimeDistributionScreen({
    super.key,
    this.dataLoader,
    this.onNavigate,
    this.titleProvidedByShell = false,
  });

  @override
  State<TimeDistributionScreen> createState() => _TimeDistributionScreenState();
}

class _TimeDistributionScreenState extends State<TimeDistributionScreen> {
  bool _loading = true;
  bool _loadError = false;
  bool _hasLoaded = false;
  int _loadVersion = 0;
  bool _showAllTags = false;
  Map<String, dynamic> _data = {};

  Future<void> _openDestination(TimeDistributionDestination destination) async {
    final navigate = widget.onNavigate;
    if (navigate == null) return;
    await navigate(destination);
    // A finished focus session may have created new facts while this page
    // stayed mounted behind the dedicated Pomodoro route.
    if (mounted && destination == TimeDistributionDestination.focus) {
      await _loadData();
    }
  }

  int? _todayMinutes() {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final rows = _data['by_day'];
    if (rows is! List) return null;
    for (final row in rows.whereType<Map>()) {
      if (row['date'] != date) continue;
      final seconds = row['work_seconds'];
      if (seconds is num) return seconds.toInt() ~/ 60;
      final minutes = row['total_min'];
      return minutes is num ? minutes.toInt() : null;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        // Keep confirmed time-allocation facts visible while refreshing.
        _loading = !_hasLoaded;
        _loadError = false;
      });
    }
    try {
      final data = await (widget.dataLoader?.call() ??
          AnalyticsApi.getTimeDistribution());
      // A missing field or malformed response is unknown, never zero.
      if (data['total_min'] is! num ||
          data['tags'] is! List ||
          data['by_day'] is! List) {
        throw const FormatException('时间分配来源未返回完整数据');
      }
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _data = data;
        _hasLoaded = true;
        _loading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoaded) return const Center(child: FxCircularProgress());
    if (_loadError && !_hasLoaded) {
      return Center(
        child: FxEmptyState(
          icon: LucideIcons.triangleAlert,
          title: '时间分配暂时不可用',
          subtitle: '数据读取失败，请稍后重试。',
          action: FxButton(
            label: '重新加载',
            variant: FxButtonVariant.secondary,
            onPressed: _loadData,
          ),
        ),
      );
    }
    final totalMin = (_data['total_min'] as num).toInt();
    final tags =
        (_data['tags'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

    return FxRefresh(
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
                            Text(
                              widget.titleProvidedByShell
                                  ? '专注时间分配'
                                  : '时间分配',
                              style: widget.titleProvidedByShell
                                  ? SlowlightTypography.cardTitle(context)
                                  : SlowlightTypography.pageTitle(context),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '近 7 天 · 按标签和日期回看真实专注',
                              style: SlowlightTypography.secondary(
                                context,
                              ).copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FxIconButton(
                        icon: LucideIcons.refreshCw,
                        tooltip: '刷新',
                        iconSize: 17,
                        onPressed: _loadData,
                      ),
                    ],
                  ),
                  if (_loadError) ...[
                    FxCard(
                      padding: const EdgeInsets.all(12),
                      expanded: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '时间分配刷新未确认，以下为上次已载入记录。',
                              style: SlowlightTypography.secondary(context),
                            ),
                          ),
                          FxButton(
                            label: '重新加载',
                            size: FxButtonSize.sm,
                            variant: FxButtonVariant.ghost,
                            onPressed: _loadData,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 14),
                  _stats(totalMin, tags.length),
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
                            if (widget.onNavigate != null) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FxButton(
                                  label: '进入专注',
                                  onPressed: () => unawaited(
                                    _openDestination(TimeDistributionDestination.focus),
                                  ),
                                ),
                              ),
                            ],
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

  Widget _stats(int totalMin, int tagCount) {
    final desktop = ResponsiveLayout.isDesktopOrWider(context);
    final todayMinutes = _todayMinutes();
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final minCellWidth = desktop
            ? (190 + (textScale - 1) * 50).clamp(190, 240).toDouble()
            : (140 + (textScale - 1) * 50).clamp(140, 190).toDouble();
        final cellWidth = (constraints.maxWidth - 10) / 2;
        final stacked = cellWidth < minCellWidth;
        final cells = [
          FxStatCell(
            value: desktop ? '$totalMin' : (todayMinutes?.toString() ?? '—'),
            label: desktop ? '总专注时长' : '今日已记录专注',
            suffix: ' 分钟',
          ),
          FxStatCell(
            value: desktop ? '$tagCount' : (tagCount == 0 ? '—' : '$tagCount'),
            label: desktop ? '覆盖分类' : '可确认的分类',
            suffix: desktop ? ' 个' : null,
          ),
        ];

        Widget cell(int index) {
          final child = cells[index];
          if (desktop || widget.onNavigate == null) return child;
          final destination = index == 0
              ? TimeDistributionDestination.focus
              : TimeDistributionDestination.tags;
          return FxInkWell(
            key: ValueKey('timedist.kpi.${destination.name}'),
            borderRadius: BorderRadius.circular(SlowlightRadius.lg),
            onTap: () => unawaited(_openDestination(destination)),
            child: Semantics(button: true, child: child),
          );
        }

        if (stacked) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: cell(0)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: cell(1)),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cell(0)),
            const SizedBox(width: 10),
            Expanded(child: cell(1)),
          ],
        );
      },
    );
  }

  Widget _distributionCard(List<Map<String, dynamic>> source) {
    final theme = Theme.of(context);
    final tags = [...source]..sort(
      (a, b) => ((b['total_min'] as num?)?.toInt() ?? 0).compareTo(
        (a['total_min'] as num?)?.toInt() ?? 0,
      ),
    );

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '标签分布'),
          const SizedBox(height: 14),
          if (tags.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  _data['total_min'] is num && (_data['total_min'] as num) > 0
                      ? '当前专注尚无可确认的分类'
                      : '暂无专注数据',
                  style: SlowlightTypography.secondary(
                    context,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                constraints: const BoxConstraints(minHeight: 44),
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
                        style: SlowlightTypography.secondary(context),
                      ),
                    ),
                    Text(
                      '${percent.toStringAsFixed(0)}%',
                      style: SlowlightTypography.caption(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600, color: color),
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
    final byDay =
        (_data['by_day'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
    final maxMin = byDay.fold<int>(
      0,
      (max, item) => math.max(max, (item['total_min'] as num?)?.toInt() ?? 0),
    );

    return FxCard(
      padding: const EdgeInsets.all(16),
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '每日专注'),
          const SizedBox(height: 14),
          if (byDay.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  '暂无每日记录',
                  style: SlowlightTypography.secondary(
                    context,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                      width: 54,
                      child: Text(
                        _weekdayLabel(day['date']?.toString() ?? ''),
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: FxProgress(
                        value: ratio.clamp(0, 1).toDouble(),
                        height: 8,
                        backgroundColor: theme.colorScheme.outlineVariant,
                        color: activePalette.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        min > 0 ? '$min 分钟 · $count 次' : '—',
                        textAlign: TextAlign.right,
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: theme.colorScheme.onSurfaceVariant),
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
          fontSize: SlowlightTypography.sectionTitleSize,
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
        style: TextStyle(fontSize: SlowlightTypography.captionSize, color: secondaryTextColor),
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
