import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/today_timeline_item.dart';

void main() {
  test('今日轨迹只接受真实时间并按发生时间排序', () {
    final task = TodayTimelineItem.fromJson({
      'id': 'event:1',
      'kind': 'task_completed',
      'title': '复习笔记',
      'occurred_at': '2026-10-22T08:00:00Z',
    })!;
    final focus = TodayTimelineItem.fromJson({
      'id': 'event:2',
      'kind': 'session_ended',
      'duration_min': 25,
      'occurred_at': '2026-10-22T09:00:00Z',
    })!;
    expect(TodayTimelineItem.fromJson({'id': 'invalid'}), isNull);
    expect(task.description, '完成了复习笔记');
    expect(focus.description, '专注 25 分钟');
    expect(TodayTimelineItem.sorted([task, focus]).first.id, 'event:2');
  });
}
