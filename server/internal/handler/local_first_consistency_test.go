package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
)

func TestStartSession_AutoEndPreviousCreatesBehaviorEvent(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	previous := model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   time.Now().Add(-10 * time.Minute),
	}
	if err := db.Create(&previous).Error; err != nil {
		t.Fatalf("create previous session: %v", err)
	}

	body, _ := json.Marshal(map[string]interface{}{"session_type": "break"})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/start", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("StartSession returned %d: %s", w.Code, w.Body.String())
	}

	var event model.BehaviorEvent
	if err := db.Where(
		"user_id = ? AND event_type = ? AND entity_type = ? AND entity_id = ?",
		userID, "session_ended", "session", previous.ID,
	).First(&event).Error; err != nil {
		t.Fatalf("auto-ended work session should create BehaviorEvent: %v", err)
	}
	if event.DurationMin < 1 {
		t.Fatalf("DurationMin = %d, expected >= 1", event.DurationMin)
	}
}

func TestCompleteTask_RevertRemovesBehaviorEvent(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "工作")
	task := createTestTask(t, tx, user.ID, list.ID, "一致性测试")

	handler := NewTaskHandler(tx)
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.PATCH("/tasks/:id/complete", handler.CompleteTask)

	taskID := strconv.FormatUint(uint64(task.ID), 10)

	// 第一次：完成任务，应写一条 task_completed。
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+taskID+"/complete", nil)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("complete returned %d: %s", w.Code, w.Body.String())
	}

	var count int64
	tx.Model(&model.BehaviorEvent{}).Where(
		"user_id = ? AND event_type = ? AND entity_type = ? AND entity_id = ?",
		user.ID, "task_completed", "task", task.ID,
	).Count(&count)
	if count != 1 {
		t.Fatalf("completion event count = %d, expected 1", count)
	}

	// 第二次：取消完成，事件应作为纠正被清理，避免 Review 仍把任务算作完成。
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("PATCH", "/tasks/"+taskID+"/complete", nil)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("uncomplete returned %d: %s", w.Code, w.Body.String())
	}

	tx.Model(&model.BehaviorEvent{}).Where(
		"user_id = ? AND event_type = ? AND entity_type = ? AND entity_id = ?",
		user.ID, "task_completed", "task", task.ID,
	).Count(&count)
	if count != 0 {
		t.Fatalf("completion event count after revert = %d, expected 0", count)
	}
}
