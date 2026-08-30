import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../reflection_composer.dart';

/// 四维度是固定产品坐标，不再用 SystemTag ID 充当维度身份。
class Dimension {
  final String key;
  final String name;
  final String icon;
  final String color;
  final int value;
  final int total;
  final String unit;
  final String trend;
  final String trendDesc;
  final String lastRecord;
  final int? id;

  Dimension({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.value,
    required this.total,
    required this.unit,
    required this.trend,
    required this.trendDesc,
    required this.lastRecord,
    this.id,
  });

  factory Dimension.fromJson(Map<String, dynamic> json) {
    return Dimension(
      key: json['key'] as String? ?? '',
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? '◌',
      color: json['color'] as String? ?? '#1890ff',
      value: (json['value'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      unit: json['unit'] as String? ?? '',
      trend: json['trend'] as String? ?? 'flat',
      trendDesc: json['trend_desc'] as String? ?? '',
      lastRecord: json['last_record'] as String? ?? '',
    );
  }
}

class DimensionSummaryCard extends StatelessWidget {
  final List<Dimension> dimensions;
  final ValueChanged<Dimension>? onDimensionTap;
  final ValueChanged<Dimension>? onAddRecord;
  final VoidCallback? onCreateTag;

  const DimensionSummaryCard({
    super.key,
    required this.dimensions,
    this.onDimensionTap,
    this.onAddRecord,
    this.onCreateTag,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar_outlined, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '四维近况',
                  style: SlowlightTypography.cardTitle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '本周',
                style: SlowlightTypography.caption(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (dimensions.isEmpty)
            Text(
              '还没有可用的维度数据。',
              style: SlowlightTypography.secondary(context).copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...dimensions.map((dim) => _buildItem(context, dim)),
          if (dimensions.isNotEmpty) ...[
            const SizedBox(height: 8),
            FxButton(
              label: '写下一个观察',
              icon: Icons.edit_outlined,
              variant: FxButtonVariant.ghost,
              size: FxButtonSize.sm,
              onPressed: () => ReflectionComposer.show(
                context,
                entryType: 'observation',
                prompt: '今天有什么值得留下的观察？',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, Dimension dim) {
    final theme = Theme.of(context);
    final color = _parseColor(dim.color);
    return FxInkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onDimensionTap?.call(dim),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(dim.icon, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dim.name,
                style: SlowlightTypography.secondary(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${dim.value}${dim.unit.isEmpty ? '' : ' ${dim.unit}'}',
              style: SlowlightTypography.secondary(context).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              _trendIcon(dim.trend),
              size: 18,
              color: _trendColor(context, dim.trend),
            ),
            const SizedBox(width: 2),
            FxIconButton(
              icon: Icons.edit_outlined,
              iconSize: 16,
              tooltip: '记录关于${dim.name}的观察',
              onPressed: () => ReflectionComposer.show(
                context,
                entryType: 'observation',
                dimensionKey: dim.key,
                prompt: '关于「${dim.name}」，此刻你自己观察到了什么？',
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _trendIcon(String trend) {
    if (trend == 'up') return Icons.arrow_upward;
    if (trend == 'down') return Icons.arrow_downward;
    return Icons.arrow_forward;
  }

  Color _trendColor(BuildContext context, String trend) {
    if (trend == 'up') return AppTheme.success;
    if (trend == 'down') return Theme.of(context).colorScheme.error;
    return Theme.of(context).colorScheme.outline;
  }

  Color _parseColor(String value) {
    try {
      var hex = value.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return AppTheme.info;
    }
  }
}
