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
    expect(model.frequencyText, '每3天');
  });
  test('频率摘要展示具体日期、月末及间隔，不暴露指定日期占位文案', () {
    const weekly = HabitScheduleRule(
      anchorDate: anchor, kind: 'specific', unit: 'week',
      weekdays: [1, 3, 5],
    );
    expect(weekly.summary, '每周一、三、五');

    const biweekly = HabitScheduleRule(
      anchorDate: anchor, kind: 'specific', unit: 'week',
      every: 2, weekdays: [2, 6],
    );
    expect(biweekly.summary, '每2周的周二、六');

    const month = HabitScheduleRule(
      anchorDate: anchor, kind: 'specific', unit: 'month',
      monthDays: [15], lastDay: true,
    );
    expect(month.summary, '每月15日、月末');

    const twoMonths = HabitScheduleRule(
      anchorDate: anchor, kind: 'specific', unit: 'month',
      every: 2, monthDays: [1, 31],
    );
    expect(twoMonths.summary, '每2个月的1日、31日');

    const window = HabitScheduleRule(
      anchorDate: anchor, every: 2, unit: 'hour',
      hourMode: 'window', windowStart: '22:00', windowEnd: '06:00',
    );
    expect(window.summary, '每2小时（22:00–06:00）');
    const rolling = HabitScheduleRule(
      anchorDate: anchor, every: 2, unit: 'hour',
      hourMode: 'rolling',
    );
    expect(rolling.summary, '每2小时');
    const invalid = HabitScheduleRule(
      anchorDate: anchor, kind: 'specific', unit: 'week', weekdays: [],
    );
    expect(invalid.summary, isEmpty);
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
    expect(goal.summary, '每2周完成5次');
    expect(goal.preview(), isEmpty);
    const bad = HabitScheduleRule(anchorDate: anchor, kind:'specific',
      unit:'week', weekdays:[]);
    expect(bad.validationError, contains('星期'));
  });
  test('P05 hourly window preview and reminder use identical slots', () {
    const rule = HabitScheduleRule(anchorDate: '2026-10-23',
      unit: 'hour', every: 2, hourMode: 'window',
      windowStart: '22:00', windowEnd: '06:00');
    final preview = rule.preview(8);
    final reminders = rule.nextAfter(DateTime(2026, 10, 23, 21, 59),
      count: 8);
    expect(reminders, preview);
    expect(preview.map((d) => '${HabitScheduleRule.dayKey(d)} ${d.hour}'),
      ['2026-10-23 22', '2026-10-24 0', '2026-10-24 2',
       '2026-10-24 4', '2026-10-24 6', '2026-10-24 22',
       '2026-10-25 0', '2026-10-25 2']);
  });

  test('P05 next reminder after window ends is next local window start', () {
    const rule = HabitScheduleRule(anchorDate: '2026-01-01',
      unit: 'hour', every: 2, hourMode: 'window',
      windowStart: '22:00', windowEnd: '06:00');
    final found = rule.nextAfter(DateTime(2030, 6, 20, 6, 1),count: 2);
    expect(found, [DateTime(2030, 6, 20, 22), DateTime(2030, 6, 21)]);
  });

  test('P05 DST crossing never proposes a slot after the real local end',
      () {
    const rule = HabitScheduleRule(anchorDate: '2026-03-07',
      unit: 'hour', every: 2, hourMode: 'window',
      windowStart: '22:00', windowEnd: '06:00');
    final end = DateTime(2026, 3, 8, 6);
    final slots = rule.preview(8);
    final inFirstWindow = slots.where((slot) => !slot.isAfter(end)).toList();
    expect(inFirstWindow, isNotEmpty);
    expect(inFirstWindow.first, DateTime(2026, 3, 7, 22));
    expect(inFirstWindow.last.isAfter(end), isFalse);
    expect(slots[inFirstWindow.length], DateTime(2026, 3, 8, 22));
    // Full preview and reminder paths must agree even if the host zone
    // changes its UTC offset inside the overnight window.
    expect(slots, rule.nextAfter(DateTime(2026, 3, 7, 21, 59),count: 8));
  });

  test('P05 every 24 months returns all eight actual future occurrences', () {
    const rule = HabitScheduleRule(
      anchorDate: '2026-01-01', kind: 'specific', unit: 'month',
      every: 24, monthDays: [15],
    );
    final result = rule.nextAfter(DateTime(2025,12,31),count:8);
    expect(result.map(HabitScheduleRule.dayKey).toList(), [
      '2026-01-15','2028-01-15','2030-01-15','2032-01-15',
      '2034-01-15','2036-01-15','2038-01-15','2040-01-15',
    ]);
    expect(rule.preview(8),result);
  });

  test('P05 monthly dates before anchor stay excluded, month end stays distinct', () {
    const rule = HabitScheduleRule(
      anchorDate: '2026-01-15', kind: 'specific', unit: 'month',
      monthDays: [1,31], lastDay: true,
    );
    final result = rule.preview(4).map(HabitScheduleRule.dayKey).toList();
    expect(result, ['2026-01-31','2026-02-01','2026-02-28','2026-03-01']);
  });

  test('P05 a February-only 31st never fabricates an occurrence', () {
    const rule = HabitScheduleRule(
      anchorDate: '2026-02-01', kind: 'specific', unit: 'month',
      every: 24, monthDays: [31],
    );
    expect(rule.nextAfter(DateTime(2026,2,1),count:8), isEmpty);
    expect(rule.preview(),isEmpty);
  });

  test('P05 invalid imported specified days are reported, never normalized', () {
    final invalidWeek = HabitScheduleRule.fromJson({
      'kind': 'specific', 'unit': 'week', 'every': 1,
      'anchor_date': '2026-01-01', 'weekdays': [8],
    });
    expect(invalidWeek.validationError, contains('星期'));
    final missingWeek = HabitScheduleRule.fromJson({
      'kind': 'specific', 'unit': 'week', 'every': 1,
      'anchor_date': '2026-01-01',
    });
    expect(missingWeek.validationError, contains('星期'));
    const invalidMonth = HabitScheduleRule(
      anchorDate: '2026-01-01', kind: 'specific',
      unit: 'month', monthDays: [0],
    );
    expect(invalidMonth.validationError, contains('月份'));
    expect(invalidMonth.nextAfter(DateTime(2025,12,31)), isEmpty);
  });

}
