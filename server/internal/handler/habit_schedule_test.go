package handler

import (
 "encoding/json"
 "strings"
 "testing"
)

func TestHabitScheduleValidation(t *testing.T) {
 cases := []struct{name, body string; valid bool}{
  {"legacy", "{}", true},
  {"valid interval", `{"version":1,"kind":"interval","unit":"hour","every":2,"anchor_date":"2026-10-23","anchor_time":"22:00","hour_mode":"window","window_start":"22:00","window_end":"06:00","reminder_mode":"off","reminder_time":"09:00"}`, true},
  {"valid specific", `{"version":1,"kind":"specific","unit":"month","every":1,"anchor_date":"2026-01-31","anchor_time":"08:00","month_days":[31],"last_day":true,"reminder_mode":"off","reminder_time":"09:00"}`, true},
  {"invalid zero", `{"version":1,"kind":"interval","unit":"day","every":0,"anchor_date":"2026-10-23","anchor_time":"08:00","reminder_mode":"off","reminder_time":"09:00"}`, false},
  {"invalid same hour", `{"version":1,"kind":"interval","unit":"hour","every":2,"anchor_date":"2026-10-23","anchor_time":"08:00","hour_mode":"window","window_start":"08:00","window_end":"08:00","reminder_mode":"off","reminder_time":"09:00"}`, false},
  {"invalid month empty", `{"version":1,"kind":"specific","unit":"month","every":1,"anchor_date":"2026-10-23","anchor_time":"08:00","reminder_mode":"off","reminder_time":"09:00"}`, false},
 }
 for _,tc:=range cases {t.Run(tc.name,func(t *testing.T){
  var body map[string]interface{}
  if err:=json.Unmarshal([]byte(tc.body),&body);err!=nil{t.Fatal(err)}
  output,err:=validateHabitSchedule(body)
  if (err==nil)!=tc.valid{t.Fatalf("got %q %v",output,err)}
  if tc.valid && !strings.Contains(output,"{"){t.Fatal("not encoded as JSON")}
 })}
 }
}
