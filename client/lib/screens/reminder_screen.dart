import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import 'settings_screen.dart';

/// 桌面休息提醒：运行态、今日统计、系统规则与全屏休息遮罩。
class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  final ReminderService _service = ReminderService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    if (!_service.isLoaded) _service.loadAll();
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(initialSection: 'rest'),
      ),
    );
    if (!_service.isLoaded) await _service.loadAll();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final resting =
        _service.state == 'micro_rest' || _service.state == 'long_rest';
    return Scaffold(
      body: SafeArea(
        child:
            resting
                ? _fullscreenRest()
                : Column(
                  children: [
                    FxPageHeader(
                      title: '休息提醒',
                      actionIcon: LucideIcons.settings,
                      actionTooltip: '提醒设置',
                      onAction: _openSettings,
                    ),
                    Expanded(child: _runtime()),
                  ],
                ),
      ),
    );
  }

  Widget _runtime() {
    final theme = Theme.of(context);
    final working = _service.state == 'working';
    final total = _service.totalSeconds;
    final progress =
        total <= 0
            ? 0.0
            : (1 - _service.remainingSeconds / total).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                FxChip(
                  label:
                      working
                          ? '● 工作中 · 第 ${_service.cycleCount + 1} 轮'
                          : '● 待机',
                  backgroundColor:
                      working
                          ? activePalette.accent.withValues(alpha: .12)
                          : fxSubtleSurface(context),
                  foregroundColor:
                      working
                          ? activePalette.accent
                          : theme.colorScheme.onSurfaceVariant,
                  borderRadius: 999,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 150,
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: FxCircularProgress(
                          value: progress,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          backgroundColor: theme.colorScheme.surfaceContainer,
                          color: AppTheme.success,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _format(_service.remainingSeconds),
                            style: SlowlightTypography.hero(
                              context,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            working
                                ? '距小憩 · 小憩 ${_service.microRestCount}/${_service.microRestsBeforeLong}'
                                : '还未开始',
                            textAlign: TextAlign.center,
                            style: SlowlightTypography.caption(
                              context,
                            ).copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!working)
                      FxButton(
                        label: '开始工作',
                        icon: LucideIcons.play,
                        size: FxButtonSize.sm,
                        onPressed: _service.startWork,
                      )
                    else
                      FxButton(
                        label: '开始小憩',
                        icon: LucideIcons.coffee,
                        size: FxButtonSize.sm,
                        onPressed: _service.forceRest,
                      ),
                    FxButton(
                      label: '延后 5 分钟',
                      variant: FxButtonVariant.outline,
                      size: FxButtonSize.sm,
                      onPressed: working ? _postponeUpcoming : null,
                    ),
                    FxButton(
                      label: '跳过本轮',
                      variant: FxButtonVariant.ghost,
                      size: FxButtonSize.sm,
                      onPressed: working ? _skipUpcoming : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _todayStats(),
                const SizedBox(height: 12),
                _systemRules(),
                const SizedBox(height: 10),
                Text(
                  '每轮工作 / 小憩 / 跳过都记录为事实 · 在「回顾 → 休息数据」中查看',
                  textAlign: TextAlign.center,
                  style: SlowlightTypography.caption(
                    context,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _postponeUpcoming() {
    // 当前服务的延后动作只接受“已进入休息”的状态；这里先进入当前小憩，
    // 再立即执行延后，保持 UI 操作与既有状态机一致。
    _service.forceRest();
    _service.postponeRest();
    _message('已延后 5 分钟');
  }

  void _skipUpcoming() {
    _service.forceRest();
    _service.skipRest();
    _message('已跳过本轮');
  }

  Widget _todayStats() {
    final theme = Theme.of(context);
    final workMinutes = _service.todayWorkSeconds ~/ 60;
    final restMinutes = _service.todayRestSeconds ~/ 60;
    final skipRate = (_service.todaySkipRate * 100).round();
    return FxCard(
      padding: const EdgeInsets.all(12),
      color: fxSurface(context),
      borderRadius: AppTheme.radiusLg,
      border: Border.all(color: fxBorder(context)),
      boxShadow:
          theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FxSectionHeader(title: '今日统计', trailing: '→ 写入行为事件'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final scaled = MediaQuery.textScalerOf(
                context,
              ).scale(SlowlightTypography.bodySize);
              final columns =
                  scaled >= SlowlightTypography.bodySize * 1.3
                      ? 1
                      : constraints.maxWidth < 420
                      ? 2
                      : 4;
              final width =
                  (constraints.maxWidth - 6 * (columns - 1)) / columns;
              final cells = [
                FxStatCell(value: _duration(workMinutes), label: '工作'),
                FxStatCell(value: '$restMinutes', suffix: '分', label: '休息'),
                FxStatCell(value: '$skipRate%', label: '跳过率'),
                FxStatCell(
                  value: '${_service.todayLongestNoSkipStreak}',
                  label: '连续不跳过',
                ),
              ];
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: cells
                    .map((cell) => SizedBox(width: width, child: cell))
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _systemRules() {
    final theme = Theme.of(context);
    Widget rule(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: SlowlightTypography.secondary(
                context,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );

    return FxCard(
      padding: const EdgeInsets.all(12),
      color: fxSurface(context),
      borderRadius: AppTheme.radiusLg,
      border: Border.all(color: fxBorder(context)),
      boxShadow:
          theme.brightness == Brightness.light ? AppTheme.cardShadow : null,
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '系统行为规则',
                style: SlowlightTypography.secondary(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              FxChip(
                label: '新增需求',
                backgroundColor: fxSubtleSurface(context),
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                borderRadius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          rule(LucideIcons.monitor, '仅桌面端 · 休息默认霸屏全屏接管'),
          rule(LucideIcons.moon, '电脑睡眠 → 计时自动暂停，休眠时长不计入工作'),
          rule(LucideIcons.lock, '锁屏 → 重置本轮计时，解锁后从零开始'),
        ],
      ),
    );
  }

  Widget _fullscreenRest() {
    final strict = _service.isCurrentRestStrict;
    final micro = _service.state == 'micro_rest';
    final total = _service.totalSeconds;
    final progress =
        total <= 0
            ? 0.0
            : (1 - _service.remainingSeconds / total).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 18,
            child: Text(
              micro ? '小憩' : '长休息',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: AppTheme.textXs,
                letterSpacing: 3,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 190,
                    height: 190,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: FxCircularProgress(
                            value: progress,
                            strokeWidth: 9,
                            strokeCap: StrokeCap.round,
                            backgroundColor: Colors.white.withValues(
                              alpha: .14,
                            ),
                            color: const Color(0xFF4ADE80),
                          ),
                        ),
                        Text(
                          _format(_service.remainingSeconds),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    micro ? '眨眨眼，看看六米外的地方' : '离开屏幕，活动一下身体',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 18),
                  if (!strict)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_service.isCurrentRestPostponeAllowed)
                          FxButton(
                            label: '延后 5 分钟',
                            variant: FxButtonVariant.outline,
                            size: FxButtonSize.sm,
                            onPressed: _service.postponeRest,
                          ),
                        FxButton(
                          label: '跳过',
                          variant: FxButtonVariant.ghost,
                          size: FxButtonSize.sm,
                          onPressed: _service.skipRest,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 14,
            child: Text(
              strict ? '严格模式 · 不可跳过' : '非严格模式',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: AppTheme.textXs,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _format(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _duration(int minutes) {
    if (minutes < 60) return '$minutes 分';
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(minutes % 60 == 0 ? 0 : 1)} 小时';
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
    );
  }
}
