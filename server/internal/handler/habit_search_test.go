package handler

import (
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "net/url"
    "strings"
    "testing"

    "slowlight/internal/model"
)

func TestSearchHabitsByNameOrNoteScopedToCurrentUser(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    other := createTestUser(t, db)
    router := newHabitRouter(handler, userID)

    owned := model.Habit{UserID: userID, Name: "晨间阅读", Frequency: "daily"}
    otherHabit := model.Habit{UserID: other.ID, Name: "私人习惯", Frequency: "daily"}
    nameOnly := model.Habit{UserID: userID, Name: "周报整理", Frequency: "daily"}
    for _, habit := range []*model.Habit{&owned, &otherHabit, &nameOnly} {
        if err := db.Create(habit).Error; err != nil { t.Fatal(err) }
    }
    for _, entry := range []model.HabitLog{
        {HabitID: owned.ID, Date: "2024-01-01", Note: "摘录 100% 的周报素材"},
        {HabitID: owned.ID, Date: "2024-01-02", Note: "摘录 a_b"},
        {HabitID: otherHabit.ID, Date: "2024-01-03", Note: "隐私词不可外泄"},
    } {
        if err := db.Create(&entry).Error; err != nil { t.Fatal(err) }
    }

    query := func(term string) []map[string]interface{} {
        t.Helper()
        w := httptest.NewRecorder()
        request, _ := http.NewRequest("GET",
            "/habits/search?search="+url.QueryEscape(term), nil)
        router.ServeHTTP(w, request)
        if w.Code != http.StatusOK {
            t.Fatalf("search(%q): status=%d body=%s", term, w.Code, w.Body.String())
        }
        var result []map[string]interface{}
        if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
        return result
    }

    byNote := query("100%")
    if len(byNote) != 1 || byNote[0]["id"] != float64(owned.ID) ||
        !strings.Contains(byNote[0]["search_note"].(string), "100%") {
        t.Fatalf("literal percent note search: %+v", byNote)
    }
    byUnderscore := query("a_b")
    if len(byUnderscore) != 1 || byUnderscore[0]["id"] != float64(owned.ID) {
        t.Fatalf("literal underscore note search: %+v", byUnderscore)
    }
    byName := query("周报整理")
    if len(byName) != 1 || byName[0]["id"] != float64(nameOnly.ID) {
        t.Fatalf("name search: %+v", byName)
    }
    if result := query("隐私词"); len(result) != 0 {
        t.Fatalf("cross-account records leaked: %+v", result)
    }
    w := httptest.NewRecorder()
    request, _ := http.NewRequest("GET",
        "/habits/search?search="+strings.Repeat("x", 201), nil)
    router.ServeHTTP(w, request)
    if w.Code != http.StatusBadRequest {
        t.Fatalf("oversized query status=%d", w.Code)
    }
}
