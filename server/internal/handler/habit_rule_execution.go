package handler

import (
  "encoding/json"
  "fmt"
  "strings"
  "time"
)

// Habit day boundaries are calendar boundaries in the user's configured zone.
// A fixed-hour rolling interval uses elapsed UTC time; a daily hour window
// resets at its local start wall time, including windows crossing midnight.
type habitRuleExecution struct {
  Kind string `json:"kind"`
  Unit string `json:"unit"`
  Every int `json:"every"`
  AnchorDate string `json:"anchor_date"`
  AnchorTime string `json:"anchor_time"`
  HourMode string `json:"hour_mode"`
  WindowStart string `json:"window_start"`
  WindowEnd string `json:"window_end"`
  Weekdays []int `json:"weekdays"`
  MonthDays []int `json:"month_days"`
  LastDay bool `json:"last_day"`
  TargetCount int `json:"target_count"`
  SameDayMultiple bool `json:"same_day_multiple"`
}
type habitOccurrence struct {
  Key string
  PeriodStart string
  PeriodEnd string
  Target int
  SameDayMultiple bool
  At time.Time
}
func habitRuleFromJSON(raw string) (*habitRuleExecution,error) {
  if strings.TrimSpace(raw)=="" || strings.TrimSpace(raw)=="{}" {return nil,nil}
  var r habitRuleExecution
  if err:=json.Unmarshal([]byte(raw),&r);err!=nil{return nil,err}
  return &r,nil
}
func habitCivilDay(d time.Time) time.Time {
  return time.Date(d.Year(),d.Month(),d.Day(),0,0,0,0,d.Location())
}
func habitCivilDiff(a,b time.Time) int {
  ua:=time.Date(a.Year(),a.Month(),a.Day(),0,0,0,0,time.UTC)
  ub:=time.Date(b.Year(),b.Month(),b.Day(),0,0,0,0,time.UTC)
  return int(ua.Sub(ub).Hours()/24)
}
func habitClockDay(d time.Time,clock string) time.Time{
  var hh,mm int
  fmt.Sscanf(clock,"%d:%d",&hh,&mm)
  return time.Date(d.Year(),d.Month(),d.Day(),hh,mm,0,0,d.Location())
}
func habitMonthDiff(d,start time.Time)int{return (d.Year()-start.Year())*12+int(d.Month())-int(start.Month())}
func habitMonthAnchor(start time.Time,months int) time.Time {
  first:=time.Date(start.Year(),start.Month()+time.Month(months),1,0,0,0,0,start.Location())
  last:=first.AddDate(0,1,-1).Day()
  day:=start.Day()
  if day>last{day=last}
  return first.AddDate(0,0,day-1)
}
func habitContains(values []int,n int)bool{
  for _,v:=range values{if v==n{return true}}
  return false
}
func habitRuleOccurrence(rule *habitRuleExecution, now time.Time, checkDate string, requestKey string)(habitOccurrence,error){
  var out habitOccurrence
  if rule==nil {
    out.Key="day:"+checkDate
    return out,nil
  }
  start,err:=time.ParseInLocation("2006-01-02",rule.AnchorDate,now.Location())
  if err!=nil{return out,fmt.Errorf("习惯起算日期不正确")}
  day,err:=time.ParseInLocation("2006-01-02",checkDate,now.Location())
  if err!=nil{return out,fmt.Errorf("打卡日期不正确")}
  if day.Before(start){return out,fmt.Errorf("打卡日期早于计划起算日期")}
  every:=rule.Every
  if every<1{return out,fmt.Errorf("间隔不正确")}
  if rule.Kind=="goal" {
    base:=start
    var next time.Time
    if rule.Unit=="week" {
      base=start.AddDate(0,0,-(int(start.Weekday())+6)%7)
      weeks:=habitCivilDiff(day,base)/7
      group:=(weeks/every)*every
      base=base.AddDate(0,0,group*7)
      next=base.AddDate(0,0,every*7)
    } else {
      base=time.Date(start.Year(),start.Month(),1,0,0,0,0,now.Location())
      delta:=habitMonthDiff(day,base)
      group:=(delta/every)*every
      base=base.AddDate(0,group,0)
      next=base.AddDate(0,every,0)
    }
    out.PeriodStart=base.Format("2006-01-02")
    out.PeriodEnd=next.Format("2006-01-02")
    out.Target=rule.TargetCount
    out.SameDayMultiple=rule.SameDayMultiple
    if rule.SameDayMultiple {
      if !strings.HasPrefix(requestKey,"event:")||len(requestKey)<14||len(requestKey)>120{return out,fmt.Errorf("同日多次打卡需要独立请求标识")}
      out.Key=requestKey
    }else{
      out.Key="day:"+checkDate
    }
    out.At=now
    return out,nil
  }
  if rule.Kind=="specific"{
    if rule.Unit=="week"{
      startMonday:=start.AddDate(0,0,-(int(start.Weekday())+6)%7)
      weeks:=habitCivilDiff(day,startMonday)/7
      if weeks%every!=0 || !habitContains(rule.Weekdays,(int(day.Weekday())+6)%7+1) {
        return out,fmt.Errorf("该日期不在预定记录日内")
      }
    }else{
      months:=habitMonthDiff(day,start)
      last:=day.AddDate(0,1,-day.Day()).Day()
      if months%every!=0 || !(habitContains(rule.MonthDays,day.Day()) || rule.LastDay&&day.Day()==last){
        return out,fmt.Errorf("该日期不在预定记录日内")
      }
    }
    out.Key="day:"+checkDate
    out.At=habitClockDay(day,rule.AnchorTime)
    return out,nil
  }
  if rule.Unit=="hour"{
    // A date-only historic backfill cannot identify the intended hour slot.
    if checkDate!=now.Format("2006-01-02"){return out,fmt.Errorf("小时习惯不支持仅指定日期补卡")}
    var slot time.Time
    if rule.HourMode=="rolling"{
      first:=habitClockDay(start,rule.AnchorTime)
      since:=now.Sub(first)
      if since<0{return out,fmt.Errorf("尚未到首次计划时间")}
      index:=int64(since/time.Hour)/int64(every)
      slot=first.Add(time.Duration(index*int64(every))*time.Hour)
    }else{
      var best time.Time
      for offset:=0;offset<=1;offset++{
        beginDay:=habitCivilDay(now).AddDate(0,0,-offset)
        if beginDay.Before(start){continue}
        begin:=habitClockDay(beginDay,rule.WindowStart)
        end:=habitClockDay(beginDay,rule.WindowEnd)
        if !end.After(begin){end=end.AddDate(0,0,1)}
        if now.Before(begin)||now.After(end){continue}
        steps:=int(now.Sub(begin)/(time.Duration(every)*time.Hour))
        current:=begin.Add(time.Duration(steps*every)*time.Hour)
        if !current.After(end)&&(!best.After(current)){best=current}
      }
      if best.IsZero(){return out,fmt.Errorf("当前不在小时习惯的执行时段")}
      slot=best
    }
    out.Key="slot:"+slot.UTC().Format("20060102T150405Z")
    out.At=now
    return out,nil
  }
  scheduled:=false
  switch rule.Unit{
  case "day": scheduled=habitCivilDiff(day,start)%every==0
  case "week": scheduled=habitCivilDiff(day,start)%(7*every)==0
  case "month":
    delta:=habitMonthDiff(day,start)
    scheduled=delta>=0&&delta%every==0&&day.Equal(habitMonthAnchor(start,delta))
  case "year":
    delta:=habitMonthDiff(day,start)
    scheduled=delta>=0&&delta%(12*every)==0&&day.Equal(habitMonthAnchor(start,delta))
  }
  if !scheduled {return out,fmt.Errorf("该日期不是计划记录日")}
  out.Key="day:"+checkDate
  out.At=habitClockDay(day,rule.AnchorTime)
  return out,nil
}
