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

func setupReminderTest(t *testing.T) (*gorm.DB, *ReminderHandler, uint) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewReminderHandler(tx)
	user := createTestUser(t, tx)
	return tx, handler, user.ID
}

func newReminderRouter(h *ReminderHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.GET("/reminder/config", h.GetConfig)
	r.POST("/reminder/config", h.SaveConfig)
	r.POST("/reminder/start-work", h.StartWork)
	r.POST("/reminder/start-rest", h.StartRest)
	r.POST("/reminder/end-rest", h.EndRest)
	r.POST("/reminder/skip-rest", h.SkipRest)
	r.GET("/reminder/stats", h.GetStats)
	r.GET("/reminder/today", h.GetTodayStats)
	return r
}

func TestGetConfig_Default(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/reminder/config", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetConfig 返回 %d", w.Code)
	}

	var config model.ReminderConfig
	json.Unmarshal(w.Body.Bytes(), &config)

	assertEqual(t, config.WorkMinutes, 25, "WorkMinutes (default)")
	assertEqual(t, config.LongRestMinutes, 5, "LongRestMinutes (default)")
	assertEqual(t, config.AutoLoop, true, "AutoLoop (default)")
}

func TestGetConfig_Saved(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	db.Create(&model.ReminderConfig{
		UserID:         userID,
		WorkMinutes:    25,
		LongRestMinutes: 5,
		AutoLoop:       true,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/reminder/config", nil)
	r.ServeHTTP(w, req)

	var config model.ReminderConfig
	json.Unmarshal(w.Body.Bytes(), &config)

	assertEqual(t, config.WorkMinutes, 25, "WorkMinutes")
	assertEqual(t, config.AutoLoop, true, "AutoLoop")
}

func TestSaveConfig(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	body := map[string]interface{}{
		"work_minutes":     30,
		"long_rest_minutes": 5,
		"auto_loop":        true,
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/config", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("SaveConfig 返回 %d. Body: %s", w.Code, w.Body.String())
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	config := result["config"].(map[string]interface{})
	if config["work_minutes"].(float64) != 30 {
		t.Errorf("work_minutes = %v, 期望 30", config["work_minutes"])
	}
}

func TestSaveConfig_Update(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	db.Create(&model.ReminderConfig{
		UserID:          userID,
		WorkMinutes:     50,
		LongRestMinutes: 10,
	})

	// 只更新 work_minutes
	body := map[string]interface{}{"work_minutes": 25}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/config", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d", w.Code)
	}

	// 验证 rest_minutes 保持不变
	var config model.ReminderConfig
	db.Where("user_id = ?", userID).First(&config)
	assertEqual(t, config.WorkMinutes, 25, "WorkMinutes")
	assertEqual(t, config.LongRestMinutes, 10, "LongRestMinutes (unchanged)")
}

func TestStartWork(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	body := map[string]interface{}{"device": "web"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/start-work", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("StartWork 返回 %d. Body: %s", w.Code, w.Body.String())
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result["message"], "工作阶段已开始", "message")
}

func TestStartWork_AutoEndPrevious(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	// 创建一个未结束的会话（过去1小时开始）
	db.Create(&model.ReminderSession{
		UserID:    userID,
		StartedAt: pastTime(60),
	})

	body := map[string]interface{}{"device": "web"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/start-work", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d", w.Code)
	}

	// 验证新会话已创建
	var count int64
	db.Model(&model.ReminderSession{}).Where("user_id = ?", userID).Count(&count)
	if count != 2 {
		t.Errorf("应有 2 个会话(旧+新), 实际 %d", count)
	}
}

func TestStartRest(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	// 创建一个进行中的工作会话
	db.Create(&model.ReminderSession{
		UserID:    userID,
		StartedAt: pastTime(30),
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/start-rest", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("StartRest 返回 %d. Body: %s", w.Code, w.Body.String())
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result["message"], "休息阶段已开始", "message")
}

func TestStartRest_NoActiveWork(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/start-rest", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("无工作阶段应返回 400, 实际 %d", w.Code)
	}
}

func TestEndRest(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	past := pastTime(30)
	workEnd := pastTime(5)
	db.Create(&model.ReminderSession{
		UserID:       userID,
		StartedAt:    past,
		WorkEndedAt:  &workEnd,
		WorkSeconds:  1500,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/end-rest", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("EndRest 返回 %d. Body: %s", w.Code, w.Body.String())
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result["message"], "休息阶段已结束", "message")
}

func TestEndRest_NoActiveRest(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/end-rest", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("无休息阶段应返回 400, 实际 %d", w.Code)
	}
}

func TestSkipRest(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	past := pastTime(30)
	workEnd := pastTime(5)
	db.Create(&model.ReminderSession{
		UserID:       userID,
		StartedAt:    past,
		WorkEndedAt:  &workEnd,
		WorkSeconds:  1500,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/skip-rest", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("SkipRest 返回 %d", w.Code)
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result["message"], "休息已跳过", "message")
}

func TestSkipRest_NoActiveRest(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reminder/skip-rest", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("无休息阶段应返回 400, 实际 %d", w.Code)
	}
}

func TestGetReminderStats_Empty(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/reminder/stats", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d", w.Code)
	}

	var stats model.ReminderStats
	json.Unmarshal(w.Body.Bytes(), &stats)

	if stats.SessionCount != 0 {
		t.Errorf("空数据 SessionCount = %d, 期望 0", stats.SessionCount)
	}
}

func TestGetReminderTodayStats_Empty(t *testing.T) {
	_, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/reminder/today", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d", w.Code)
	}
}

func TestGetReminderStats_WithSessions(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	// 创建已完成的会话（有 rest_ended_at）
	now := time.Now()
	createdAt := now.Add(-60 * time.Minute)
	startedAt := now.Add(-60 * time.Minute)
	workEnded := now.Add(-30 * time.Minute)
	restEnded := now.Add(-20 * time.Minute)

	db.Create(&model.ReminderSession{
		UserID:       userID,
		StartedAt:    startedAt,
		WorkEndedAt:  &workEnded,
		RestEndedAt:  &restEnded,
		WorkSeconds:  1800,
		RestSeconds:  600,
		SkippedRest:  false,
		CreatedAt:    createdAt,
	})

	db.Create(&model.ReminderSession{
		UserID:       userID,
		StartedAt:    startedAt.Add(-60 * time.Minute),
		WorkEndedAt:  &startedAt,
		RestEndedAt:  &startedAt,
		WorkSeconds:  1200,
		RestSeconds:  0,
		SkippedRest:  true,
		CreatedAt:    createdAt.Add(-60 * time.Minute),
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/reminder/stats?period=all", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetReminderStats 返回 %d", w.Code)
	}

	var stats model.ReminderStats
	json.Unmarshal(w.Body.Bytes(), &stats)

	assertEqual(t, stats.SessionCount, 2, "SessionCount")
	assertEqual(t, stats.SkipCount, 1, "SkipCount")
	if stats.TotalWorkSeconds != 3000 {
		t.Errorf("TotalWorkSeconds = %d, 期望 3000", stats.TotalWorkSeconds)
	}
	if stats.TotalRestSeconds != 600 {
		t.Errorf("TotalRestSeconds = %d, 期望 600", stats.TotalRestSeconds)
	}
}

func TestGetReminderStats_MonthPeriod(t *testing.T) {
	db, handler, userID := setupReminderTest(t)
	r := newReminderRouter(handler, userID)

	now := time.Now()
	startedAt := now.Add(-30 * time.Minute)
	workEnded := now.Add(-10 * time.Minute)
	restEnded := now

	db.Create(&model.ReminderSession{
		UserID:       userID,
		StartedAt:    startedAt,
		WorkEndedAt:  &workEnded,
		RestEndedAt:  &restEnded,
		WorkSeconds:  1200,
		RestSeconds:  600,
		CreatedAt:    now,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/reminder/stats?period=month", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetReminderStats 返回 %d", w.Code)
	}

	var stats model.ReminderStats
	json.Unmarshal(w.Body.Bytes(), &stats)

	assertEqual(t, stats.SessionCount, 1, "SessionCount")
	assertEqual(t, stats.TotalWorkSeconds, 1200, "TotalWorkSeconds")
	assertEqual(t, stats.TotalRestSeconds, 600, "TotalRestSeconds")
}
