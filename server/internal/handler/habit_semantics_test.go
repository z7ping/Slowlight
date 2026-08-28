package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"slowlight/internal/model"
)

func TestHabitUpdateCanClearObservationTagAndZeroValues(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)
	tags := createDefaultSystemTags(t, db, userID)

	habit := model.Habit{
		UserID:            userID,
		Name:              "阅读",
		Frequency:         "daily",
		SystemTagID:       &tags[1].ID,
		GenerateTask:      true,
		ShowCheckinDialog: true,
		DurationMin:       30,
		ReminderAt:        `{"enabled":true,"hour":21,"minute":20}`,
	}
	if err := db.Create(&habit).Error; err != nil {
		t.Fatal(err)
	}

	body := []byte(`{"system_tag_id":null,"generate_task":false,"show_checkin_dialog":false,"duration_min":0,"specific_time":"","reminder_at":{"enabled":false}}`)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/habits/"+itoa(habit.ID), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("UpdateHabit 返回 %d: %s", w.Code, w.Body.String())
	}

	var stored model.Habit
	if err := db.First(&stored, habit.ID).Error; err != nil {
		t.Fatal(err)
	}
	if stored.SystemTagID != nil {
		t.Fatalf("system_tag_id 应被清空，实际 %v", *stored.SystemTagID)
	}
	if stored.GenerateTask || stored.ShowCheckinDialog || stored.DurationMin != 0 {
		t.Fatalf("false/0 更新未保留: %+v", stored)
	}
	var reminder struct {
		Enabled *bool `json:"enabled"`
	}
	if err := json.Unmarshal([]byte(stored.ReminderAt), &reminder); err != nil {
		t.Fatalf("reminder_at 不是合法 JSON: %s: %v", stored.ReminderAt, err)
	}
	if reminder.Enabled == nil || *reminder.Enabled {
		t.Fatalf("reminder_at.enabled 应保留 false，实际: %s", stored.ReminderAt)
	}
}

func TestHabitBackfillUsesRequestedCalendarDate(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	var user model.User
	if err := db.First(&user, userID).Error; err != nil {
		t.Fatal(err)
	}
	loc := model.UserLocation(user.Timezone)
	now := time.Now().In(loc)
	requestedDay := now.AddDate(0, 0, -1)
	requestedDate := requestedDay.Format("2006-01-02")

	habit := model.Habit{
		UserID:    userID,
		Name:      "散步",
		Frequency: "daily",
		CreatedAt: now.AddDate(0, 0, -10).UTC(),
	}
	if err := db.Create(&habit).Error; err != nil {
		t.Fatal(err)
	}

	payload, _ := json.Marshal(map[string]interface{}{
		"date":         requestedDate,
		"duration_min": 15,
		"period":       "evening",
		"note":         "补记",
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("Backfill 返回 %d: %s", w.Code, w.Body.String())
	}

	var log model.HabitLog
	if err := db.Where("habit_id = ?", habit.ID).First(&log).Error; err != nil {
		t.Fatal(err)
	}
	if log.Date != requestedDate {
		t.Fatalf("HabitLog.date=%s, 期望 %s", log.Date, requestedDate)
	}

	var event model.BehaviorEvent
	if err := db.Where("user_id = ? AND entity_type = ? AND entity_id = ?", userID, "habit", habit.ID).First(&event).Error; err != nil {
		t.Fatal(err)
	}
	if event.OccurredAt.In(loc).Format("2006-01-02") != requestedDate {
		t.Fatalf("BehaviorEvent 日期=%s, 期望 %s", event.OccurredAt.In(loc).Format("2006-01-02"), requestedDate)
	}
	if !strings.Contains(event.Metadata, requestedDate) {
		t.Fatalf("BehaviorEvent metadata 未记录 habit_date: %s", event.Metadata)
	}
}
