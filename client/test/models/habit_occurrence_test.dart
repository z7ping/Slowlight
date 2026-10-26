import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit_occurrence.dart';
import 'package:slowlight/models/habit_schedule_rule.dart';

void main() {
  test('全天每2小时连续，不因跨午夜重置', () {
    const rule=HabitScheduleRule(anchorDate:'2026-10-23',anchorTime:'08:00',
        unit:'hour',every:2,hourMode:'rolling');
    final before=HabitOccurrence.calculate(rule,DateTime(2026,10,23,23,30));
    final after=HabitOccurrence.calculate(rule,DateTime(2026,10,24,0,30));
    expect(before.key,HabitOccurrence.slotKey(DateTime(2026,10,23,22)));
    expect(after.key,HabitOccurrence.slotKey(DateTime(2026,10,24,0)));
  });
  test('22点到次日6点：次日凌晨归属昨日窗口', () {
    const rule=HabitScheduleRule(anchorDate:'2026-10-23',
      unit:'hour',every:2,hourMode:'window',
      windowStart:'22:00',windowEnd:'06:00');
    final at=HabitOccurrence.calculate(rule,DateTime(2026,10,24,1,30));
    expect(at.key,HabitOccurrence.slotKey(DateTime(2026,10,24,0)));
    expect(() => HabitOccurrence.calculate(rule,DateTime(2026,10,24,12)),
      throwsStateError);
  });
  test('每2周5次目标独立于同一天打卡上限', () {
    const rule=HabitScheduleRule(anchorDate:'2026-10-23',kind:'goal',
      unit:'week',every:2,targetCount:5,sameDayMultiple:true);
    final occurrence=HabitOccurrence.calculate(rule,DateTime(2026,10,24,10),
      requestKey:'event:unique-123456');
    expect(occurrence.periodStart,'2026-10-19');
    expect(occurrence.periodEnd,'2026-11-02');
    expect(occurrence.target,5);
    expect(occurrence.key,'event:unique-123456');
    expect(() => HabitOccurrence.calculate(rule,DateTime(2026,10,24)),
      throwsStateError);
  });
  test('每月31日按原始日期而非累积漂移', () {
    const rule=HabitScheduleRule(anchorDate:'2026-01-31',unit:'month');
    expect(() => HabitOccurrence.calculate(rule,DateTime(2026,2,28)),returnsNormally);
    expect(() => HabitOccurrence.calculate(rule,DateTime(2026,3,28)),throwsStateError);
    expect(() => HabitOccurrence.calculate(rule,DateTime(2026,3,31)),returnsNormally);
  });
  test('下一次计划是未来时点，不返回多年前的第一次', () {
    const rule=HabitScheduleRule(anchorDate:'2026-01-31',unit:'month',every:1);
    expect(rule.nextAfter(DateTime(2026,3,2),count:2)
       .map(HabitScheduleRule.dayKey).toList(),['2026-03-31','2026-04-30']);
  });
  test('指定日期31号跳过短月，月末照常命中', () {
    const thirtyOne=HabitScheduleRule(anchorDate:'2026-01-01',kind:'specific',
      unit:'month',monthDays:[31]);
    const monthEnd=HabitScheduleRule(anchorDate:'2026-01-01',kind:'specific',
      unit:'month',monthDays:[],lastDay:true);
    expect(thirtyOne.nextAfter(DateTime(2026,1,31,23),count:2)
       .map(HabitScheduleRule.dayKey).toList(),['2026-03-31','2026-05-31']);
    expect(monthEnd.nextAfter(DateTime(2026,1,31,23),count:2)
       .map(HabitScheduleRule.dayKey).toList(),['2026-02-28','2026-03-31']);
  });
}
