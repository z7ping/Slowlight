import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import '../repositories/session_repository.dart';
import '../repositories/tag_links_repository.dart';
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
  static const _settingsPrefsKey = 'slowlight_pomodoro_settings_v1';
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
  // Immutable goal for the active session; restored from Local/Cloud storage.
  int _sessionTargetMinutes = 25;
  String _sessionType = 'work';
  bool _running = false;
  bool _activeSession = false;
  bool _finalizingSession = false;
  bool _sessionTransitioning = false;
  bool _endConfirmationOpen = false;
  int? _sessionId;
  int _sessionRevision = 0;
  DateTime? _sessionStartedAt;
  DateTime? _sessionPausedAt;
  int _pausedDurationSeconds = 0;
  String? _finishError;
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
    unawaited(_restorePreferencesThenSession());
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
      if (data['active'] != true || !mounted) return;
      _applySession(Map<String, dynamic>.from(data['session'] as Map));
    } catch (_) {
      if (mounted) _message('恢复专注状态失败，请检查连接');
    }
  }

  /// Restore preferences before the legacy session fallback reads a target
  /// duration. Active rounds with persisted target_minutes remain authoritative.
  Future<void> _restorePreferencesThenSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_settingsPrefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final work = decoded['workMinutes'];
          if (work is int && const [25, 45, 60].contains(work)) {
            _workMinutes = work;
          }
          final auto = decoded['autoStartNext'];
          if (auto is bool) _autoStartNext = auto;
          final sound = decoded['soundEnabled'];
          if (sound is bool) _soundEnabled = sound;
          if (mounted && !_activeSession && !_sessionTransitioning) {
            setState(() {
              _sessionTargetMinutes = _durationFor(_sessionType);
              _remainingSeconds = _sessionTargetMinutes * 60;
            });
          }
        }
      }
    } catch (_) {
      // Invalid old preferences must not stop active-session recovery.
      if (mounted) _message('专注偏好读取失败，已使用默认设置');
    } finally {
      if (mounted) await _restoreActiveSession();
    }
  }

  int _remainingFromSession() {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return _remainingSeconds;
    final now = DateTime.now();
    final until = _sessionPausedAt != null && _sessionPausedAt!.isBefore(now)
        ? _sessionPausedAt!
        : now;
    final activeSeconds =
        (until.difference(startedAt).inSeconds - _pausedDurationSeconds)
            .clamp(0, 1 << 31);
    final totalSeconds = _sessionTargetMinutes * 60;
    return (totalSeconds - activeSeconds).clamp(0, totalSeconds).toInt();
  }

  void _applySession(Map<String, dynamic> session) {
    if (!mounted) return;
    final id = session['id'];
    if (id is! num || id.toInt() <= 0) throw StateError('会话 ID 无效');
    final startedAt = DateTime.parse(session['started_at'] as String).toLocal();
    final rawPausedAt = session['paused_at'];
    final pausedAt = rawPausedAt is String
        ? DateTime.parse(rawPausedAt).toLocal()
        : null;
    _timer?.cancel();
    setState(() {
      _sessionId = id.toInt();
      _sessionRevision = (session['revision'] as num?)?.toInt() ?? 0;
      _sessionStartedAt = startedAt;
      _sessionPausedAt = pausedAt;
      _pausedDurationSeconds =
          (session['paused_duration_seconds'] as num?)?.toInt() ?? 0;
      _sessionType = session['session_type']?.toString() ?? 'work';
      final storedTarget = (session['target_minutes'] as num?)?.toInt() ?? 0;
      // Old sessions have no per-round snapshot; retain legacy defaults.
      _sessionTargetMinutes = storedTarget > 0 && storedTarget <= 180
          ? storedTarget
          : _durationFor(_sessionType);
      _activeSession = true;
      _remainingSeconds = _remainingFromSession();
      _running = pausedAt == null && _remainingSeconds > 0;
      final taskId = session['task_id'];
      if (taskId is num && taskId.toInt() > 0) _linkedTaskId = taskId.toInt();
    });
    if (_running) _startTicker();
  }

  int _durationFor(String type) => switch (type) {
    'long_break' => _longBreakMinutes,
    'break' => _breakMinutes,
    _ => _workMinutes,
  };

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      // 不以 Timer.periodic 调用次数为事实来源：系统挂起、后台恢复后按
      // 已持久化开始时间与暂停累计重新计算，避免跨端倒计时漂移。
      final remaining = _remainingFromSession();
      if (remaining <= 0) {
        setState(() => _remainingSeconds = 0);
        // 正在等待暂停/恢复确认时不能并发结束同一会话。
        if (!_sessionTransitioning) {
          _timer?.cancel();
          unawaited(_finishNaturally());
        }
        return;
      }
      setState(() => _remainingSeconds = remaining);
    });
  }

  Future<void> _start() async {
    if (_finalizingSession || _sessionTransitioning) return;
    if (_activeSession && _remainingSeconds <= 0) {
      await _finishNaturally();
      return;
    }
    setState(() => _sessionTransitioning = true);
    try {
      final response = !_activeSession
          ? await _sessions.startSession(
              _sessionType,
              taskId: _sessionType == 'work' ? _linkedTaskId : null,
              targetMinutes: _durationFor(_sessionType),
            )
          : await _sessions.resumeSession(_sessionId!, _sessionRevision);
      if (!mounted) return;
      _applySession(Map<String, dynamic>.from(response['session'] as Map));
    } catch (_) {
      if (mounted) _message(_activeSession ? '继续专注失败，请重试' : '开始专注失败，请重试');
    } finally {
      if (mounted) setState(() => _sessionTransitioning = false);
    }
  }

  Future<void> _pause() async {
    if (_finalizingSession || _sessionTransitioning || _sessionId == null) return;
    setState(() => _sessionTransitioning = true);
    try {
      final response = await _sessions.pauseSession(_sessionId!, _sessionRevision);
      if (!mounted) return;
      _applySession(Map<String, dynamic>.from(response['session'] as Map));
    } catch (_) {
      if (mounted) _message('无法确认暂停状态，请刷新或重试');
    } finally {
      if (mounted) setState(() => _sessionTransitioning = false);
    }
  }

  Future<bool> _freezeBeforeEnding() async {
    if (!_activeSession || _sessionId == null) return true;
    try {
      final response = await _sessions.pauseSession(_sessionId!, _sessionRevision);
      if (!mounted) return false;
      _applySession(Map<String, dynamic>.from(response['session'] as Map));
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _finalizingSession = false;
          _finishError = '无法确认停止计时，结束记录未保存，请重试。';
        });
      }
      return false;
    }
  }

  /// 结束会话是核心写入；标签是附加写入。两者状态必须分别反馈，
  /// 否则标签保存失败时会把已结束的专注误当成整轮失败。
  Future<bool> _endSessionWithTags(List<int>? tagIds) async {
    final result = await _sessions.endSession();
    if (tagIds == null || tagIds.isEmpty) return true;
    try {
      final session = result['session'];
      final rawId = session is Map ? session['id'] : null;
      if (rawId is! num || rawId.toInt() <= 0) {
        throw StateError('缺少结束记录的有效 ID');
      }
      await TagLinksRepository().replaceFor(
        TagLinkedEntity.session,
        rawId.toInt(),
        tagIds,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _finishNaturally() async {
    if (_finalizingSession) return;
    setState(() {
      _finalizingSession = true;
      _running = false;
      _finishError = null;
    });
    _timer?.cancel();
    if (!await _freezeBeforeEnding()) return;

    List<int>? tagIds;
    if (_sessionType == 'work' && mounted) {
      tagIds = await SystemTagPicker.showMultiple(context);
    }
    if (!mounted) return;

    var tagsSaved = true;
    try {
      if (_activeSession) tagsSaved = await _endSessionWithTags(tagIds);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finalizingSession = false;
        _finishError = '结束记录未能保存，请重试。';
      });
      return;
    }
    if (!mounted) return;
    _activeSession = false;
    _sessionId = null;
    _sessionStartedAt = null;
    _sessionPausedAt = null;
    if (_soundEnabled) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
    if (!mounted) return;
    if (_sessionType == 'work') {
      _completedSessions++;
      _showCompletion(tagsSaved ? '专注了 $_sessionTargetMinutes 分钟' : '专注已结束，但标签未保存');
      final longBreak = _completedSessions % _sessionsBeforeLong == 0;
      setState(() {
        _sessionType = longBreak ? 'long_break' : 'break';
        _sessionTargetMinutes = _durationFor(_sessionType);
        _remainingSeconds = _sessionTargetMinutes * 60;
        _running = false;
        _finalizingSession = false;
      });
    } else {
      _showCompletion('休息结束');
      setState(() {
        _sessionType = 'work';
        _sessionTargetMinutes = _workMinutes;
        _remainingSeconds = _sessionTargetMinutes * 60;
        _running = false;
        _finalizingSession = false;
      });
    }
    await _loadTodayStats();
    if (_autoStartNext && mounted) await _start();
  }

  Future<void> _stop() async {
    if (_finalizingSession || _sessionTransitioning ||
        _endConfirmationOpen || !_activeSession) return;
    // Do not stop the persisted timer before the user confirms. The timer
    // may also finish naturally while the confirmation is on screen.
    final sessionId = _sessionId;
    final sessionType = _sessionType;
    _endConfirmationOpen = true;
    bool? confirmed;
    try {
      confirmed = await FxDialog.confirm(
        context: context,
        title: sessionType == 'work' ? '结束本轮专注？' : '结束本轮休息？',
        content: '结束后将按实际计时尝试保存本轮记录。',
        cancelText: '继续计时',
        confirmText: '确认结束',
        destructive: true,
        barrierDismissible: false,
      );
    } finally {
      _endConfirmationOpen = false;
    }
    if (!mounted || confirmed != true || !_activeSession ||
        _sessionId != sessionId || _sessionType != sessionType ||
        _finalizingSession || _sessionTransitioning) return;
    _timer?.cancel();
    setState(() {
      _finalizingSession = true;
      _running = false;
      _finishError = null;
    });
    if (!await _freezeBeforeEnding()) return;
    List<int>? tagIds;
    if (_activeSession && _sessionType == 'work') {
      final elapsed = _sessionTargetMinutes * 60 - _remainingSeconds;
      if (elapsed >= _sessionTargetMinutes * 30 && mounted) {
        tagIds = await SystemTagPicker.showMultiple(context);
      }
    }
    if (!mounted) return;
    var tagsSaved = true;
    try {
      if (_activeSession) tagsSaved = await _endSessionWithTags(tagIds);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _finalizingSession = false;
        _finishError = '结束记录未能保存，请重试结束。';
      });
      return;
    }
    if (!mounted) return;
    if (!tagsSaved) _message('专注已结束，但关联标签保存失败');
    setState(() {
      _activeSession = false;
      _sessionId = null;
      _sessionStartedAt = null;
      _sessionPausedAt = null;
      _finalizingSession = false;
      _sessionType = 'work';
      _sessionTargetMinutes = _workMinutes;
      _remainingSeconds = _sessionTargetMinutes * 60;
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
    // Timer duration must not change while a persisted session is in progress.
    if (_activeSession || _sessionTransitioning || _finalizingSession) return;
    var work = _workMinutes;
    var autoStart = _autoStartNext;
    var soundEnabled = _soundEnabled;
    var linkedTaskId = _linkedTaskId;

    final saved = await FxDialog.show<bool>(
      context: context,
      title: '🍅 专注设置',
      showCloseButton: false,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .72,
            ),
            child: SingleChildScrollView(
              child: SizedBox(
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
              ),
            ),
          );
        },
      ),
    );

    if (saved != true || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = await prefs.setString(
        _settingsPrefsKey,
        jsonEncode({
          'workMinutes': work,
          'autoStartNext': autoStart,
          'soundEnabled': soundEnabled,
        }),
      );
      if (!persisted) throw StateError('写入设置失败');
    } catch (_) {
      if (mounted) _message('专注设置未保存，请重试');
      return;
    }
    if (!mounted) return;
    final oldTotal = _durationFor(_sessionType) * 60;
    final atStart = !_activeSession && _remainingSeconds == oldTotal;
    setState(() {
      _workMinutes = work;
      _autoStartNext = autoStart;
      _soundEnabled = soundEnabled;
      _linkedTaskId = linkedTaskId;
      if (atStart) {
        _sessionTargetMinutes = _durationFor(_sessionType);
        _remainingSeconds = _sessionTargetMinutes * 60;
      }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 290 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.4;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: SlowlightTypography.secondary(dialogContext).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: SlowlightTypography.caption(dialogContext).copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        return Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    copy,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: trailing),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: copy),
                    const SizedBox(width: 12),
                    trailing,
                  ],
                ),
        );
      },
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
              trailing: FxIconButton(
                icon: LucideIcons.settings,
                tooltip: _activeSession
                    ? '本轮结束后可修改设置'
                    : '专注设置',
                onPressed: _activeSession ||
                        _sessionTransitioning ||
                        _finalizingSession
                    ? null
                    : _openSettings,
              ),
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
    final totalSeconds = (_activeSession
            ? _sessionTargetMinutes
            : _durationFor(_sessionType)) * 60;
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
    // 专注刻度盘根据真实宽度与文字缩放适度伸展，不再固定 220dp。
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final availableWidth = MediaQuery.sizeOf(context).width - 48;
    final desired = 220.0 + (scale - 1).clamp(0.0, 1.0).toDouble() * 64.0;
    final dialSize = desired > availableWidth ? availableWidth : desired;

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
              key: const ValueKey('pomodoro-dial'),
              width: dialSize,
              height: dialSize,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _format(_remainingSeconds),
                            maxLines: 1,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontSize: SlowlightTypography.displaySize,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
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
                      label: _remainingSeconds == 0 && _activeSession
                          ? '重试保存本轮'
                          : _activeSession
                              ? '继续'
                              : isWork ? '开始专注' : '开始休息',
                      icon: LucideIcons.play,
                      onPressed: _finalizingSession || _sessionTransitioning ? null : _start,
                    )
                  else
                    FxButton(
                      label: '暂停',
                      icon: LucideIcons.pause,
                      variant: FxButtonVariant.outline,
                      onPressed: _finalizingSession || _sessionTransitioning ? null : _pause,
                    ),
                  if (_activeSession)
                    FxButton(
                      label: _finalizingSession
                          ? '保存中…'
                          : isWork ? '结束专注' : '结束休息',
                      size: FxButtonSize.lg,
                      variant: FxButtonVariant.destructive,
                      onPressed: _finalizingSession || _sessionTransitioning ? null : _stop,
                    ),
                ],
              ),
            ),
            if (_finishError != null) ...[
              const SizedBox(height: 12),
              Text(
                _finishError!,
                key: const ValueKey('pomodoro-finish-error'),
                textAlign: TextAlign.center,
                style: SlowlightTypography.secondary(context).copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
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
              borderRadius: BorderRadius.circular(SlowlightRadius.lg),
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
