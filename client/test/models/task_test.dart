import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/models/tag.dart';

void main() {
  group('Task', () {
    final baseJson = {
      'id': 1,
      'list_id': 5,
      'title': '写测试',
      'priority': 'high',
      'is_completed': false,
      'repeat_type': 'none',
      'repeat_interval': 1,
      'repeat_days': '',
      'created_at': '2026-04-15T10:00:00Z',
    };

    group('fromJson', () {
      test('完整字段正常解析', () {
        final task = Task.fromJson({
          ...baseJson,
          'description': '覆盖所有 model',
          'due_date': '2026-04-20',
          'due_time': '14:00',
          'completed_at': null,
          'reminder_at': '2026-04-20T13:00:00Z',
          'subtask_count': 3,
          'completed_subtask': 1,
          'task_type': 'main',
          'mood_before': 2,
          'mood_after': 4,
          'is_milestone': true,
          'related_quest_id': 42,
          'obsidian_link': 'Projects/Slowlight.md',
          'output_level': 'A',
        });

        expect(task.id, 1);
        expect(task.listId, 5);
        expect(task.title, '写测试');
        expect(task.description, '覆盖所有 model');
        expect(task.priority, 'high');
        expect(task.dueDate, DateTime.parse('2026-04-20'));
        expect(task.dueTime, '14:00');
        expect(task.isCompleted, false);
        // fromJson 会把时间点规范化为本地时区的同一时刻
        expect(
          task.reminderAt,
          DateTime.parse('2026-04-20T13:00:00Z').toLocal(),
        );
        expect(task.subtaskCount, 3);
        expect(task.completedSubtask, 1);
        expect(task.taskType, 'main');
        expect(task.moodBefore, 2);
        expect(task.moodAfter, 4);
        expect(task.isMilestone, true);
        expect(task.relatedQuestId, 42);
        expect(task.obsidianLink, 'Projects/Slowlight.md');
        expect(task.outputLevel, 'A');
      });

      test('可选字段缺失时使用默认值', () {
        final task = Task.fromJson(baseJson);

        expect(task.description, isNull);
        expect(task.dueDate, isNull);
        expect(task.dueTime, isNull);
        expect(task.completedAt, isNull);
        expect(task.reminderAt, isNull);
        expect(task.repeatType, 'none');
        expect(task.repeatInterval, 1);
        expect(task.repeatDays, '');
        expect(task.subtaskCount, 0);
        expect(task.completedSubtask, 0);
        expect(task.tags, isEmpty);
        expect(task.taskType, 'daily');
        expect(task.moodBefore, 0);
        expect(task.moodAfter, 0);
        expect(task.isMilestone, false);
        expect(task.relatedQuestId, isNull);
        expect(task.obsidianLink, '');
        expect(task.outputLevel, '');
      });

      test('嵌套 list 解析为 TodoList', () {
        final task = Task.fromJson({
          ...baseJson,
          'list': {'id': 5, 'name': '工作', 'color': '#ff0000', 'created_at': '2026-04-01T00:00:00Z'},
        });

        expect(task.list, isNotNull);
        expect(task.list!.name, '工作');
        expect(task.list!.color, '#ff0000');
      });

      test('嵌套 tags 解析为 List<Tag>', () {
        final task = Task.fromJson({
          ...baseJson,
          'tags': [
            {'id': 1, 'name': '紧急', 'color': '#ff0000', 'created_at': '2026-04-01T00:00:00Z'},
            {'id': 2, 'name': '后端', 'color': '#0000ff', 'created_at': '2026-04-01T00:00:00Z'},
          ],
        });

        expect(task.tags.length, 2);
        expect(task.tags[0].name, '紧急');
        expect(task.tags[1].name, '后端');
      });

      test('is_completed 为 true 时解析正确', () {
        final task = Task.fromJson({
          ...baseJson,
          'is_completed': true,
          'completed_at': '2026-04-15T12:00:00Z',
        });

        expect(task.isCompleted, true);
        expect(
          task.completedAt,
          DateTime.parse('2026-04-15T12:00:00Z').toLocal(),
        );
      });
    });

    group('isRepeat', () {
      test('repeatType 为 none 时返回 false', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'none'});
        expect(task.isRepeat, false);
      });

      test('repeatType 不为 none 时返回 true', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'daily'});
        expect(task.isRepeat, true);
      });
    });

    group('repeatText', () {
      test('daily interval=1 → 每天', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'daily', 'repeat_interval': 1});
        expect(task.repeatText, '每天');
      });

      test('daily interval=3 → 每3天', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'daily', 'repeat_interval': 3});
        expect(task.repeatText, '每3天');
      });

      test('weekly 无 repeatDays → 每周', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'weekly'});
        expect(task.repeatText, '每周');
      });

      test('weekly 有 repeatDays → 每周一、三、五', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'weekly', 'repeat_days': '1,3,5'});
        expect(task.repeatText, '每周一、三、五');
      });

      test('monthly → 每月', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'monthly'});
        expect(task.repeatText, '每月');
      });

      test('yearly interval=2 → 每2年', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'yearly', 'repeat_interval': 2});
        expect(task.repeatText, '每2年');
      });

      test('none → 空字符串', () {
        final task = Task.fromJson({...baseJson, 'repeat_type': 'none'});
        expect(task.repeatText, '');
      });
    });
  });
}
