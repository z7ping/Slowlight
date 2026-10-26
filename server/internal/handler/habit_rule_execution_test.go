package handler

import (
 "testing"
 "time"
)

func TestV3OccurrenceAndGoalPeriods(t *testing.T) {
 loc := time.FixedZone("CST",8*3600)
 day := func(y int,m time.Month,d,h,min int)time.Time{return time.Date(y,m,d,h,min,0,0,loc)}
 rolling:=&habitRuleExecution{Kind:"interval",Unit:"hour",Every:2,
  AnchorDate:"2026-10-23",AnchorTime:"08:00",HourMode:"rolling"}
 a,err:=habitRuleOccurrence(rolling,day(2026,10,23,23,30),"2026-10-23","")
 if err!=nil{t.Fatal(err)}
 b,err:=habitRuleOccurrence(rolling,day(2026,10,24,0,30),"2026-10-24","")
 if err!=nil{t.Fatal(err)}
 if a.Key==b.Key{t.Fatal("hour key must change across midnight")}
 window:=&habitRuleExecution{Kind:"interval",Unit:"hour",Every:2,
  AnchorDate:"2026-10-23",AnchorTime:"08:00",HourMode:"window",
  WindowStart:"22:00",WindowEnd:"06:00"}
 first,err:=habitRuleOccurrence(window,day(2026,10,24,1,30),"2026-10-24","")
 if err!=nil||first.Key==""{t.Fatalf("overnight slot %v %v",first,err)}
 if _,err:=habitRuleOccurrence(window,day(2026,10,24,12,0),"2026-10-24","");err==nil{
  t.Fatal("must reject out-of-window check-in")
 }
 month:=&habitRuleExecution{Kind:"interval",Unit:"month",Every:1,
   AnchorDate:"2026-01-31",AnchorTime:"08:00"}
 if _,err:=habitRuleOccurrence(month,day(2026,3,28,12,0),"2026-03-28","");err==nil{
  t.Fatal("monthly 31 must not drift to 28")
 }
 if _,err:=habitRuleOccurrence(month,day(2026,3,31,12,0),"2026-03-31","");err!=nil{
  t.Fatal(err)
 }
 goal:=&habitRuleExecution{Kind:"goal",Unit:"week",Every:2,TargetCount:5,
   AnchorDate:"2026-10-23",AnchorTime:"08:00",SameDayMultiple:true}
 period,err:=habitRuleOccurrence(goal,day(2026,10,24,12,0),"2026-10-24","event:stable-test-id")
 if err!=nil{t.Fatal(err)}
 if period.PeriodStart!="2026-10-19"||period.PeriodEnd!="2026-11-02"||period.Target!=5{
   t.Fatalf("wrong period %+v",period)
 }
 if _,err:=habitRuleOccurrence(goal,day(2026,10,24,12,0),"2026-10-24","");err==nil{
  t.Fatal("same-day multi requires replay-stable key")
 }
}
