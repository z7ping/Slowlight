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

func TestCheckTypeDoesNotInheritPlannedDuration(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    r := newHabitRouter(handler, userID)
    habit := model.Habit{UserID: userID, Name: "不按名称判断", RecordType: "check", DurationMin: 45}
    if err := db.Create(&habit).Error; err != nil { t.Fatal(err) }
    body := []byte(`{"duration_min":45,"note":"完成"}`)
    w := httptest.NewRecorder()
    req, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    r.ServeHTTP(w, req)
    if w.Code != http.StatusOK { t.Fatalf("checkin=%d %s", w.Code, w.Body.String()) }
    var log model.HabitLog
    if err := db.Where("habit_id = ?", habit.ID).First(&log).Error; err != nil { t.Fatal(err) }
    if log.DurationMin != 0 { t.Fatalf("check should have zero duration, got %d", log.DurationMin) }
    var event model.BehaviorEvent
    if err := db.Where("entity_type = ? AND entity_id = ?", "habit", habit.ID).First(&event).Error; err != nil { t.Fatal(err) }
    if event.DurationMin != 0 { t.Fatalf("event should have zero duration, got %d", event.DurationMin) }
}

func TestCountTypeRequiresPositiveValue(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    r := newHabitRouter(handler, userID)
    habit := model.Habit{UserID: userID, Name: "运动", RecordType: "count", RecordUnit: "次"}
    if err := db.Create(&habit).Error; err != nil { t.Fatal(err) }

    request := func(data map[string]interface{}) *httptest.ResponseRecorder {
        payload, _ := json.Marshal(data)
        w := httptest.NewRecorder()
        req, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewReader(payload))
        req.Header.Set("Content-Type", "application/json")
        r.ServeHTTP(w, req)
        return w
    }
    if result := request(map[string]interface{}{"count_value": 0}); result.Code != http.StatusBadRequest {
        t.Fatalf("zero count returned %d", result.Code)
    }
    if result := request(map[string]interface{}{"count_value": 18}); result.Code != http.StatusOK {
        t.Fatalf("positive count returned %d %s", result.Code, result.Body.String())
    }
    var log model.HabitLog
    if err := db.Where("habit_id = ?", habit.ID).First(&log).Error; err != nil { t.Fatal(err) }
    if log.CountValue == nil || *log.CountValue != 18 || log.DurationMin != 0 {
        t.Fatalf("count log invalid: %+v", log)
    }
}

func TestOccurredAtRejectsFutureValue(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    r := newHabitRouter(handler, userID)
    habit := model.Habit{UserID: userID, Name: "起床", RecordType: "check", RecordTimeLabel: "起床时间"}
    if err := db.Create(&habit).Error; err != nil { t.Fatal(err) }
    body, _ := json.Marshal(map[string]string{"occurred_at": time.Now().Add(time.Hour).UTC().Format(time.RFC3339)})
    w := httptest.NewRecorder()
    req, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    r.ServeHTTP(w, req)
    if w.Code != http.StatusBadRequest { t.Fatalf("future occurrence accepted: %d", w.Code) }
}
