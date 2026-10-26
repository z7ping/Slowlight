import 'dart:convert';
import 'dart:math';
import 'habit_schedule_rule.dart';

/// V3 client occurrence policy; null rule means a legacy daily log.
class HabitOccurrence {
  final String key;
  final DateTime at;
  final String? periodStart, periodEnd;
  final int target;
  final bool sameDayMultiple;
  const HabitOccurrence(this.key, this.at, {
    this.periodStart, this.periodEnd, this.target=0, this.sameDayMultiple=false,
  });

  static HabitScheduleRule? rule(Object? raw, {String legacyFrequency='daily'}) {
    Object? decoded=raw;
    if(raw is String) {
      try { decoded=jsonDecode(raw); } catch (_) { return null; }
    }
    if(decoded is! Map || decoded.isEmpty) return null;
    return HabitScheduleRule.fromJson(Map<String,dynamic>.from(decoded),
      legacyFrequency:legacyFrequency);
  }

  static int civilDiff(DateTime a,DateTime b)=>
    DateTime.utc(a.year,a.month,a.day).difference(DateTime.utc(b.year,b.month,b.day)).inDays;

  static String slotKey(DateTime d) {
    final u=d.toUtc();
    String p(int x)=>x.toString().padLeft(2,'0');
    return 'slot:'+u.year.toString().padLeft(4,'0')+p(u.month)+p(u.day)+
      'T'+p(u.hour)+p(u.minute)+p(u.second)+'Z';
  }

  static HabitOccurrence calculate(HabitScheduleRule r,DateTime now,{String? date,String? requestKey}){
    if(r.validationError!=null)throw StateError(r.validationError!);
    final anchor=r.anchor!;
    final today=date==null?DateTime(now.year,now.month,now.day):DateTime.tryParse(date);
    if(today==null || (date!=null&&HabitScheduleRule.dayKey(today)!=date))
      throw StateError('打卡日期不正确');
    if(civilDiff(today,anchor)<0)throw StateError('早于起算日期');
    final dateText=HabitScheduleRule.dayKey(today);
    if(r.kind=='goal'){
      DateTime begin,end;
      if(r.unit=='week'){
        final monday=DateTime(anchor.year,anchor.month,anchor.day-anchor.weekday+1);
        final weeks=civilDiff(today,monday)~/7;
        begin=DateTime(monday.year,monday.month,monday.day+(weeks~/r.every)*r.every*7);
        end=DateTime(begin.year,begin.month,begin.day+r.every*7);
      }else{
        final months=(today.year-anchor.year)*12+today.month-anchor.month;
        begin=DateTime(anchor.year,anchor.month+(months~/r.every)*r.every,1);
        end=DateTime(begin.year,begin.month+r.every,1);
      }
      if(r.sameDayMultiple&&(requestKey==null||!requestKey.startsWith('event:')||
          requestKey.length<14||requestKey.length>120))
        throw StateError('同日多次需要独立请求标识');
      return HabitOccurrence(r.sameDayMultiple?requestKey!:'day:'+dateText,now,
        periodStart:HabitScheduleRule.dayKey(begin),
        periodEnd:HabitScheduleRule.dayKey(end),target:r.targetCount,
        sameDayMultiple:r.sameDayMultiple);
    }
    if(r.kind=='specific'){
      bool hit=false;
      if(r.unit=='week'){
        final monday=DateTime(anchor.year,anchor.month,anchor.day-anchor.weekday+1);
        hit=(civilDiff(today,monday)~/7)%r.every==0&&r.weekdays.contains(today.weekday);
      }else{
        final months=(today.year-anchor.year)*12+today.month-anchor.month;
        hit=months%r.every==0&&(r.monthDays.contains(today.day)||
          (r.lastDay&&today.day==DateTime(today.year,today.month+1,0).day));
      }
      if(!hit)throw StateError('该日期不在计划内');
    }else if(r.unit=='hour'){
      if(dateText!=HabitScheduleRule.dayKey(now))
        throw StateError('小时规则需要具体时点，不能仅按日期补卡');
      DateTime? slot;
      if(r.hourMode=='rolling'){
        final mins=HabitScheduleRule.minute(r.anchorTime);
        final first=DateTime(anchor.year,anchor.month,anchor.day,mins~/60,mins%60);
        if(now.isBefore(first))throw StateError('未到首次计划时间');
        final duration=Duration(hours:r.every);
        final n=now.difference(first).inMicroseconds~/duration.inMicroseconds;
        slot=first.add(Duration(microseconds:n*duration.inMicroseconds));
      }else{
        for(var offset=0;offset<=1;offset++){
          final d=DateTime(now.year,now.month,now.day-offset);
          if(civilDiff(d,anchor)<0)continue;
          final a=HabitScheduleRule.minute(r.windowStart),b=HabitScheduleRule.minute(r.windowEnd);
          final begin=DateTime(d.year,d.month,d.day,a~/60,a%60);
          final end=DateTime(d.year,d.month,d.day+(b<=a?1:0),b~/60,b%60);
          if(now.isBefore(begin)||now.isAfter(end))continue;
          final n=now.difference(begin).inMicroseconds~/Duration(hours:r.every).inMicroseconds;
          final choice=begin.add(Duration(hours:n*r.every));
          if(!choice.isAfter(end)&&(slot==null||choice.isAfter(slot)))slot=choice;
        }
        if(slot==null)throw StateError('当前不在执行时段');
      }
      return HabitOccurrence(slotKey(slot!),now);
    }else {
      final delta=civilDiff(today,anchor);
      bool hit=false;
      if(r.unit=='day')hit=delta%r.every==0;
      else if(r.unit=='week')hit=delta%(7*r.every)==0;
      else {
        final months=(today.year-anchor.year)*12+today.month-anchor.month;
        final last=DateTime(anchor.year,anchor.month+months+1,0).day;
        hit=months>=0&&months%(r.every*(r.unit=='year'?12:1))==0&&
          today.day==min(anchor.day,last);
      }
      if(!hit)throw StateError('该日期不在计划内');
    }
    return HabitOccurrence('day:'+dateText,now);
  }
}
