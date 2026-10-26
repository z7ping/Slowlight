package handler

import (
    "bytes"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"

    "slowlight/internal/model"
)

func TestHabitMultipleRecordsCountIdempotencyAndDelete(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    router := newHabitRouter(handler, userID)
    habit := model.Habit{
        UserID: userID, Name: "喝水", RecordType: "count", RecordUnit: "杯",
        AllowMultiplePerDay: true, GoalPeriod: "day", GoalMetric: "count", GoalValue: 8,
    }
    if err := db.Create(&habit).Error; err != nil { t.Fatal(err) }
    post := func(key string, quantity int) *httptest.ResponseRecorder {
        body, _ := json.Marshal(map[string]interface{}{"client_key": key, "count_value": quantity})
        r := httptest.NewRecorder()
        req := httptest.NewRequest(http.MethodPost, "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewReader(body))
        req.Header.Set("Content-Type", "application/json")
        router.ServeHTTP(r, req)
        return r
    }
    first := post("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 1)
    second := post("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", 2)
    replay := post("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", 2)
    for _, result := range []*httptest.ResponseRecorder{first, second, replay} {
        if result.Code != http.StatusOK { t.Fatalf("checkin %d: %s", result.Code, result.Body.String()) }
    }
    var logs []model.HabitLog
    if err := db.Where("habit_id = ?", habit.ID).Order("id").Find(&logs).Error; err != nil { t.Fatal(err) }
    if len(logs) != 2 || habitProgress(logs, "count") != 3 {
        t.Fatalf("expected 2 distinct logs / 3 cups, got %+v", logs)
    }
    var events []model.BehaviorEvent
    db.Where("event_type = ? AND entity_type = ? AND entity_id = ?",
        "habit_checked", "habit", habit.ID).Find(&events)
    if len(events) != 2 { t.Fatalf("duplicate replay created events: %d", len(events)) }
    list := httptest.NewRecorder()
    router.ServeHTTP(list, httptest.NewRequest(http.MethodGet, "/habits", nil))
    if list.Code != http.StatusOK { t.Fatalf("get habits %d: %s", list.Code, list.Body.String()) }
    var habits []model.Habit
    if err := json.Unmarshal(list.Body.Bytes(), &habits); err != nil { t.Fatal(err) }
    if len(habits) != 1 || habits[0].GoalProgress != 3 || habits[0].GoalMet {
        t.Fatalf("goal should not be complete at 3/8: %+v", habits)
    }
    remove := httptest.NewRecorder()
    router.ServeHTTP(remove, httptest.NewRequest(http.MethodDelete,
        "/habits/"+itoa(habit.ID)+"/logs/"+itoa(logs[0].ID), nil))
    if remove.Code != http.StatusOK { t.Fatalf("delete %d: %s", remove.Code, remove.Body.String()) }
    db.Where("habit_id = ?", habit.ID).Find(&logs)
    if len(logs) != 1 || habitProgress(logs, "count") != 2 {
        t.Fatalf("single deletion affected other log: %+v", logs)
    }
    db.Where("event_type = ? AND entity_type = ? AND entity_id = ?",
        "habit_checked", "habit", habit.ID).Find(&events)
    if len(events) != 1 { t.Fatalf("remaining events=%d", len(events)) }
}

func TestHabitMultiRequiresClientKeyAndLegacyStillOncePerDay(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    router := newHabitRouter(handler, userID)
    multiple := model.Habit{UserID: userID, Name: "多次", RecordType: "check", AllowMultiplePerDay: true}
    legacy := model.Habit{UserID: userID, Name: "旧习惯", RecordType: "check"}
    db.Create(&multiple)
    db.Create(&legacy)
    request := func(habitID uint) *httptest.ResponseRecorder {
        r := httptest.NewRecorder()
        req := httptest.NewRequest(http.MethodPost, "/habits/"+itoa(habitID)+"/checkin",
            bytes.NewBufferString("{}"))
        req.Header.Set("Content-Type", "application/json")
        router.ServeHTTP(r, req)
        return r
    }
    if res := request(multiple.ID); res.Code != http.StatusBadRequest {
        t.Fatalf("multi without stable key should fail, got %d", res.Code)
    }
    if res := request(legacy.ID); res.Code != http.StatusOK {
        t.Fatalf("legacy first=%d", res.Code)
    }
    if res := request(legacy.ID); res.Code != http.StatusOK {
        t.Fatalf("legacy repeated=%d", res.Code)
    }
    var count int64
    db.Model(&model.HabitLog{}).Where("habit_id = ?", legacy.ID).Count(&count)
    if count != 1 { t.Fatalf("legacy duplicated: %d", count) }
}
