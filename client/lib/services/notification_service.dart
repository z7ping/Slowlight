import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../brand.dart';
import '../models/habit_schedule_rule.dart';
import '../repositories/habit_repository.dart';
import 'api_service.dart';
import 'data_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _androidChannelId = 'slowlight_reminders';
  static const _androidIcon = '@mipmap/ic_launcher';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Map<int, Timer> _desktopPending = <int, Timer>{};

  /// 是否是桌面端（Windows/macOS/Linux，排除 Web）
  bool get _isDesktop => !kIsWeb && {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  }.contains(defaultTargetPlatform);

  /// 用户设置的跳转回调（外部可注入，便于测试）
  void Function(int taskId)? onTaskTap;

  /// 通知点击后暂存的任务 ID（HomeScreen 启动后检查并跳转）
  static int? pendingTaskId;

  /// 初始化通知服务
  Future<void> init() async {
    if (_initialized) return;

    // Web 平台不支持本地通知，直接跳过
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    if (_isDesktop) {
      await LocalNotifier.instance.setup(
        appName: kTechnicalAppName,
      );
    } else {
      // 移动端：使用 flutter_local_notifications
      // 初始化时区
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

      const androidSettings = AndroidInitializationSettings(_androidIcon);
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onMobileNotificationTapped,
      );

      // 请求普通通知权限（Android 13+）。精确闹钟属于独立特殊权限，
      // 不在启动时强行跳转系统设置；调度时若未授权则自动降级为非精确提醒。
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    }

    _initialized = true;
  }

  /// 移动端通知点击回调
  void _onMobileNotificationTapped(NotificationResponse response) {
    final action = response.actionId;
    final payload = response.payload;

    if (action == 'snooze_5' && payload != null) {
      final taskId = int.tryParse(payload.replaceFirst('task_', ''));
      if (taskId != null) _snooze(taskId, 5);
    } else if (action == 'snooze_15' && payload != null) {
      final taskId = int.tryParse(payload.replaceFirst('task_', ''));
      if (taskId != null) _snooze(taskId, 15);
    } else if (payload != null && payload.startsWith('task_')) {
      final taskId = int.tryParse(payload.replaceFirst('task_', ''));
      if (taskId != null) {
        pendingTaskId = taskId;
        onTaskTap?.call(taskId);
      }
    }
  }

  /// 延迟提醒
  Future<void> _snooze(int taskId, int minutes) async {
    final scheduledTime = DateTime.now().add(Duration(minutes: minutes));
    await scheduleNotification(
      id: taskId + 100000,
      title: '📋 任务提醒（延迟 $minutes 分钟）',
      body: '稍后提醒的任务',
      scheduledTime: scheduledTime,
      payload: 'task_$taskId',
    );
  }

  /// 立即发送通知
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (_isDesktop) {
      final notification = LocalNotification(
        identifier: 'task_$id',
        title: title,
        body: body,
      );
      // 用 closure 捕获 payload（local_notifier 无 payload 字段）
      final taskPayload = payload;
      notification.onClick = () {
        if (taskPayload != null && taskPayload.startsWith('task_')) {
          final taskId = int.tryParse(taskPayload.replaceFirst('task_', ''));
          if (taskId != null) {
            pendingTaskId = taskId;
            onTaskTap?.call(taskId);
          }
        }
      };
      notification.show();
    } else {
      const androidDetails = AndroidNotificationDetails(
        _androidChannelId,
        '任务提醒',
        channelDescription: '所行映我任务截止提醒',
        icon: _androidIcon,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        actions: [
          AndroidNotificationAction('snooze_5', '5 分钟后', showsUserInterface: false),
          AndroidNotificationAction('snooze_15', '15 分钟后', showsUserInterface: false),
        ],
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _plugin.show(id, title, body, details, payload: payload);
    }
  }

  Future<AndroidScheduleMode> _androidScheduleMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact = await android?.canScheduleExactNotifications();
    return canExact == false
        ? AndroidScheduleMode.inexactAllowWhileIdle
        : AndroidScheduleMode.exactAllowWhileIdle;
  }

  /// 定时通知
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (_isDesktop) {
      // Cancel old desktop reminder when the same ID is rescheduled.
      _desktopPending.remove(id)?.cancel();
      final delay = scheduledTime.difference(DateTime.now());
      if (delay.isNegative) return;
      _desktopPending[id] = Timer(delay, () {
        _desktopPending.remove(id);
        showNotification(id: id, title: title, body: body, payload: payload);
      });
    } else {
      final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
      if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) {
        await showNotification(id: id, title: title, body: body, payload: payload);
        return;
      }
      const androidDetails = AndroidNotificationDetails(
        _androidChannelId,
        '任务提醒',
        channelDescription: '所行映我任务截止提醒',
        icon: _androidIcon,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        actions: [
          AndroidNotificationAction('snooze_5', '5 分钟后', showsUserInterface: false),
          AndroidNotificationAction('snooze_15', '15 分钟后', showsUserInterface: false),
        ],
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: await _androidScheduleMode(),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }

  /// 取消指定通知
  Future<void> cancel(int id) async {
    _desktopPending.remove(id)?.cancel();
    if (!_isDesktop) {
      await _plugin.cancel(id);
      await _plugin.cancel(id + 100000);
    }
    // local_notifier 不支持取消已显示的通知
  }

  /// 取消所有通知
  Future<void> cancelAll() async {
    for (final timer in _desktopPending.values) { timer.cancel(); }
    _desktopPending.clear();
    if (!_isDesktop) {
      await _plugin.cancelAll();
    }
  }

  int _habitNotificationId(int habitId, int index) =>
      1100000000 + (habitId.abs() % 1000000) * 16 + index;

  Future<void> cancelHabitReminders(int habitId) async {
    for (var i=0;i<8;i++) { await cancel(_habitNotificationId(habitId,i)); }
  }

  /// Reminders are independent of logs. Android schedules OS notifications,
  /// Windows uses cancellable in-process timers.
  Future<void> scheduleHabitReminders() async {
    await init();
    final habits = await HabitRepository().getAll();
    final now = DateTime.now();
    for (final habit in habits) {
      await cancelHabitReminders(habit.id);
      if (habit.scheduleRule.isEmpty) continue; // Legacy remains unchanged.
      final rule = HabitScheduleRule.fromJson(habit.scheduleRule, legacyFrequency:habit.frequency);
      if (rule.validationError != null || rule.reminderMode=='off') continue;
      final planned=<DateTime>[];
      if (rule.reminderMode=='daily') {
        final p=HabitScheduleRule.minute(rule.reminderTime);
        for (var day=0;day<9&&planned.length<8;day++) {
          final at=DateTime(now.year,now.month,now.day+day,p~/60,p%60);
          if(at.isAfter(now))planned.add(at);
        }
      } else if (rule.reminderMode=='schedule') {
        planned.addAll(rule.nextAfter(now, count:8));
      }
      for(var i=0;i<planned.length;i++) {
        await scheduleNotification(
          id:_habitNotificationId(habit.id,i),
          title:'习惯提醒',
          body:habit.name,
          scheduledTime:planned[i],
          payload:'habit_'+habit.id.toString(),
        );
      }
    }
  }

  /// 检查并调度待提醒任务
  Future<void> checkAndScheduleReminders() async {
    try {
      final tasks = await DataService().getTodayTasks();
      final now = DateTime.now();

      for (final task in tasks) {
        if (task.reminderAt != null && !task.isCompleted) {
          final advanceMinutes = task.reminderAdvanceMinutes;
          final actualReminderTime = task.reminderAt!.subtract(
            Duration(minutes: advanceMinutes),
          );

          if (actualReminderTime.isAfter(now)) {
            final advanceText = advanceMinutes > 0 ? '（提前 ${advanceMinutes}分钟）' : '';
            await scheduleNotification(
              id: task.id,
              title: '📋 任务提醒$advanceText',
              body: task.title,
              scheduledTime: actualReminderTime,
              payload: 'task_${task.id}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Notification] reminder scheduling failed: ${e.runtimeType}');
    }
    try {
      await scheduleHabitReminders();
    } catch (e) {
      debugPrint('[Notification] habit reminder scheduling failed: ${e.runtimeType}');
    }
  }
}
