import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/habit_schedule_rule.dart';

void main() {
  const anchor = '2026-01-31';
  test('旧习惯与 V3 规则可同时读取', () {
    final old = HabitScheduleRule.fromJson({}, legacyFrequency: 'weekly');
    expect(old.unit, 'week');
    final model = Habit.fromJson({
      'id': 1, 'user_id': 1, 'name': '阅读', 'frequency': 'custom',
      'schedule_rule': '{"version":1,"kind":"interval","unit":"day","every":3,"anchor_date":"2026-01-31"}',
      'created_at': '2026-01-31T00:00:00Z',
    });
    expect(model.scheduleRule['every'], 3);
    expect(model.frequencyText, '每 3 天');
  });
  test('每月从原始起算日计算，不随短月份漂移', () {
    const rule = HabitScheduleRule(anchorDate: anchor, every: 1, unit: 'month');
    expect(rule.preview(4).map(HabitScheduleRule.dayKey).toList(),
      ['2026-01-31','2026-02-28','2026-03-31','2026-04-30']);
  });
  test('每两周从起算周选定星期', () {
    const rule = HabitScheduleRule(anchorDate: '2026-10-23',
      kind: 'specific', unit: 'week', every: 2, weekdays: [1,5]);
    expect(rule.preview(3).map(HabitScheduleRule.dayKey).toList(),
      ['2026-10-23','2026-11-02','2026-11-06']);
  });
  test('跨午夜每日窗口不会累计重置漂移', () {
    const rule = HabitScheduleRule(anchorDate:'2026-10-23', unit:'hour', every:2,
      windowStart:'22:00', windowEnd:'06:00');
    expect(rule.preview(6).map((d)=>HabitScheduleRule.dayKey(d)+' '+d.hour.toString()).toList(),
      ['2026-10-23 22','2026-10-24 0','2026-10-24 2','2026-10-24 4','2026-10-24 6','2026-10-24 22']);
  });
  test('每月31号与月末是不同语义', () {
    const specific31 = HabitScheduleRule(anchorDate: '2026-01-01',
      kind:'specific', unit:'month', monthDays:[31], lastDay:false);
    const last = HabitScheduleRule(anchorDate: '2026-01-01',
      kind:'specific', unit:'month', monthDays:[], lastDay:true);
    expect(specific31.preview(3).map(HabitScheduleRule.dayKey).toList(),
      ['2026-01-31','2026-03-31','2026-05-31']);
    expect(last.preview(3).map(HabitScheduleRule.dayKey).toList(),
      ['2026-01-31','2026-02-28','2026-03-31']);
  });
  test('周期目标与缺少星期被校验', () {
    const goal = HabitScheduleRule(anchorDate: anchor, kind:'goal',
      unit:'week', every:2, targetCount:5);
    expect(goal.validationError, isNull);
    expect(goal.summary, '每 2 周 完成 5 次');
    expect(goal.preview(), isEmpty);
    const bad = HabitScheduleRule(anchorDate: anchor, kind:'specific',
      unit:'week', weekdays:[]);
    expect(bad.validationError, contains('星期'));
  });
}
