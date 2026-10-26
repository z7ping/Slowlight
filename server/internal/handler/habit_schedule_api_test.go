package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

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
