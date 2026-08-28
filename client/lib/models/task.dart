import 'todo_list.dart';
import 'tag.dart';

/// Task 仍保持平铺字段作为 API / SQLite 兼容 DTO，
/// 新业务应通过 Facet 读取不同领域概念，避免继续把所有概念堆在 Task 根上。
class Task {
  final int id;
  final int listId;
  final String title;
  final String? description;
  final String priority;
  final DateTime? dueDate;
  final String? dueTime;
  final bool isCompleted;
  final DateTime? completedAt;
  final String repeatType;
  final int repeatInterval;
  final String repeatDays;
  final DateTime? reminderAt;
  final int reminderAdvanceMinutes;
  final DateTime createdAt;
  final TodoList? list;
  final int subtaskCount;
  final int completedSubtask;
  final List<Tag> tags;
  final int? systemTagId;
  final String taskType;
  final int moodBefore;
  final int moodAfter;
  final bool isMilestone;
  final int? relatedQuestId;
  final String obsidianLink;
  final String outputLevel;
  final int version;
  final String syncStatus;
  final DateTime? lastModified;
  final String deviceId;

  Task({
    required this.id,
    required this.listId,
    required this.title,
    this.description,
    required this.priority,
    this.dueDate,
    this.dueTime,
    required this.isCompleted,
    this.completedAt,
    this.repeatType = 'none',
    this.repeatInterval = 1,
    this.repeatDays = '',
    this.reminderAt,
    this.reminderAdvanceMinutes = 0,
    required this.createdAt,
    this.list,
    this.subtaskCount = 0,
    this.completedSubtask = 0,
    this.tags = const [],
    this.systemTagId,
    this.taskType = 'daily',
    this.moodBefore = 0,
    this.moodAfter = 0,
    this.isMilestone = false,
    this.relatedQuestId,
    this.obsidianLink = '',
    this.outputLevel = '',
    this.version = 1,
    this.syncStatus = 'synced',
    this.lastModified,
    this.deviceId = '',
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    DateTime? instant(dynamic raw) {
      if (raw == null || raw.toString().isEmpty) return null;
      return DateTime.tryParse(raw.toString())?.toLocal();
    }

    return Task(
      id: json['id'] ?? 0,
      listId: json['list_id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'],
      priority: json['priority'] ?? 'none',
      // due_date 是纯日历日期，不执行时区转换。
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'].toString())
          : null,
      dueTime: json['due_time'],
      isCompleted: json['is_completed'] == true || json['is_completed'] == 1,
      completedAt: instant(json['completed_at']),
      repeatType: json['repeat_type'] ?? 'none',
      repeatInterval: json['repeat_interval'] ?? 1,
      repeatDays: json['repeat_days'] ?? '',
      reminderAt: instant(json['reminder_at']),
      reminderAdvanceMinutes: json['reminder_advance_minutes'] ?? 0,
      createdAt: instant(json['created_at']) ?? DateTime.now(),
      list: json['list'] != null ? TodoList.fromJson(json['list']) : null,
      subtaskCount: json['subtask_count'] ?? 0,
      completedSubtask: json['completed_subtask'] ?? 0,
      tags: json['tags'] != null
          ? (json['tags'] as List).map((tag) => Tag.fromJson(tag)).toList()
          : const [],
      systemTagId: json['system_tag_id'],
      taskType: json['task_type'] ?? 'daily',
      moodBefore: json['mood_before'] ?? 0,
      moodAfter: json['mood_after'] ?? 0,
      isMilestone: json['is_milestone'] == true || json['is_milestone'] == 1,
      relatedQuestId: json['related_quest_id'],
      obsidianLink: json['obsidian_link'] ?? '',
      outputLevel: json['output_level'] ?? '',
      version: json['version'] ?? 1,
      syncStatus: json['sync_status'] ?? 'synced',
      lastModified: instant(json['last_modified']),
      deviceId: json['device_id'] ?? '',
    );
  }

  TaskSchedule get schedule => TaskSchedule(
        dueDate: dueDate,
        dueTime: dueTime,
        reminderAt: reminderAt,
        reminderAdvanceMinutes: reminderAdvanceMinutes,
      );

  TaskRepeat get repeat => TaskRepeat(
        type: repeatType,
        interval: repeatInterval,
        days: repeatDays,
      );

  TaskReflectionMeta get reflection => TaskReflectionMeta(
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        observationTagId: systemTagId,
      );

  TaskOutcome get outcome => TaskOutcome(
        taskType: taskType,
        isMilestone: isMilestone,
        relatedQuestId: relatedQuestId,
        obsidianLink: obsidianLink,
        outputLevel: outputLevel,
      );

  TaskSyncMeta get sync => TaskSyncMeta(
        version: version,
        status: syncStatus,
        lastModified: lastModified,
        deviceId: deviceId,
      );

  bool get isRepeat => repeat.enabled;
  String get repeatText => repeat.displayText;
}

class TaskSchedule {
  final DateTime? dueDate;
  final String? dueTime;
  final DateTime? reminderAt;
  final int reminderAdvanceMinutes;

  const TaskSchedule({
    required this.dueDate,
    required this.dueTime,
    required this.reminderAt,
    required this.reminderAdvanceMinutes,
  });

  bool get hasDueDate => dueDate != null;
  bool get hasReminder => reminderAt != null || reminderAdvanceMinutes > 0;
}

class TaskRepeat {
  final String type;
  final int interval;
  final String days;

  const TaskRepeat({
    required this.type,
    required this.interval,
    required this.days,
  });

  bool get enabled => type != 'none';

  String get displayText {
    switch (type) {
      case 'daily':
        return interval == 1 ? '每天' : '每${interval}天';
      case 'weekly':
        if (days.isNotEmpty) {
          const dayNames = ['', '一', '二', '三', '四', '五', '六', '日'];
          final values = days.split(',').map(int.tryParse).whereType<int>();
          final text = values
              .where((day) => day >= 1 && day <= 7)
              .map((day) => dayNames[day])
              .join('、');
          if (text.isNotEmpty) return '每周$text';
        }
        return interval == 1 ? '每周' : '每${interval}周';
      case 'monthly':
        return interval == 1 ? '每月' : '每${interval}月';
      case 'yearly':
        return interval == 1 ? '每年' : '每${interval}年';
      default:
        return '';
    }
  }
}

/// 与用户状态/观察有关的元数据，不属于任务调度本身。
class TaskReflectionMeta {
  final int moodBefore;
  final int moodAfter;
  final int? observationTagId;

  const TaskReflectionMeta({
    required this.moodBefore,
    required this.moodAfter,
    required this.observationTagId,
  });

  bool get hasMoodRecord => moodBefore > 0 || moodAfter > 0;
}

/// “主线/支线/成果/里程碑”等长期产出语义。
class TaskOutcome {
  final String taskType;
  final bool isMilestone;
  final int? relatedQuestId;
  final String obsidianLink;
  final String outputLevel;

  const TaskOutcome({
    required this.taskType,
    required this.isMilestone,
    required this.relatedQuestId,
    required this.obsidianLink,
    required this.outputLevel,
  });

  bool get isOutput => outputLevel.isNotEmpty;
  bool get hasExternalNote => obsidianLink.isNotEmpty;
}

class TaskSyncMeta {
  final int version;
  final String status;
  final DateTime? lastModified;
  final String deviceId;

  const TaskSyncMeta({
    required this.version,
    required this.status,
    required this.lastModified,
    required this.deviceId,
  });

  bool get hasPendingChange => status == 'pending' || status == 'conflict';
}
