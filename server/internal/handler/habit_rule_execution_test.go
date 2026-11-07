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

func TestV3HourWindowDSTUsesElapsedSlotsWithinCivilEnd(t *testing.T) {
 loc, err := time.LoadLocation("America/Los_Angeles")
 if err != nil { t.Fatal(err) }
 window := &habitRuleExecution{
  Kind: "interval", Unit: "hour", Every: 2, AnchorDate: "2026-03-07",
  AnchorTime: "22:00", HourMode: "window",
  WindowStart: "22:00", WindowEnd: "06:00",
 }
 springDay := time.Date(2026,3,8,5,30,0,0,loc)
 got, err := habitRuleOccurrence(window,springDay,"2026-03-08","")
 if err != nil { t.Fatal(err) }
 // 22:00 PST, 00:00 PST, 03:00 PDT, 05:00 PDT.
 expectedSlot := time.Date(2026,3,8,5,0,0,0,loc)
 expectedKey := "slot:"+expectedSlot.UTC().Format("20060102T150405Z")
 if got.Key != expectedKey {
  t.Fatalf("DST spring slot mismatch: got %s, want %s",got.Key,expectedKey)
 }
 afterWindow := time.Date(2026,3,8,7,0,0,0,loc)
 if _,err := habitRuleOccurrence(window,afterWindow,"2026-03-08","");err==nil {
  t.Fatal("DST spring window must not accept time after civil end")
 }
 // Fall-back repeated 01:30 is two different real instants. They must
 // not collapse to one occurrence key.
 fall := &habitRuleExecution{
  Kind: "interval", Unit: "hour", Every: 1, AnchorDate: "2026-10-31",
  AnchorTime: "00:00", HourMode: "window",
  WindowStart: "00:00", WindowEnd: "04:00",
 }
 first := time.Date(2026,11,1,8,30,0,0,time.UTC).In(loc)
 second := time.Date(2026,11,1,9,30,0,0,time.UTC).In(loc)
 a, err := habitRuleOccurrence(fall,first,"2026-11-01","")
 if err != nil { t.Fatal(err) }
 b, err := habitRuleOccurrence(fall,second,"2026-11-01","")
 if err != nil { t.Fatal(err) }
 if a.Key == b.Key { t.Fatalf("repeated wall clock hour lost unique instant: %s",a.Key) }
}
