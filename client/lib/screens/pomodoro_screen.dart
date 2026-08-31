import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/task.dart';
import '../repositories/session_repository.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/system_tag_picker.dart';

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with SingleTickerProviderStateMixin {
  final SessionRepository _sessions = SessionRepository();

  int _workMinutes = 25;
  int _breakMinutes = 5;
  int _longBreakMinutes = 15;
  int _sessionsBeforeLong = 4;
  bool _autoStartNext = true;
  bool _soundEnabled = true;
  int? _linkedTaskId;
  List<Task> _todayTasks = const [];

  Timer? _timer;
  int _remainingSeconds = 25 * 60;
  String _sessionType = 'work';
  bool _running = false;
  bool _activeSession = false;
  int _completedSessions = 0;
  int _todayWorkSeconds = 0;
  int _todayWorkCount = 0;
  String? _completionMessage;
  late final AnimationController _ripple;

  @override
  void initState() {
    super.initState();
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadTodayStats();
    _loadTodayTasks();
    _restoreActiveSession();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ripple.dispose();
    super.dispose();
  }

  Future<void> _loadTodayStats() async {
    try {
      final stats = await _sessions.getTodaySessionStats();
      if (!mounted) return;
      setState(() {
        _todayWorkSeconds = (stats['total_work_seconds'] as num?)?.toInt() ?? 0;
        _todayWorkCount = (stats['work_count'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _loadTodayTasks() async {
    try {
      final tasks = await DataService().getTodayTasks();
      if (!mounted) return;
      setState(() {
        _todayTasks = tasks.where((task) => !task.isCompleted).toList();
        if (_linkedTaskId != null &&
            !_todayTasks.any((task) => task.id == _linkedTaskId)) {
          _linkedTaskId = null;
        }
      });
    } catch (_) {}
  }

  Future<void> _restoreActiveSession() async {
    try {
      final data = await _sessions.getActiveSession();
      if (data['active'] != true) return;
      final session = Map<String, dynamic>.from(data['session'] as Map);
      final startedAt =
          DateTime.parse(session['started_at'] as String).toLocal();
      final type = session['session_type']?.toString() ?? 'work';
      final total = _durationFor(type) * 60;
      final remaining = total - DateTime.now().difference(startedAt).inSeconds;
      if (!mounted) return;
      setState(() {
        _sessionType = type;
        _activeSession = true;
        _remainingSeconds = remaining.clamp(0, total);
        _running = remaining > 0;
        final taskId = session['task_id'];
        if (taskId is int && taskId > 0) _linkedTaskId = taskId;
      });
      if (_running) _startTicker();
    } catch (_) {}
  }

  int _durationFor(String type) => switch (type) {
    'long_break' => _longBreakMinutes,
    'break' => _breakMinutes,
    _ => _workMinutes,
  };

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds <= 0) {
        _timer?.cancel();
        _finishNaturally();
        return;
      }
      if (mounted) setState(() => _remainingSeconds--);
    });
  }

  Future<void> _start() async {
    if (!_activeSession) {
      try {
        await _sessions.startSession(
          _sessionType,
          taskId: _sessionType == 'work' ? _linkedTaskId : null,
        );
        _activeSession = true;
      } catch (_) {
        _message('开始专注失败');
        return;
      }
    }
    if (!mounted) return;
    setState(() => _running = true);
    _startTicker();
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  Future<void> _finishNaturally() async {
    if (_soundEnabled) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }

    if (_sessionType == 'work') {
      int? tagId;
      if (mounted) {
        tagId = await SystemTagPicker.show(context, title: '这次专注属于哪个维度？');
      }
      try {
        if (_activeSession) await _sessions.endSession(systemTagId: tagId);
      } catch (_) {}
      _activeSession = false;
      _completedSessions++;
      final duration = _workMinutes;
      if (!mounted) return;
      _showCompletion('专注了 $duration 分钟');
      final longBreak = _completedSessions % _sessionsBeforeLong == 0;
      setState(() {
        _sessionType = longBreak ? 'long_break' : 'break';
        _remainingSeconds =
            (longBreak ? _longBreakMinutes : _breakMinutes) * 60;
        _running = false;
      });
    } else {
      try {
        if (_activeSession) await _sessions.endSession();
      } catch (_) {}
      _activeSession = false;
      if (!mounted) return;
      _showCompletion('休息结束');
      setState(() {
        _sessionType = 'work';
        _remainingSeconds = _workMinutes * 60;
        _running = false;
      });
    }
    await _loadTodayStats();
    if (_autoStartNext && mounted) {
      await _start();
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    if (_activeSession) {
      int? tagId;
      if (_sessionType == 'work') {
        final elapsed = _workMinutes * 60 - _remainingSeconds;
        if (elapsed >= _workMinutes * 30 && mounted) {
          tagId = await SystemTagPicker.show(context, title: '这次专注属于哪个维度？');
        }
      }
      try {
        await _sessions.endSession(systemTagId: tagId);
      } catch (_) {}
    }
    _activeSession = false;
    if (!mounted) return;
    setState(() {
      _sessionType = 'work';
      _remainingSeconds = _workMinutes * 60;
      _running = false;
    });
    await _loadTodayStats();
  }

  void _showCompletion(String message) {
    setState(() => _completionMessage = message);
    _ripple.forward(from: 0);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _completionMessage == message) {
        setState(() => _completionMessage = null);
      }
    });
  }

  Future<void> _openSettings() async {
    var work = _workMinutes;
    var autoStart = _autoStartNext;
    var soundEnabled = _soundEnabled;
    var linkedTaskId = _linkedTaskId;

    final saved = await FxDialog.show<bool>(
      context: context,
      title: '🍅 专注设置',
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          return SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingsLine(
                  dialogContext,
                  title: '专注时长',
                  subtitle: '每轮工作分钟数',
                  trailing: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [25, 45, 60]
                        .map((minutes) {
                          final selected = work == minutes;
                          return FxChip(
                            label: '$minutes',
                            onTap: () => setDialogState(() => work = minutes),
                            backgroundColor:
                                selected
                                    ? activePalette.accent.withValues(
                                      alpha: .12,
                                    )
                                    : fxSubtleSurface(dialogContext),
                            foregroundColor:
                                selected
                                    ? activePalette.accent
                                    : theme.colorScheme.onSurface,
                            borderColor:
                                selected
                                    ? activePalette.accent.withValues(
                                      alpha: .35,
                                    )
                                    : theme.colorScheme.outlineVariant,
                            borderRadius: 999,
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                _settingsLine(
                  dialogContext,
                  title: '自动开始下一轮',
                  subtitle: '短休息后直接进入专注',
                  trailing: FxSwitch(
                    value: autoStart,
                    onChanged:
                        (value) => setDialogState(() => autoStart = value),
                  ),
                ),
                _settingsLine(
                  dialogContext,
                  title: '结束音效',
                  subtitle: '铃声提醒本轮结束',
                  trailing: FxSwitch(
                    value: soundEnabled,
                    onChanged:
                        (value) => setDialogState(() => soundEnabled = value),
                  ),
                ),
                _settingsLine(
                  dialogContext,
                  title: '关联任务',
                  subtitle: '产出计入该任务',
                  trailing: SizedBox(
                    width: 150,
                    child: FxSelect<int>(
                      value: linkedTaskId ?? 0,
                      options: [
                        const FxSelectOption(value: 0, label: '不关联'),
                        ..._todayTasks.map(
                          (task) =>
                              FxSelectOption(value: task.id, label: task.title),
                        ),
                      ],
                      onChanged:
                          (value) => setDialogState(
                            () =>
                                linkedTaskId =
                                    value == null || value == 0 ? null : value,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FxButton(
                      label: '取消',
                      variant: FxButtonVariant.outline,
                      size: FxButtonSize.sm,
                      onPressed:
                          () => Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).pop(false),
                    ),
                    const SizedBox(width: 8),
                    FxButton(
                      label: '保存设置',
                      size: FxButtonSize.sm,
                      onPressed:
                          () => Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved != true || !mounted) return;
    final oldTotal = _durationFor(_sessionType) * 60;
    final atStart = !_activeSession && _remainingSeconds == oldTotal;
    setState(() {
      _workMinutes = work;
      _autoStartNext = autoStart;
      _soundEnabled = soundEnabled;
      _linkedTaskId = linkedTaskId;
      if (atStart) _remainingSeconds = _durationFor(_sessionType) * 60;
    });
    _message('专注设置已更新');
  }

  Widget _settingsLine(
    BuildContext dialogContext, {
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    final theme = Theme.of(dialogContext);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SlowlightTypography.secondary(
                    dialogContext,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: SlowlightTypography.caption(
                    dialogContext,
                  ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '专注',
              actionIcon: LucideIcons.settings,
              actionTooltip: '专注设置',
              onAction: _openSettings,
            ),
            Expanded(
              child: Stack(
                children: [
                  _timerBody(),
                  if (_completionMessage != null) _completionOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timerBody() {
    final theme = Theme.of(context);
    final totalSeconds = _durationFor(_sessionType) * 60;
    final progress =
        totalSeconds == 0
            ? 0.0
            : (1 - _remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    final isWork = _sessionType == 'work';
    final color = isWork ? activePalette.accent : AppTheme.success;
    final stateLabel =
        isWork
            ? (_running
                ? '专注中'
                : _activeSession
                ? '已暂停'
                : '准备专注')
            : (_sessionType == 'long_break' ? '长休息' : '休息中');
    final quietOpacity = _running ? .4 : 1.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedOpacity(
              opacity: quietOpacity,
              duration: const Duration(milliseconds: 180),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  stateLabel,
                  style: TextStyle(
                    fontSize: SlowlightTypography.captionSize,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: FxCircularProgress(
                      value: progress,
                      strokeWidth: 8,
                      backgroundColor: theme.colorScheme.surfaceContainer,
                      color: color,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _format(_remainingSeconds),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: SlowlightTypography.displaySize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isWork ? '专注' : '休息',
                        style: TextStyle(
                          fontSize: SlowlightTypography.captionSize,
                          letterSpacing: 2,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AnimatedOpacity(
              opacity: quietOpacity,
              duration: const Duration(milliseconds: 180),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (!_running)
                    FxButton(
                      label: _remainingSeconds == totalSeconds ? '开始专注' : '继续',
                      icon: LucideIcons.play,
                      onPressed: _start,
                    )
                  else
                    FxButton(
                      label: '暂停',
                      icon: LucideIcons.pause,
                      variant: FxButtonVariant.outline,
                      onPressed: _pause,
                    ),
                  if (_activeSession)
                    FxButton(
                      label: '结束专注',
                      size: FxButtonSize.lg,
                      variant: FxButtonVariant.destructive,
                      onPressed: _stop,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AnimatedOpacity(
              opacity: quietOpacity,
              duration: const Duration(milliseconds: 180),
              child: Text(
                '今日第 ${_todayWorkCount + (isWork && _activeSession ? 1 : 0)} 轮 · 已专注 ${_todayWorkSeconds ~/ 60} 分钟',
                style: TextStyle(
                  fontSize: SlowlightTypography.secondarySize,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completionOverlay() {
    final color = activePalette.accent;
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _ripple,
          builder: (context, child) {
            final value = Curves.easeOut.transform(_ripple.value);
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120 + value * 120,
                  height: 120 + value * 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: .28 * (1 - value)),
                      width: 2,
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Text(
              _completionMessage!,
              style: const TextStyle(
                fontSize: SlowlightTypography.bodySize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _format(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  void _message(String text) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(text));
  }
}
