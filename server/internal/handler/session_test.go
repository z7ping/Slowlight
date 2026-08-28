package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

func setupSessionTest(t *testing.T) (*gorm.DB, *SessionHandler, uint) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewSessionHandler(tx)
	user := createTestUser(t, tx)
	return tx, handler, user.ID
}

func newSessionRouter(h *SessionHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.POST("/sessions/start", h.StartSession)
	r.POST("/sessions/end", h.EndSession)
	r.GET("/sessions/active", h.GetActiveSession)
	r.GET("/sessions/stats", h.GetStats)
	r.GET("/sessions/today", h.GetTodayStats)
	return r
}

// pastTime 返回过去 N 分钟的时间
func pastTime(minutes int) time.Time {
	return time.Now().Add(-time.Duration(minutes) * time.Minute)
}

func TestStartSession(t *testing.T) {
	_, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	body := map[string]interface{}{"session_type": "work", "device": "web"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/start", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("StartSession 返回 %d. Body: %s", w.Code, w.Body.String())
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result["message"], "会话已开始", "message")
}

func TestStartSession_InvalidType(t *testing.T) {
	_, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	body := map[string]interface{}{"session_type": "invalid"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/start", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("无效 session_type 应返回 400, 实际 %d", w.Code)
	}
}

func TestStartSession_MissingType(t *testing.T) {
	_, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/start", bytes.NewBufferString(`{}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("缺少 session_type 应返回 400, 实际 %d", w.Code)
	}
}

func TestStartSession_RejectsForeignTask(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	other := createTestUser(t, db)
	list := createTestList(t, db, other.ID, "其他用户清单")
	task := createTestTask(t, db, other.ID, list.ID, "其他用户任务")
	r := newSessionRouter(handler, userID)

	body, _ := json.Marshal(map[string]interface{}{
		"session_type": "work",
		"task_id":      task.ID,
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/start", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("返回 %d, 期望 400. Body: %s", w.Code, w.Body.String())
	}
}

func TestStartSession_AutoEndPrevious(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   pastTime(10),
	})

	body := map[string]interface{}{"session_type": "break"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/start", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d", w.Code)
	}

	// 新起的会话应为唯一活跃会话
	var count int64
	db.Model(&model.WorkSession{}).Where("user_id = ? AND ended_at IS NULL", userID).Count(&count)
	if count != 1 {
		t.Errorf("应有 1 个活跃会话, 实际 %d", count)
	}
}

func TestEndSession(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   pastTime(30),
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/end", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("EndSession 返回 %d", w.Code)
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	assertEqual(t, result["message"], "会话已结束", "message")
	if result["duration"].(float64) <= 0 {
		t.Error("duration 应大于 0")
	}
}

func TestEndSession_NoActiveSession(t *testing.T) {
	_, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/end", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("无活跃会话应返回 400, 实际 %d", w.Code)
	}
}

func TestGetActiveSession_None(t *testing.T) {
	_, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sessions/active", nil)
	r.ServeHTTP(w, req)

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	if result["active"] != false {
		t.Errorf("active = %v, 期望 false", result["active"])
	}
}

func TestGetActiveSession_HasActive(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   pastTime(10),
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sessions/active", nil)
	r.ServeHTTP(w, req)

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	if result["active"] != true {
		t.Errorf("active = %v, 期望 true", result["active"])
	}
}

func TestGetStats_Empty(t *testing.T) {
	_, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sessions/stats", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d", w.Code)
	}
}

func TestGetTodayStats_Empty(t *testing.T) {
	_, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sessions/today", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d", w.Code)
	}
}

func TestGetStats_WithWorkSessions(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	// 创建 2 个工作会话（已结束）
	startedAt1 := time.Now().Add(-90 * time.Minute)
	endedAt1 := time.Now().Add(-60 * time.Minute)
	startedAt2 := time.Now().Add(-45 * time.Minute)
	endedAt2 := time.Now().Add(-15 * time.Minute)

	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt1,
		EndedAt:     &endedAt1,
		DurationSec: 1800,
	})
	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt2,
		EndedAt:     &endedAt2,
		DurationSec: 1800,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sessions/stats?period=all", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetStats 返回 %d", w.Code)
	}

	var stats model.SessionStats
	json.Unmarshal(w.Body.Bytes(), &stats)

	assertEqual(t, stats.WorkCount, 2, "WorkCount")
	assertEqual(t, stats.BreakCount, 0, "BreakCount")
	if stats.TotalWorkSeconds != 3600 {
		t.Errorf("TotalWorkSeconds = %d, 期望 3600", stats.TotalWorkSeconds)
	}
}

func TestGetStats_WithMixedSessions(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	startedAt := time.Now().Add(-30 * time.Minute)
	endedAt := time.Now()

	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt.Add(-30 * time.Minute),
		EndedAt:     &startedAt,
		DurationSec: 1800,
	})
	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "break",
		StartedAt:   startedAt,
		EndedAt:     &endedAt,
		DurationSec: 1800,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sessions/stats?period=all", nil)
	r.ServeHTTP(w, req)

	var stats model.SessionStats
	json.Unmarshal(w.Body.Bytes(), &stats)

	assertEqual(t, stats.WorkCount, 1, "WorkCount")
	assertEqual(t, stats.BreakCount, 1, "BreakCount")
	if stats.TotalWorkSeconds != 1800 {
		t.Errorf("TotalWorkSeconds = %d, 期望 1800", stats.TotalWorkSeconds)
	}
	if stats.TotalBreakSeconds != 1800 {
		t.Errorf("TotalBreakSeconds = %d, 期望 1800", stats.TotalBreakSeconds)
	}
}

func TestGetStats_MonthPeriod(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)

	endedAt := time.Now()
	startedAt := endedAt.Add(-25 * time.Minute)
	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt,
		EndedAt:     &endedAt,
		DurationSec: 1500,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sessions/stats?period=month", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetStats 返回 %d", w.Code)
	}

	var stats model.SessionStats
	json.Unmarshal(w.Body.Bytes(), &stats)
	assertEqual(t, stats.WorkCount, 1, "WorkCount")
}

// ========== 番茄钟打系统标签（PRD 4.4） ==========

func TestEndSession_WithSystemTagFromClient(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)
	tags := createDefaultSystemTags(t, db, userID)

	// 开始一个无任务的会话
	startedAt := time.Now().Add(-25 * time.Minute)
	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt,
	})

	// 结束时传入 system_tag_id
	body := map[string]interface{}{
		"system_tag_id": tags[0].ID, // 身体
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/end", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	// 验证响应中的 session 包含 system_tag_id
	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	sessionData := resp["session"].(map[string]interface{})
	respTagID := uint(sessionData["system_tag_id"].(float64))
	assertEqual(t, respTagID, tags[0].ID, "RespSystemTagID")

	// 验证 behavior_event 记录了 system_tag_id
	var event model.BehaviorEvent
	db.Where("user_id = ? AND event_type = ?", userID, "session_ended").Order("id DESC").First(&event)
	if event.SystemTagID == nil {
		t.Fatal("event.SystemTagID is nil")
	}
	assertEqual(t, *event.SystemTagID, tags[0].ID, "EventSystemTagID")
}

func TestEndSession_InheritSystemTagFromTask(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)
	tags := createDefaultSystemTags(t, db, userID)
	list := createTestList(t, db, userID, "工作")

	// 创建一个有系统标签的任务
	taskID := createTestTask(t, db, userID, list.ID, "写代码").ID
	db.Model(&model.Task{}).Where("id = ?", taskID).Update("system_tag_id", tags[2].ID) // 产出

	// 开始一个关联任务的会话
	startedAt := time.Now().Add(-25 * time.Minute)
	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt,
		TaskID:      &taskID,
	})

	// 结束时不传 system_tag_id → 应自动继承任务的标签
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/end", bytes.NewBufferString("{}"))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	// 验证自动继承了任务的系统标签
	var event model.BehaviorEvent
	db.Where("user_id = ? AND event_type = ?", userID, "session_ended").Order("id DESC").First(&event)
	if event.SystemTagID == nil {
		t.Fatal("event.SystemTagID is nil")
	}
	assertEqual(t, *event.SystemTagID, tags[2].ID, "InheritedSystemTagID")
}

func TestEndSession_ClientOverridesTaskTag(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)
	tags := createDefaultSystemTags(t, db, userID)
	list := createTestList(t, db, userID, "工作")

	// 任务关联"产出"标签
	taskID := createTestTask(t, db, userID, list.ID, "写代码").ID
	db.Model(&model.Task{}).Where("id = ?", taskID).Update("system_tag_id", tags[2].ID)

	// 开始会话
	startedAt := time.Now().Add(-25 * time.Minute)
	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt,
		TaskID:      &taskID,
	})

	// 结束时传入"认知" → 任务有标签时自动继承优先，客户端传入不覆盖
	// PRD: 有关联任务且任务有系统标签 → 自动继承，不打扰用户
	body := map[string]interface{}{
		"system_tag_id": tags[1].ID, // 认知
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/end", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	// 任务标签自动继承优先于客户端传入
	var event model.BehaviorEvent
	db.Where("user_id = ? AND event_type = ?", userID, "session_ended").Order("id DESC").First(&event)
	if event.SystemTagID == nil {
		t.Fatal("event.SystemTagID is nil")
	}
	assertEqual(t, *event.SystemTagID, tags[2].ID, "TaskTagPriority")
}

func TestEndSession_NoTagProvided(t *testing.T) {
	db, handler, userID := setupSessionTest(t)
	r := newSessionRouter(handler, userID)
	createDefaultSystemTags(t, db, userID)

	// 开始一个无任务的会话
	startedAt := time.Now().Add(-25 * time.Minute)
	db.Create(&model.WorkSession{
		UserID:      userID,
		SessionType: "work",
		StartedAt:   startedAt,
	})

	// 结束时不传 system_tag_id，也没有关联任务
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/sessions/end", nil)
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	// 没有标签也没关系，system_tag_id 为 nil
	var event model.BehaviorEvent
	db.Where("user_id = ? AND event_type = ?", userID, "session_ended").Order("id DESC").First(&event)
	if event.SystemTagID != nil {
		t.Errorf("SystemTagID 应为 nil，实际为 %d", *event.SystemTagID)
	}
}
