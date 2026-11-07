package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"slowlight/internal/model"
)

func TestHabitScheduleRoundTripAndInvalidUpdate(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	router := newHabitRouter(handler, userID)
	rule := map[string]interface{}{
		"version": 1, "kind": "specific", "unit": "week", "every": 2,
		"anchor_date": "2026-10-23", "anchor_time": "08:00",
		"weekdays": []int{1, 3, 5}, "reminder_mode": "off", "reminder_time": "09:00",
	}
	body, _ := json.Marshal(map[string]interface{}{"name": "阅读", "frequency": "custom", "schedule_rule": rule})
	request := httptest.NewRequest(http.MethodPost, "/habits", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusCreated { t.Fatalf("create=%d %s", response.Code, response.Body.String()) }
	var created model.Habit
	if err := json.Unmarshal(response.Body.Bytes(), &created); err != nil { t.Fatal(err) }
	var saved map[string]interface{}
	if err := json.Unmarshal([]byte(created.ScheduleRule), &saved); err != nil { t.Fatal(err) }
	if saved["kind"] != "specific" || saved["every"] != float64(2) { t.Fatalf("wrong round-trip: %+v", saved) }
	id := itoa(created.ID)
	bad := []byte(`{"schedule_rule":{"version":1,"kind":"interval","unit":"hour","every":0}}`)
	update := httptest.NewRequest(http.MethodPut, "/habits/"+id, bytes.NewReader(bad))
	update.Header.Set("Content-Type", "application/json")
	rejected := httptest.NewRecorder()
	router.ServeHTTP(rejected, update)
	if rejected.Code != http.StatusBadRequest { t.Fatalf("invalid update=%d %s", rejected.Code, rejected.Body.String()) }
	var unchanged model.Habit
	if err := db.First(&unchanged, created.ID).Error; err != nil { t.Fatal(err) }
	if unchanged.ScheduleRule != created.ScheduleRule { t.Fatal("rejected update mutated schedule") }
}

func TestV3GoalReachedStillAcceptsIndependentRecords(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    router := newHabitRouter(handler, userID)
    // This rule allows independent facts on the same day. Reaching 1/1 is
    // a goal status, not an instruction to discard later real events.
    rule := map[string]interface{}{
        "version": 1, "kind": "goal", "unit": "week", "every": 1,
        "anchor_date": "2026-01-01", "anchor_time": "08:00",
        "target_count": 1, "same_day_multiple": true,
        "reminder_mode": "off", "reminder_time": "09:00",
    }
    rawRule, err := json.Marshal(rule)
    if err != nil { t.Fatal(err) }
    habit := model.Habit{
        UserID: userID, Name: "如实记录", Frequency: "custom",
        ScheduleRule: string(rawRule), RecordType: "check",
        AllowMultiplePerDay: true,
    }
    if err := db.Create(&habit).Error; err != nil { t.Fatal(err) }
    post := func(clientKey, occurrenceKey string) *httptest.ResponseRecorder {
        body, _ := json.Marshal(map[string]interface{}{
            "client_key": clientKey, "occurrence_key": occurrenceKey,
        })
        req := httptest.NewRequest(http.MethodPost, "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewReader(body))
        req.Header.Set("Content-Type", "application/json")
        rec := httptest.NewRecorder()
        router.ServeHTTP(rec, req)
        return rec
    }
    for _, item := range [][2]string{
        {"goal-p05-event-one", "event:goal-p05-one"},
        {"goal-p05-event-one", "event:goal-p05-one"}, // replay
        {"goal-p05-event-two", "event:goal-p05-two"},
    } {
        rec := post(item[0], item[1])
        if rec.Code != http.StatusOK {
            t.Fatalf("goal record %s returned %d: %s", item[0], rec.Code, rec.Body.String())
        }
    }
    var count int64
    if err := db.Model(&model.HabitLog{}).Where("habit_id = ?", habit.ID).Count(&count).Error; err != nil { t.Fatal(err) }
    if count != 2 { t.Fatalf("expected 2 independent facts after 1/1 goal, got %d", count) }
    var events int64
    db.Model(&model.BehaviorEvent{}).Where("entity_type = ? AND entity_id = ? AND event_type = ?", "habit", habit.ID, "habit_checked").Count(&events)
    if events != 2 { t.Fatalf("expected 2 behavior events, got %d", events) }
    list := httptest.NewRecorder()
    router.ServeHTTP(list, httptest.NewRequest(http.MethodGet, "/habits", nil))
    var habits []model.Habit
    if err := json.Unmarshal(list.Body.Bytes(), &habits); err != nil { t.Fatal(err) }
    if len(habits) != 1 || habits[0].PeriodCount != 2 || habits[0].PeriodTarget != 1 ||
        habits[0].CanCheckIn == nil || !*habits[0].CanCheckIn {
        t.Fatalf("reached goal should remain recordable: %+v at %s", habits, time.Now().UTC().Format(time.RFC3339))
    }
}
