package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
)

func TestUnifiedTagLinksAcrossRecordsAndOwnership(t *testing.T) {
	db := beginTx(t, setupTestDB(t))
	user := createTestUser(t, db)
	other := createTestUser(t, db)
	first := model.Tag{UserID: user.ID, Name: uniqueName("学习"), Color: "#123456"}
	second := model.Tag{UserID: user.ID, Name: uniqueName("阅读"), Color: "#123456"}
	foreign := model.Tag{UserID: other.ID, Name: uniqueName("他人标签"), Color: "#123456"}
	for _, item := range []*model.Tag{&first, &second, &foreign} {
		if err := db.Create(item).Error; err != nil { t.Fatal(err) }
	}
	list := model.List{UserID: user.ID, Name: uniqueName("清单")}
	if err := db.Create(&list).Error; err != nil { t.Fatal(err) }
	task := model.Task{UserID: user.ID, ListID: list.ID, Title: "任务"}
	habit := model.Habit{UserID: user.ID, Name: "习惯"}
	session := model.WorkSession{UserID: user.ID, SessionType: "work", StartedAt: time.Now()}
	reflection := model.Reflection{UserID: user.ID, EntryType: "observation", Content: "观察", Context: "{}"}
	for _, item := range []interface{}{&task, &habit, &session, &reflection} {
		if err := db.Create(item).Error; err != nil { t.Fatal(err) }
	}
	handler := NewTagLinksHandler(db)
	router := newTestGin()
	router.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	router.GET("/tag-links/:entity/:id", handler.Get)
	router.PUT("/tag-links/:entity/:id", handler.Put)
	call := func(method, path, body string) *httptest.ResponseRecorder {
		t.Helper()
		w := httptest.NewRecorder()
		req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)
		return w
	}

	for _, e := range []struct{ kind string; id uint }{
		{"task", task.ID}, {"habit", habit.ID},
		{"session", session.ID}, {"observation", reflection.ID},
	} {
		path := fmt.Sprintf("/tag-links/%s/%d", e.kind, e.id)
		body, _ := json.Marshal(gin.H{"tag_ids": []uint{first.ID, second.ID, first.ID}})
		result := call("PUT", path, string(body))
		if result.Code != http.StatusOK { t.Fatalf("%s assign: %d %s", e.kind, result.Code, result.Body.String()) }
		var data struct { TagIDs []uint `json:"tag_ids"` }
		if err := json.Unmarshal(result.Body.Bytes(), &data); err != nil { t.Fatal(err) }
		if len(data.TagIDs) != 2 { t.Fatalf("%s tag IDs: %v", e.kind, data.TagIDs) }
		result = call("GET", path, "")
		if result.Code != http.StatusOK { t.Fatalf("%s read: %d %s", e.kind, result.Code, result.Body.String()) }

		for _, invalid := range []string{`{}`, `{"tag_ids":null}`, `{"tag_ids":"no"}`, fmt.Sprintf(`{"tag_ids":[%d]}`, foreign.ID)} {
			result = call("PUT", path, invalid)
			if result.Code != http.StatusBadRequest { t.Fatalf("%s invalid payload %s: %d", e.kind, invalid, result.Code) }
		}
		result = call("GET", path, "")
		if err := json.Unmarshal(result.Body.Bytes(), &data); err != nil { t.Fatal(err) }
		if len(data.TagIDs) != 2 { t.Fatalf("%s invalid update altered links: %v", e.kind, data.TagIDs) }

		result = call("PUT", path, `{"tag_ids":[]}`)
		if result.Code != http.StatusOK { t.Fatalf("%s clear: %d %s", e.kind, result.Code, result.Body.String()) }
		result = call("GET", path, "")
		if err := json.Unmarshal(result.Body.Bytes(), &data); err != nil { t.Fatal(err) }
		if len(data.TagIDs) != 0 { t.Fatalf("%s clear failed: %v", e.kind, data.TagIDs) }
	}

	// Scoped to the authenticated user even when the other record ID is known.
	otherHabit := model.Habit{UserID: other.ID, Name: "Other habit"}
	if err := db.Create(&otherHabit).Error; err != nil { t.Fatal(err) }
	result := call("GET", fmt.Sprintf("/tag-links/habit/%d", otherHabit.ID), "")
	if result.Code != http.StatusNotFound { t.Fatalf("cross-user read: %d", result.Code) }
	result = call("PUT", fmt.Sprintf("/tag-links/habit/%d", otherHabit.ID), `{"tag_ids":[]}`)
	if result.Code != http.StatusNotFound { t.Fatalf("cross-user write: %d", result.Code) }
}
