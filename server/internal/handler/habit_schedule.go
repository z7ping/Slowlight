package handler

import (
	"encoding/json"
	"errors"
	"strings"
	"time"
)

// validateHabitSchedule accepts the empty object for legacy habits.
// New V3 schedules must be structurally valid before touching persistent state.
func validateHabitSchedule(value interface{}) (string, error) {
	if value == nil {
		return "{}", nil
	}
	var raw []byte
	switch v := value.(type) {
	case string:
		raw = []byte(v)
	default:
		var err error
		raw, err = json.Marshal(v)
		if err != nil { return "", errors.New("周期配置不是有效 JSON") }
	}
	var rule struct {
		Version int `json:"version"`
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
		ReminderMode string `json:"reminder_mode"`
		ReminderTime string `json:"reminder_time"`
	}
	if err := json.Unmarshal(raw, &rule); err != nil {
		return "", errors.New("周期配置 JSON 格式错误")
	}
	if len(strings.TrimSpace(string(raw))) == 0 || strings.TrimSpace(string(raw)) == "{}" {
		return "{}", nil
	}
	if rule.Version != 1 || rule.Every < 1 || rule.Every > 999 {
		return "", errors.New("周期配置版本或间隔不正确")
	}
	if _, err := time.Parse("2006-01-02", rule.AnchorDate); err != nil {
		return "", errors.New("起算日期格式不正确")
	}
	clock := func(v string) bool {
		if len(v) != 5 { return false }
		_, err := time.Parse("15:04", v)
		return err == nil
	}
	if !clock(rule.AnchorTime) || !clock(rule.ReminderTime) {
		return "", errors.New("计划或提醒时间不正确")
	}
	if rule.ReminderMode != "off" && rule.ReminderMode != "schedule" && rule.ReminderMode != "daily" {
		return "", errors.New("提醒方式不正确")
	}
	switch rule.Kind {
	case "interval":
		if rule.Unit != "hour" && rule.Unit != "day" && rule.Unit != "week" && rule.Unit != "month" && rule.Unit != "year" {
			return "", errors.New("间隔单位不正确")
		}
		if rule.Unit == "hour" {
			if rule.HourMode != "rolling" && rule.HourMode != "window" { return "", errors.New("小时循环方式不正确") }
			if !clock(rule.WindowStart) || !clock(rule.WindowEnd) || (rule.HourMode == "window" && rule.WindowStart == rule.WindowEnd) {
				return "", errors.New("执行时间范围不正确")
			}
		}
	case "specific":
		if rule.Every > 24 || (rule.Unit != "week" && rule.Unit != "month") { return "", errors.New("指定日期的周期不正确") }
		if rule.Unit == "week" {
			if len(rule.Weekdays)==0 { return "", errors.New("至少选择一个星期") }
			for _,v := range rule.Weekdays { if v<1||v>7 {return "",errors.New("星期数值错误")} }
		} else {
			if !rule.LastDay && len(rule.MonthDays)==0 {return "", errors.New("至少选择一个月内日期")}
			for _,v := range rule.MonthDays {if v<1||v>31{return "", errors.New("月份日期错误")}}
		}
	case "goal":
		if rule.Every > 24 || (rule.Unit!="week"&&rule.Unit!="month") || rule.TargetCount<1 || rule.TargetCount>99 {
			return "", errors.New("周期目标不正确")
		}
		if rule.ReminderMode == "schedule" { return "", errors.New("周期目标不支持计划时点提醒") }
	default:
		return "", errors.New("重复方式不正确")
	}
	return string(raw), nil
}
