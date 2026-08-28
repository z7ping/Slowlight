import 'package:flutter/material.dart';
import '../../services/api/analytics_api.dart';
import '../../ui/fx.dart';
import '../../theme/app_theme.dart';

class TaskAnalysisTab extends StatefulWidget {
  const TaskAnalysisTab({super.key});
  @override
  State<TaskAnalysisTab> createState() => _TaskAnalysisTabState();
}

class _TaskAnalysisTabState extends State<TaskAnalysisTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _outputStats = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await AnalyticsApi.getOutputStats(period: 'all');
      if (mounted) {
        setState(() {
          _outputStats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError();
    final theme = Theme.of(context);
    final total = _outputStats['total_count'] ?? 0;
    final byLevel = _outputStats['by_level'] as Map<String, dynamic>? ?? {};
    final byTaskType = _outputStats['by_task_type'] as Map<String, dynamic>? ?? {};
    final ms = _outputStats['milestones'] ?? 0;
    final wk = _outputStats['this_week'] ?? 0;
    final mo = _outputStats['this_month'] ?? 0;

    if (total == 0 && wk == 0 && mo == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📊', style: TextStyle(fontSize: 48)),
            Text('数据积累中', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _totalCard(theme, total, wk, mo, ms),
          if (byLevel.isNotEmpty) ...[
            const SizedBox(height: 10),
            _levelCard(theme, byLevel),
          ],
          if (byTaskType.isNotEmpty) ...[
            const SizedBox(height: 10),
            _typeCard(theme, byTaskType),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(color: AppTheme.error)),
          const SizedBox(height: 8),
          FxButton(label: '重试', variant: FxButtonVariant.secondary, onPressed: _load),
        ],
      ),
    );
  }

  Widget _statCol(ThemeData theme, String emoji, String value, String label) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: AppTheme.text2Xl)),
      Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }

  Widget _totalCard(ThemeData theme, int total, int wk, int mo, int ms) {
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Icon(Icons.analytics_outlined, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 6),
          Text('输出记录', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _statCol(theme, '🎯', '$total', '总输出'),
          _statCol(theme, '📅', '$wk', '本周'),
          _statCol(theme, '📆', '$mo', '本月'),
        ]),
        if (ms > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.emoji_events, color: AppTheme.warning),
              Text(' $ms 个里程碑', style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }

  Widget _levelCard(ThemeData theme, Map<String, dynamic> byLevel) {
    final colors = {
      'S': AppTheme.priorityLow,
      'A': AppTheme.success,
      'B': AppTheme.warning,
      'C': AppTheme.error,
    };
    final mx = byLevel.values.fold<int>(0, (a, b) => (b as int) > a ? b : a).toDouble();
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Text('输出等级分布', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...['S', 'A', 'B', 'C'].map((level) {
          final count = (byLevel[level] ?? 0) as int;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 36, child: Text('$level 级', style: theme.textTheme.bodySmall)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: mx > 0 ? count / mx : 0,
                    minHeight: 16,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: colors[level],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 30, child: Text('$count', style: theme.textTheme.bodySmall)),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _typeCard(ThemeData theme, Map<String, dynamic> byTaskType) {
    final names = {'main': '主线', 'branch': '分支', 'daily': '日常', 'explore': '探索'};
    return FxCard(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Text('任务类型分布', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: byTaskType.entries
              .map((e) => Chip(
                    label: Text('${names[e.key] ?? e.key}: ${e.value}'),
                    visualDensity: VisualDensity.compact,
                  ))
              .toList(),
        ),
      ]),
    );
  }
}
