import 'dart:math';

/// Shared V3 recurrence contract. Empty JSON means a legacy habit.
class HabitScheduleRule {
  final String kind, unit, anchorDate, anchorTime, hourMode;
  final String windowStart, windowEnd, reminderMode, reminderTime;
  final int every, targetCount;
  final List<int> weekdays, monthDays;
  final bool lastDay, sameDayMultiple;

  const HabitScheduleRule({
    required this.anchorDate, this.kind='interval', this.unit='day', this.every=1,
    this.anchorTime='08:00', this.hourMode='window',
    this.windowStart='08:00', this.windowEnd='22:00',
    this.weekdays=const [1,3,5], this.monthDays=const [15],
    this.lastDay=false, this.targetCount=3, this.sameDayMultiple=false,
    this.reminderMode='off', this.reminderTime='09:00',
  });

  static String dayKey(DateTime d) => d.year.toString().padLeft(4,'0')+'-'
      +d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
  static bool clock(String t)=>RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t);
  static int minute(String t)=>int.parse(t.substring(0,2))*60+int.parse(t.substring(3,5));

  factory HabitScheduleRule.fromJson(Map<String,dynamic> json,{String legacyFrequency='daily'}) {
    final legacyUnit=switch(legacyFrequency){'weekly'=>'week','monthly'=>'month','yearly'=>'year',_=>'day'};
    List<int> days(String field,int max,List<int> fallback){
      final raw=json[field];if(raw is! List)return fallback;
      return raw.whereType<int>().where((x)=>x>0&&x<=max).toSet().toList()..sort();
    }
    return HabitScheduleRule(
      anchorDate:json['anchor_date'] as String? ?? dayKey(DateTime.now()),
      anchorTime:json['anchor_time'] as String? ?? '08:00',
      kind:json['kind'] as String? ?? 'interval',unit:json['unit'] as String? ?? legacyUnit,
      every:json['every'] is int ? json['every'] as int : 1,
      hourMode:json['hour_mode'] as String? ?? 'window',
      windowStart:json['window_start'] as String? ?? '08:00',
      windowEnd:json['window_end'] as String? ?? '22:00',
      weekdays:days('weekdays',7,[1,3,5]),monthDays:days('month_days',31,[15]),
      lastDay:json['last_day']==true,targetCount:json['target_count'] is int ? json['target_count'] as int : 3,
      sameDayMultiple:json['same_day_multiple']==true,
      reminderMode:json['reminder_mode'] as String? ?? 'off',
      reminderTime:json['reminder_time'] as String? ?? '09:00',
    );
  }

  Map<String,dynamic> toJson()=>{
    'version':1,'kind':kind,'unit':unit,'every':every,
    'anchor_date':anchorDate,'anchor_time':anchorTime,
    'hour_mode':hourMode,'window_start':windowStart,'window_end':windowEnd,
    'weekdays':weekdays,'month_days':monthDays,'last_day':lastDay,
    'target_count':targetCount,'same_day_multiple':sameDayMultiple,
    'reminder_mode':reminderMode,'reminder_time':reminderTime,
  };

  DateTime? get anchor {
    final d=DateTime.tryParse(anchorDate);
    return d!=null&&dayKey(d)==anchorDate?DateTime(d.year,d.month,d.day):null;
  }

  String? get validationError {
    if(anchor==null||!clock(anchorTime))return '起算日期或时间不正确';
    if(!['interval','specific','goal'].contains(kind))return '重复方式不正确';
    if(every<1||every>(kind=='interval'?999:24))return '周期数值不正确';
    if(kind=='interval') {
      if(!['hour','day','week','month','year'].contains(unit))return '周期单位不正确';
      if(unit=='hour'&&(!['rolling','window'].contains(hourMode)||
          !clock(windowStart)||!clock(windowEnd)||
          (hourMode=='window'&&windowStart==windowEnd)))return '小时执行时段不正确';
    } else if(kind=='specific'){
      if(!['week','month'].contains(unit))return '指定日期仅支持周或月';
      if(unit=='week'&&weekdays.isEmpty)return '至少选择一个星期';
      if(unit=='month'&&monthDays.isEmpty&&!lastDay)return '至少选择一个日期';
    } else if(!['week','month'].contains(unit)||targetCount<1||targetCount>99) {
      return '周期目标不正确';
    }
    if(!['off','schedule','daily'].contains(reminderMode)||!clock(reminderTime)||
       (kind=='goal'&&reminderMode=='schedule'))return '提醒规则不正确';
    return null;
  }

  String get summary{
    final text=switch(unit){'hour'=>'小时','day'=>'天','week'=>'周','month'=>'个月',_=>'年'};
    if(kind=='goal')return '每 $every $text 完成 $targetCount 次';
    if(kind=='specific')return '每 $every $text 指定日期';
    return '每 $every $text';
  }

  /// Calendar preview, not the DST/timezone-aware scheduler.
  List<DateTime> preview([int count=4]){
    final start=anchor;
    if(start==null||validationError!=null||kind=='goal')return [];
    final minutes=minute(anchorTime);
    final hour=minutes~/60,m=minutes%60;
    final result=<DateTime>[];
    if(kind=='interval'){
      for(var i=0;i<count;i++){
        if(unit=='hour'){
          if(hourMode=='rolling'){
            result.add(DateTime(start.year,start.month,start.day,hour,m).add(Duration(hours:i*every)));
          }else{
            final begin=minute(windowStart),end=minute(windowEnd);
            final len=end>begin?end-begin:end+1440-begin;
            final slots=len~/(every*60)+1;
            result.add(DateTime(start.year,start.month,start.day+i~/slots)
                .add(Duration(minutes:begin+(i%slots)*every*60)));
          }
        }else if(unit=='day'||unit=='week'){
          result.add(DateTime(start.year,start.month,start.day+i*every*(unit=='week'?7:1),hour,m));
        }else{
          final offset=i*every*(unit=='year'?12:1);
          final last=DateTime(start.year,start.month+offset+1,0).day;
          result.add(DateTime(start.year,start.month+offset,min(start.day,last),hour,m));
        }
      }
      return result;
    }
    final monday=DateTime.utc(start.year,start.month,start.day-start.weekday+1);
    for(var i=0;i<3660&&result.length<count;i++){
      final d=DateTime(start.year,start.month,start.day+i,hour,m);
      if(unit=='week'){
        final weeks=DateTime.utc(d.year,d.month,d.day).difference(monday).inDays~/7;
        if(weeks%every==0&&weekdays.contains(d.weekday))result.add(d);
      }else{
        final months=(d.year-start.year)*12+d.month-start.month;
        if(months%every==0&&(monthDays.contains(d.day)||
             lastDay&&d.day==DateTime(d.year,d.month+1,0).day))result.add(d);
      }
    }
    return result;
  }

  /// The same recurrence definition powers the editor preview and notifications.
  /// Hourly rolling uses elapsed duration; day/week/month rules use civil dates.
  List<DateTime> nextAfter(DateTime after, {int count=8}) {
    final start=anchor;
    if(start==null||validationError!=null||kind=='goal'||count<=0)return [];
    final result=<DateTime>[];
    final clockMinutes=minute(anchorTime);
    final hh=clockMinutes~/60,mm=clockMinutes%60;
    final from=DateTime(after.year,after.month,after.day);
    final startCivil=DateTime.utc(start.year,start.month,start.day);
    final fromCivil=DateTime.utc(from.year,from.month,from.day);
    final days=fromCivil.difference(startCivil).inDays;
    void add(DateTime value){if(value.isAfter(after)&&result.length<count)result.add(value);}
    if(kind=='interval'){
      if(unit=='hour'){
        if(hourMode=='rolling'){
          final first=DateTime(start.year,start.month,start.day,hh,mm);
          final interval=Duration(hours:every);
          final n=after.isBefore(first)?0:after.difference(first).inMicroseconds~/interval.inMicroseconds+1;
          for(var i=0;i<count;i++)add(first.add(Duration(microseconds:(n+i)*interval.inMicroseconds)));
        }else{
          final begin=minute(windowStart),end=minute(windowEnd);
          final duration=end>begin?end-begin:end+1440-begin;
          final candidate=days>1?days-1:0;
          for(var d=candidate;d<candidate+40&&result.length<count;d++){
            final day=DateTime(start.year,start.month,start.day+d);
            for(var offset=0;offset<=duration&&result.length<count;offset+=every*60){
              add(DateTime(day.year,day.month,day.day,
                begin~/60,begin%60).add(Duration(minutes:offset)));
            }
          }
        }
      }else if(unit=='day'||unit=='week'){
        final stride=every*(unit=='week'?7:1);
        var index=max(0,days~/stride);
        while(result.length<count){
          add(DateTime(start.year,start.month,start.day+index*stride,hh,mm));
          index++;
        }
      }else{
        final stride=every*(unit=='year'?12:1);
        final delta=(after.year-start.year)*12+after.month-start.month;
        var index=max(0,delta~/stride);
        while(result.length<count){
          final month=start.month+index*stride;
          final last=DateTime(start.year,month+1,0).day;
          add(DateTime(start.year,month,min(start.day,last),hh,mm));
          index++;
        }
      }
      return result;
    }
    final monday=DateTime.utc(start.year,start.month,start.day-start.weekday+1);
    for(var d=max(0,days);d<max(0,days)+3660&&result.length<count;d++){
      final value=DateTime(start.year,start.month,start.day+d,hh,mm);
      if(unit=='week'){
        final week=DateTime.utc(value.year,value.month,value.day).difference(monday).inDays~/7;
        if(week%every==0&&weekdays.contains(value.weekday))add(value);
      }else{
        final delta=(value.year-start.year)*12+value.month-start.month;
        if(delta%every==0&&(monthDays.contains(value.day)||
            lastDay&&value.day==DateTime(value.year,value.month+1,0).day))add(value);
      }
    }
    return result;
  }

}
