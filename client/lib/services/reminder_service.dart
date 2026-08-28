import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/lock_screen.dart';
import '../services/reminder_local.dart';
import '../services/data_mode_manager.dart';

/// 休息提醒服务（全局单例）
///
/// 本地优先架构：所有数据先写 SQLite，服务端异步同步。
/// 状态机: idle → working → micro_rest → working → micro_rest → working → long_rest → idle → ...
class ReminderService extends ChangeNotifier {
  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;
  ReminderService._();

  final _local = ReminderLocal();

  // 配置
  int _workMinutes = 25;
  int _microRestSeconds = 20;
  int _longRestMinutes = 5;
  int _microRestsBeforeLong = 2;
  String _lockScreenMode = 'window'; // window / fullscreen
  int _notifyBeforeSec = 30;
  bool _autoLoop = true;
  bool _autoStartOnLaunch = true;
  bool _microRestStrict = false;
  bool _longRestStrict = false;
  bool _allowPostponeMicro = true;
  bool _allowPostponeLong = true;
  bool _loaded = false;

  // 状态机: idle / working / micro_rest / long_rest
  String _state = 'idle';
  Timer? _timer;
  Timer? _statsTimer;
  Timer? _syncTimer;
  Timer? _pauseUntilTimer;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;
  int _cycleCount = 0;
  int _microRestCount = 0;
  bool _paused = false;
  DateTime? _pauseUntil; // 暂停截止时间（null=无限期暂停）
  DateTime? _lastTickTime;
  DateTime? _activeWorkStartedAt;

  // 统计
  int _todayWorkSeconds = 0;
  int _todayRestSeconds = 0;
  int _todayCycles = 0;
  int _todaySkips = 0;
  int _todayWorkCount = 0;
  int _todayWorkAvgSeconds = 0;
  int _todayWorkMaxSeconds = 0;
  int _todayWorkMinSeconds = 0;
  int _todayRestCount = 0;
  int _todayRestAvgSeconds = 0;
  int _todayRestMaxSeconds = 0;
  double _todaySkipRate = 0;
  double _todayWorkRestRatio = 0;
  int _todayLongestNoSkipStreak = 0;
  String _todayDayStart = '';
  String _todayDayEnd = '';
  bool _todayIsActive = false;

  int _pendingSyncCount = 0;

  // ── Getters ──

  int get workMinutes => _workMinutes;
  int get microRestSeconds => _microRestSeconds;
  int get longRestMinutes => _longRestMinutes;
  int get microRestsBeforeLong => _microRestsBeforeLong;
  String get lockScreenMode => Platform.isWindows ? _lockScreenMode : 'window';
  int get notifyBeforeSec => _notifyBeforeSec;
  bool get autoLoop => _autoLoop;
  bool get autoStartOnLaunch => _autoStartOnLaunch;
  bool get microRestStrict => _microRestStrict;
  bool get longRestStrict => _longRestStrict;
  bool get allowPostponeMicro => _allowPostponeMicro;
  bool get allowPostponeLong => _allowPostponeLong;
  bool get paused => _paused;
  DateTime? get pauseUntil => _pauseUntil;
  String get state => _state;
  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;
  int get cycleCount => _cycleCount;
  int get microRestCount => _microRestCount;
  int get todayWorkSeconds {
    if (_state == 'working' && !_paused && _activeWorkStartedAt != null) {
      return _todayWorkSeconds + DateTime.now().difference(_activeWorkStartedAt!).inSeconds;
    }
    return _todayWorkSeconds;
  }
  int get todayRestSeconds => _todayRestSeconds;
  int get todayCycles => _todayCycles;
  int get todaySkips => _todaySkips;
  int get todayWorkCount => _todayWorkCount;
  int get todayWorkAvgSeconds => _todayWorkAvgSeconds;
  int get todayWorkMaxSeconds => _todayWorkMaxSeconds;
  int get todayWorkMinSeconds => _todayWorkMinSeconds;
  int get todayRestCount => _todayRestCount;
  int get todayRestAvgSeconds => _todayRestAvgSeconds;
  int get todayRestMaxSeconds => _todayRestMaxSeconds;
  double get todaySkipRate => _todaySkipRate;
  double get todayWorkRestRatio => _todayWorkRestRatio;
  int get todayLongestNoSkipStreak => _todayLongestNoSkipStreak;
  String get todayDayStart => _todayDayStart;
  String get todayDayEnd => _todayDayEnd;
  bool get todayIsActive => _todayIsActive;
  int get pendingSyncCount => _pendingSyncCount;

  Future<void> refreshStats() async {
    await _refreshLocalStats();
    notifyListeners();
  }
  bool get isRunning => _state != 'idle';
  bool get isLoaded => _loaded;
  bool get _enabled => true;

  /// 当前休息类型是否严格模式（不能跳过）
  bool get isCurrentRestStrict {
    if (_state == 'micro_rest') return _microRestStrict;
    if (_state == 'long_rest') return _longRestStrict;
    return false;
  }

  /// 当前休息类型是否允许延后
  bool get isCurrentRestPostponeAllowed {
    if (_state == 'micro_rest') return _allowPostponeMicro;
    if (_state == 'long_rest') return _allowPostponeLong;
    return false;
  }

  // ── 加载 ──

  Future<void> loadAll() async {
    try {
      final localConfig = await _local.getConfig();
      if (localConfig != null) {
        _workMinutes = localConfig['work_minutes'] as int? ?? 25;
        _microRestSeconds = localConfig['micro_rest_seconds'] as int? ?? 20;
        _longRestMinutes = localConfig['long_rest_minutes'] as int? ?? 5;
        _microRestsBeforeLong = localConfig['micro_rests_before_long'] as int? ?? 2;
        _lockScreenMode = localConfig['lock_screen_mode'] as String? ?? 'window';
        _notifyBeforeSec = localConfig['notify_before_seconds'] as int? ?? 30;
        _autoLoop = (localConfig['auto_loop'] as int?) == 1;
        _autoStartOnLaunch = (localConfig['auto_start_on_launch'] as int?) == 1;
        _microRestStrict = (localConfig['micro_rest_strict'] as int?) == 1;
        _longRestStrict = (localConfig['long_rest_strict'] as int?) == 1;
        _allowPostponeMicro = (localConfig['allow_postpone_micro'] as int?) != 0; // 默认true
        _allowPostponeLong = (localConfig['allow_postpone_long'] as int?) != 0; // 默认true
      }

      final stats = await _local.getTodayStats();
      _todayWorkSeconds = stats['total_work_seconds'] as int;
      _todayRestSeconds = stats['total_break_seconds'] as int;
      _todayCycles = stats['rest_count'] as int;
      _todaySkips = stats['skip_count'] as int;
      _todayWorkCount = stats['work_count'] as int;
      _todayWorkAvgSeconds = stats['work_avg_seconds'] as int;
      _todayWorkMaxSeconds = stats['work_max_seconds'] as int;
      _todayWorkMinSeconds = stats['work_min_seconds'] as int;
      _todayRestCount = stats['rest_count'] as int;
      _todayRestAvgSeconds = stats['rest_avg_seconds'] as int;
      _todayRestMaxSeconds = stats['rest_max_seconds'] as int;
      _todaySkipRate = (stats['skip_rate'] as num).toDouble();
      _todayWorkRestRatio = (stats['work_rest_ratio'] as num).toDouble();
      _todayLongestNoSkipStreak = stats['longest_no_skip_streak'] as int;
      _todayDayStart = stats['day_start'] as String;
      _todayDayEnd = stats['day_end'] as String;
      _todayIsActive = stats['is_active'] as bool;

      _pendingSyncCount = await _local.getPendingCount();
      _loaded = true;
      notifyListeners();

      _syncConfigFromServer();
      _syncPendingToServer();
      _startSyncTimer();
      _startStatsTimer();
      autoStartIfNeeded();
    } catch (e) {
    }
  }

  // ── 配置 ──

  void updateConfig({
    int? workMinutes,
    int? microRestSeconds,
    int? longRestMinutes,
    int? microRestsBeforeLong,
    String? lockScreenMode,
    int? notifyBeforeSec,
    bool? autoLoop,
    bool? autoStartOnLaunch,
    bool? microRestStrict,
    bool? longRestStrict,
    bool? allowPostponeMicro,
    bool? allowPostponeLong,
  }) {
    if (workMinutes != null) _workMinutes = workMinutes;
    if (microRestSeconds != null) _microRestSeconds = microRestSeconds;
    if (longRestMinutes != null) _longRestMinutes = longRestMinutes;
    if (microRestsBeforeLong != null) _microRestsBeforeLong = microRestsBeforeLong;
    if (lockScreenMode != null) _lockScreenMode = lockScreenMode;
    if (notifyBeforeSec != null) _notifyBeforeSec = notifyBeforeSec;
    if (autoLoop != null) _autoLoop = autoLoop;
    if (autoStartOnLaunch != null) _autoStartOnLaunch = autoStartOnLaunch;
    if (microRestStrict != null) _microRestStrict = microRestStrict;
    if (longRestStrict != null) _longRestStrict = longRestStrict;
    if (allowPostponeMicro != null) _allowPostponeMicro = allowPostponeMicro;
    if (allowPostponeLong != null) _allowPostponeLong = allowPostponeLong;
    notifyListeners();
  }

  Future<void> saveConfig() async {
    await _local.saveConfig(
      workMinutes: _workMinutes,
      microRestSeconds: _microRestSeconds,
      longRestMinutes: _longRestMinutes,
      microRestsBeforeLong: _microRestsBeforeLong,
      lockScreenMode: _lockScreenMode,
      notifyBeforeSeconds: _notifyBeforeSec,
      autoLoop: _autoLoop,
      autoStartOnLaunch: _autoStartOnLaunch,
      microRestStrict: _microRestStrict,
      longRestStrict: _longRestStrict,
      allowPostponeMicro: _allowPostponeMicro,
      allowPostponeLong: _allowPostponeLong,
    );

    _safeSync(() => ApiService.saveReminderConfig({
          'work_minutes': _workMinutes,
          'micro_rest_seconds': _microRestSeconds,
          'long_rest_minutes': _longRestMinutes,
          'micro_rests_before_long': _microRestsBeforeLong,
          'lock_screen_mode': _lockScreenMode,
          'notify_before_seconds': _notifyBeforeSec,
          'auto_loop': _autoLoop,
          'auto_start_on_launch': _autoStartOnLaunch,
          'micro_rest_strict': _microRestStrict,
          'long_rest_strict': _longRestStrict,
          'allow_postpone_micro': _allowPostponeMicro,
          'allow_postpone_long': _allowPostponeLong,
        }));
  }

  // ── 状态控制 ──

  void startWork() {
    unawaited(_local.endWork());
    unawaited(_local.cancelActiveRest());
    _local.startWork();
    _activeWorkStartedAt = DateTime.now();
    _state = 'working';
    _totalSeconds = _workMinutes * 60;
    _remainingSeconds = _totalSeconds;
    _startTimer();
    notifyListeners();
  }

  void startMicroRest() {
    final shouldEndWork = _state == 'working';
    _activeWorkStartedAt = null;
    unawaited(() async {
      if (shouldEndWork) {
        await _local.endWork();
        await _refreshLocalStats();
      }
      await _local.startRest();
    }());
    _state = 'micro_rest';
    _totalSeconds = _microRestSeconds;
    _remainingSeconds = _totalSeconds;
    if (_lockScreenMode == 'fullscreen') {
      LockScreenManager().updateOverlayCountdown(_remainingSeconds);
    }
    _startTimer();
    // 小憩也锁屏
    _doLockScreen();
    notifyListeners();
  }

  void startLongRest() {
    final shouldEndWork = _state == 'working';
    _activeWorkStartedAt = null;
    unawaited(() async {
      if (shouldEndWork) {
        await _local.endWork();
        await _refreshLocalStats();
      }
      await _local.startRest();
    }());
    _state = 'long_rest';
    _totalSeconds = _longRestMinutes * 60;
    _remainingSeconds = _totalSeconds;
    if (_lockScreenMode == 'fullscreen') {
      LockScreenManager().updateOverlayCountdown(_remainingSeconds);
    }
    _startTimer();
    _doLockScreen();
    notifyListeners();
  }

  void skipRest() {
    if (_state != 'micro_rest' && _state != 'long_rest') return;
    if (isCurrentRestStrict) return;

    _timer?.cancel();
    _cycleCount++;
    if (_state == 'long_rest') {
      _microRestCount = 0;
    }
    LockScreenManager().unlock();

    _local.skipRest().then((_) async {
      await _refreshLocalStats();
    if (_autoLoop && !_paused) {
      startWork();
    } else {
      _activeWorkStartedAt = null;
      _state = 'idle';
      notifyListeners();
    }
    });
  }

  void endRest() {
    if (_state != 'micro_rest' && _state != 'long_rest') return;

    _timer?.cancel();
    _cycleCount++;

    final wasMicro = _state == 'micro_rest';
    final willStartLong = wasMicro && (_microRestCount + 1 >= _microRestsBeforeLong);

    if (wasMicro) {
      _microRestCount++;
    } else {
      _microRestCount = 0;
    }
    if (willStartLong) _microRestCount = 0;

    LockScreenManager().unlock();

    _local.endRest().then((_) async {
      await _refreshLocalStats();
      if (willStartLong) {
        startLongRest();
      } else if (_autoLoop && !_paused) {
        startWork();
      } else {
        _state = 'idle';
        notifyListeners();
      }
    });
  }

  void postponeRest() {
    if (_state != 'micro_rest' && _state != 'long_rest') return;
    if (!isCurrentRestPostponeAllowed) return;

    _timer?.cancel();
    LockScreenManager().unlock();
    // 回到工作状态，延后5分钟后重新提醒
    _state = 'idle';
    notifyListeners();
    final savedWorkMinutes = _workMinutes;
    _workMinutes = 5; // 临时5分钟
    _local.cancelActiveRest().then((_) {
      startWork();
      // 恢复原配置（startWork 已读取 _workMinutes 设置了 _totalSeconds）
      _workMinutes = savedWorkMinutes;
      _refreshLocalStats();
    });
  }

  void stopAll() {
    _timer?.cancel();
    final wasWorking = _state == 'working';
    final wasRest = _state == 'micro_rest' || _state == 'long_rest';
    _state = 'idle';
    _remainingSeconds = 0;
    _totalSeconds = 0;
    _microRestCount = 0;
    LockScreenManager().unlock();

    Future<void>? op;
    if (wasWorking) {
      _activeWorkStartedAt = null;
      op = _local.endWork();
    } else if (wasRest) {
      op = _local.cancelActiveRest();
    }

    (op ?? Future.value()).then((_) async {
      await _refreshLocalStats();
      notifyListeners();
    });
  }

  void resetWork() {
    _timer?.cancel();
    LockScreenManager().unlock();
    if (_state == 'working') {
      _activeWorkStartedAt = null;
      _local.endWork();
    } else if (_state == 'micro_rest' || _state == 'long_rest') {
      _local.cancelActiveRest();
    }
    _state = 'idle';
    notifyListeners();
    startWork();
  }

  void forceRest() {
    if (_state == 'micro_rest' || _state == 'long_rest') return;
    _timer?.cancel();
    if (_state == 'working') {
      _safeSync(() => ApiService.startRestSession());
    }
    startMicroRest();
  }

  // ── 内部方法 ──

  void _startTimer() {
    _timer?.cancel();
    _lastTickTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (_lastTickTime != null) {
        final gap = now.difference(_lastTickTime!).inSeconds;
        if (gap > 60) {
          _timer?.cancel();
          _lastTickTime = now;
          _remainingSeconds = 0;
          _totalSeconds = 0;
          final wasRest = _state == 'micro_rest' || _state == 'long_rest';
          if (wasRest) {
            _cycleCount++;
            if (_state == 'micro_rest') _microRestCount++;
            _activeWorkStartedAt = null;
            _state = 'idle';
            LockScreenManager().unlock();
            _local.endRest().then((_) async {
              await _refreshLocalStats();
              if (_autoLoop && _state == 'idle') startWork();
            });
          } else if (_state == 'working') {
            _activeWorkStartedAt = null;
            _state = 'idle';
            LockScreenManager().unlock();
            _local.endWork().then((_) async {
              await _refreshLocalStats();
              if (_autoLoop && _state == 'idle') startWork();
            });
          }
          notifyListeners();
          return;
        }
      }
      _lastTickTime = now;

      if (_remainingSeconds <= 0) {
        if (_state == 'working') {
          startMicroRest();
        } else if (_state == 'micro_rest' || _state == 'long_rest') {
          endRest();
        }
        return;
      }
      _remainingSeconds--;
      if (_lockScreenMode == 'fullscreen') {
        LockScreenManager().updateOverlayCountdown(_remainingSeconds);
      }
      notifyListeners();
    });
  }

  Future<void> _refreshLocalStats() async {
    try {
      final stats = await _local.getTodayStats();
      _todayWorkSeconds = stats['total_work_seconds'] as int;
      _todayRestSeconds = stats['total_break_seconds'] as int;
      _todayCycles = stats['rest_count'] as int;
      _todaySkips = stats['skip_count'] as int;
      _todayWorkCount = stats['work_count'] as int;
      _todayWorkAvgSeconds = stats['work_avg_seconds'] as int;
      _todayWorkMaxSeconds = stats['work_max_seconds'] as int;
      _todayWorkMinSeconds = stats['work_min_seconds'] as int;
      _todayRestCount = stats['rest_count'] as int;
      _todayRestAvgSeconds = stats['rest_avg_seconds'] as int;
      _todayRestMaxSeconds = stats['rest_max_seconds'] as int;
      _todaySkipRate = (stats['skip_rate'] as num).toDouble();
      _todayWorkRestRatio = (stats['work_rest_ratio'] as num).toDouble();
      _todayLongestNoSkipStreak = stats['longest_no_skip_streak'] as int;
      _todayDayStart = stats['day_start'] as String;
      _todayDayEnd = stats['day_end'] as String;
      _todayIsActive = stats['is_active'] as bool;
      _pendingSyncCount = await _local.getPendingCount();
      notifyListeners();
    } catch (e) {
    }
  }

  Future<void> _doLockScreen() async {
    try {
      if (_lockScreenMode == 'fullscreen') {
        await LockScreenManager().lock(message: '请休息一下 ☕');
      }
      // window 模式下由 UI 层的 _RestOverlay 处理
    } catch (e) {
    }
  }

  Future<void> _safeSync(Future<dynamic> Function() apiCall) async {
    if (DataModeManager().isLocal) return;
    try {
      await apiCall().timeout(const Duration(seconds: 5));
      _syncPendingToServer();
    } catch (e) {
    }
  }

  Future<void> _syncConfigFromServer() async {
    if (DataModeManager().isLocal) return;
    try {
      final config = await ApiService.getReminderConfig().timeout(const Duration(seconds: 5));
      await _local.saveConfig(
        workMinutes: config['work_minutes'] ?? 25,
        microRestSeconds: config['micro_rest_seconds'] ?? 20,
        longRestMinutes: config['long_rest_minutes'] ?? 5,
        microRestsBeforeLong: config['micro_rests_before_long'] ?? 2,
        lockScreenMode: config['lock_screen_mode'] ?? 'window',
        notifyBeforeSeconds: config['notify_before_seconds'] ?? 30,
        autoLoop: config['auto_loop'] ?? true,
        autoStartOnLaunch: config['auto_start_on_launch'] ?? true,
        microRestStrict: config['micro_rest_strict'] ?? false,
        longRestStrict: config['long_rest_strict'] ?? false,
        allowPostponeMicro: config['allow_postpone_micro'] ?? true,
        allowPostponeLong: config['allow_postpone_long'] ?? true,
      );
      _workMinutes = config['work_minutes'] ?? 25;
      _microRestSeconds = config['micro_rest_seconds'] ?? 20;
      _longRestMinutes = config['long_rest_minutes'] ?? 5;
      _microRestsBeforeLong = config['micro_rests_before_long'] ?? 2;
      _lockScreenMode = config['lock_screen_mode'] ?? 'window';
      _notifyBeforeSec = config['notify_before_seconds'] ?? 30;
      _autoLoop = config['auto_loop'] ?? true;
      _autoStartOnLaunch = config['auto_start_on_launch'] ?? true;
      _microRestStrict = config['micro_rest_strict'] ?? false;
      _longRestStrict = config['long_rest_strict'] ?? false;
      _allowPostponeMicro = config['allow_postpone_micro'] ?? true;
      _allowPostponeLong = config['allow_postpone_long'] ?? true;
      notifyListeners();
    } catch (e) {
    }
  }

  Future<void> _syncPendingToServer() async {
    if (DataModeManager().isLocal) return;
    final pending = await _local.getPendingSync();
    if (pending.isEmpty) return;
    for (final row in pending) {
      try {
        final localId = row['id'] as int;
        await ApiService.startWorkSession().timeout(const Duration(seconds: 5));
        await _local.markSynced(localId, 0);
      } catch (e) {
        break;
      }
    }
    _pendingSyncCount = await _local.getPendingCount();
    notifyListeners();
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _syncPendingToServer();
      _syncConfigFromServer();
    });
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshLocalStats();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statsTimer?.cancel();
    _syncTimer?.cancel();
    _pauseUntilTimer?.cancel();
    LockScreenManager().unlock();
    super.dispose();
  }

  void autoStartIfNeeded() {
    if (!_autoStartOnLaunch) return;
    if (_state != 'idle') return;
    startWork();
  }

  void pause() {
    if (_state == 'idle' || _paused) return;
    _paused = true;
    _timer?.cancel();
    notifyListeners();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    if (_state == 'working' || _state == 'micro_rest' || _state == 'long_rest') {
      _lastTickTime = DateTime.now();
      _startTimer();
    } else if (_state == 'idle' && _autoLoop) {
      startWork();
    }
    notifyListeners();
  }

  /// 跳到下一次休息（直接进入小憩）
  void skipToNextRest() {
    if (_state == 'micro_rest' || _state == 'long_rest') return;
    _timer?.cancel();
    final op = _state == 'working' ? _local.endWork() : Future<void>.value();
    _state = 'idle';
    notifyListeners();
    op.then((_) {
      startMicroRest();
    });
  }

  /// 跳到下一次长休息（直接进入休息）
  void skipToNextLongRest() {
    if (_state == 'micro_rest' || _state == 'long_rest') return;
    _timer?.cancel();
    final op = _state == 'working' ? _local.endWork() : Future<void>.value();
    _state = 'idle';
    notifyListeners();
    op.then((_) {
      startLongRest();
    });
  }

  /// 暂停休息直到指定时间
  void pauseRestUntil(DateTime until) {
    final wasWorking = _state == 'working';
    final wasRest = _state == 'micro_rest' || _state == 'long_rest';
    _pauseUntil = until;
    _paused = true;
    _timer?.cancel();
    _state = 'idle';
    LockScreenManager().unlock();
    if (wasWorking) {
      _activeWorkStartedAt = null;
      unawaited(_local.endWork().then((_) => _refreshLocalStats()));
    } else if (wasRest) {
      unawaited(_local.cancelActiveRest().then((_) => _refreshLocalStats()));
    }
    notifyListeners();

    // 计算暂停时长
    final duration = until.difference(DateTime.now());
    if (duration.isNegative) {
      // 已过期，直接恢复
      resume();
      return;
    }

    // 设置定时器自动恢复
    _pauseUntilTimer?.cancel();
    _pauseUntilTimer = Timer(duration, () {
      _pauseUntil = null;
      _paused = false;
      notifyListeners();
      if (_autoLoop) {
        startWork();
      }
    });
  }

  /// 暂停休息无限期
  void pauseIndefinitely() {
    final wasWorking = _state == 'working';
    final wasRest = _state == 'micro_rest' || _state == 'long_rest';
    _pauseUntil = null;
    _paused = true;
    _timer?.cancel();
    _state = 'idle';
    LockScreenManager().unlock();
    _pauseUntilTimer?.cancel();
    if (wasWorking) {
      _activeWorkStartedAt = null;
      unawaited(_local.endWork().then((_) => _refreshLocalStats()));
    } else if (wasRest) {
      unawaited(_local.cancelActiveRest().then((_) => _refreshLocalStats()));
    }
    notifyListeners();
  }

  /// 重置休息（停止当前状态，重新开始工作循环）
  void resetReminder() {
    _timer?.cancel();
    _pauseUntilTimer?.cancel();
    Future<void>? op;
    if (_state == 'working') {
      _activeWorkStartedAt = null;
      op = _local.endWork();
    } else if (_state == 'micro_rest' || _state == 'long_rest') {
      op = _local.cancelActiveRest();
    }
    _state = 'idle';
    _paused = false;
    _pauseUntil = null;
    _microRestCount = 0;
    _remainingSeconds = 0;
    _totalSeconds = 0;
    LockScreenManager().unlock();
    (op ?? Future.value()).then((_) {
      _refreshLocalStats();
    });
    notifyListeners();
    // 重新开始工作循环
    if (_autoLoop) {
      Future.delayed(const Duration(seconds: 1), () {
        if (_state == 'idle' && _autoLoop) {
          startWork();
        }
      });
    }
  }

  /// 暂停剩余时间的可读文本
  String? get pauseRemainingText {
    if (!_paused || _pauseUntil == null) return null;
    final remaining = _pauseUntil!.difference(DateTime.now());
    if (remaining.isNegative) return null;
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    if (h > 0) return '${h}时${m}分后恢复';
    return '${m}分钟后恢复';
  }

  void stopLoop() {
    _autoLoop = false;
    stopAll();
    _local.saveConfig(
      workMinutes: _workMinutes,
      microRestSeconds: _microRestSeconds,
      longRestMinutes: _longRestMinutes,
      microRestsBeforeLong: _microRestsBeforeLong,
      lockScreenMode: _lockScreenMode,
      notifyBeforeSeconds: _notifyBeforeSec,
      autoLoop: false,
      autoStartOnLaunch: _autoStartOnLaunch,
      microRestStrict: _microRestStrict,
      longRestStrict: _longRestStrict,
      allowPostponeMicro: _allowPostponeMicro,
      allowPostponeLong: _allowPostponeLong,
    );
    notifyListeners();
  }
}
