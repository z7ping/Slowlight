package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

func setupReviewTest(t *testing.T) (*gorm.DB, *ReviewHandler, uint) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewReviewHandler(tx)
	user := createTestUser(t, tx)
	return tx, handler, user.ID
}

func newReviewRouter(h *ReviewHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.GET("/review/today", h.GetTodayReview)
	r.GET("/review/today/timeline", h.GetTodayTimeline)
	r.GET("/review/tasks", h.GetTasksReview)
	return r
}

// ========== GetTodayReview ==========

func TestGetTodayReview_EmptyDay(t *testing.T) {
	_, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/today", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var review TodayReview
	json.Unmarshal(w.Body.Bytes(), &review)

	// 空数据：所有计数为 0
	assertEqual(t, review.Facts.HabitChecked, 0, "HabitChecked")
	assertEqual(t, review.Facts.HabitTotal, 0, "HabitTotal")
	assertEqual(t, review.Facts.TaskCompleted, 0, "TaskCompleted")
	assertEqual(t, review.Facts.TaskCreated, 0, "TaskCreated")
	assertEqual(t, review.Facts.FocusMinutes, 0, "FocusMinutes")
	assertEqual(t, review.Facts.FocusCount, 0, "FocusCount")

	// 模式差值全部为 0
	assertEqual(t, review.Patterns.HabitDelta, 0, "HabitDelta")
	assertEqual(t, review.Patterns.TaskDelta, 0, "TaskDelta")
	assertEqual(t, review.Patterns.FocusDelta, 0, "FocusDelta")
}

func TestGetTodayReview_WithHabits(t *testing.T) {
	tx, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)

	// 创建 3 个习惯
	habits := []model.Habit{
		{UserID: userID, Name: "早起", Frequency: "daily"},
		{UserID: userID, Name: "喝水", Frequency: "daily"},
		{UserID: userID, Name: "锻炼", Frequency: "daily"},
	}
	tx.Create(&habits)

	// 今天打卡了 2 个
	today := time.Now().Format("2006-01-02")
	tx.Create(&model.HabitLog{HabitID: habits[0].ID, Date: today})
	tx.Create(&model.HabitLog{HabitID: habits[1].ID, Date: today})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/today", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var review TodayReview
	json.Unmarshal(w.Body.Bytes(), &review)
	assertEqual(t, review.Facts.HabitChecked, 2, "HabitChecked")
	assertEqual(t, review.Facts.HabitTotal, 3, "HabitTotal")
}

func TestGetTodayReview_WithCompletedTasks(t *testing.T) {
	tx, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)

	list := createTestList(t, tx, userID, "工作")
	now := time.Now()

	// 创建 3 个任务，2 个今天完成
	task1 := createTestTask(t, tx, userID, list.ID, "任务1")
	tx.Model(&task1).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
	})
	task2 := createTestTask(t, tx, userID, list.ID, "任务2")
	tx.Model(&task2).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
	})
	createTestTask(t, tx, userID, list.ID, "任务3") // 未完成

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/today", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var review TodayReview
	json.Unmarshal(w.Body.Bytes(), &review)
	assertEqual(t, review.Facts.TaskCompleted, 2, "TaskCompleted")
	assertEqual(t, review.Facts.TaskCreated, 3, "TaskCreated")
}

func TestGetTodayReview_WithFocusSessions(t *testing.T) {
	tx, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)
	tags := createDefaultSystemTags(t, tx, userID)

	now := time.Now()
	// 创建 2 个工作会话的行为事件
	tx.Create(&model.BehaviorEvent{
		UserID:      userID,
		EventType:   "session_ended",
		EntityType:  "session",
		EntityID:    1,
		SystemTagID: &tags[0].ID, // 身体
		DurationMin: 25,
		OccurredAt:  now,
	})
	tx.Create(&model.BehaviorEvent{
		UserID:      userID,
		EventType:   "session_ended",
		EntityType:  "session",
		EntityID:    2,
		SystemTagID: &tags[2].ID, // 产出
		DurationMin: 30,
		OccurredAt:  now,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/today", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var review TodayReview
	json.Unmarshal(w.Body.Bytes(), &review)
	assertEqual(t, review.Facts.FocusMinutes, 55, "FocusMinutes")
	assertEqual(t, review.Facts.FocusCount, 2, "FocusCount")

	// 系统标签分布
	assertEqual(t, len(review.Facts.TagDistribution), 2, "TagDistCount")
}

// ========== GetTasksReview ==========

func TestGetTasksReview_Empty(t *testing.T) {
	_, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/tasks?days=7", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var resp TasksReviewResponse
	json.Unmarshal(w.Body.Bytes(), &resp)
	assertEqual(t, resp.Summary.CompletedCount, 0, "CompletedCount")
	assertEqual(t, resp.Summary.CreatedCount, 0, "CreatedCount")
	assertEqual(t, len(resp.CompletedTasks), 0, "CompletedTasks")
}

func TestGetTasksReview_WithCompletedTasks(t *testing.T) {
	tx, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)

	list := createTestList(t, tx, userID, "工作")
	now := time.Now()
	loc := time.Now().Location()
	todayStr := now.In(loc).Format("2006-01-02")
	startOfToday, _ := time.ParseInLocation("2006-01-02", todayStr, loc)

	// 今天完成 2 个，昨天完成 1 个
	task1 := createTestTask(t, tx, userID, list.ID, "任务1")
	tx.Model(&task1).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
		"task_type":    "main",
		"output_level": "A",
		"is_milestone": false,
	})
	task2 := createTestTask(t, tx, userID, list.ID, "任务2")
	tx.Model(&task2).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
		"task_type":    "daily",
		"output_level": "B",
		"is_milestone": true,
	})
	yesterday := startOfToday.AddDate(0, 0, -1)
	task3 := createTestTask(t, tx, userID, list.ID, "昨日任务")
	tx.Model(&task3).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": yesterday,
		"task_type":    "branch",
		"output_level": "S",
		"is_milestone": false,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/tasks?days=7", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var resp TasksReviewResponse
	json.Unmarshal(w.Body.Bytes(), &resp)
	assertEqual(t, resp.Summary.CompletedCount, 3, "CompletedCount")
	assertEqual(t, resp.Summary.CreatedCount, 3, "CreatedCount")
	assertEqual(t, resp.Summary.TotalDays, 7, "TotalDays")
	assertEqual(t, len(resp.CompletedTasks), 3, "CompletedTasks length")
	assertEqual(t, resp.Distribution.ByTaskType["main"], 1, "ByTaskType main")
	assertEqual(t, resp.Distribution.ByTaskType["daily"], 1, "ByTaskType daily")
	assertEqual(t, resp.Distribution.ByQuality["A"], 1, "ByQuality A")
	assertEqual(t, resp.Distribution.ByQuality["S"], 1, "ByQuality S")
}

func TestGetTasksReview_TodayOnly(t *testing.T) {
	tx, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)

	list := createTestList(t, tx, userID, "工作")
	now := time.Now()

	task := createTestTask(t, tx, userID, list.ID, "今日任务")
	tx.Model(&task).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
	})

	// 昨日任务（days=1 不应包含）
	yesterday := time.Now().AddDate(0, 0, -1)
	task2 := createTestTask(t, tx, userID, list.ID, "昨日任务")
	tx.Model(&task2).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": yesterday,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/tasks?days=1", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")
	var resp TasksReviewResponse
	json.Unmarshal(w.Body.Bytes(), &resp)
	assertEqual(t, resp.Summary.CompletedCount, 1, "CompletedCount should only include today")
}

func TestGetTodayReview_PatternComparison(t *testing.T) {
	tx, handler, userID := setupReviewTest(t)
	r := newReviewRouter(handler, userID)

	list := createTestList(t, tx, userID, "工作")
	now := time.Now()
	loc := time.Now().Location()
	todayStr := now.In(loc).Format("2006-01-02")
	startOfToday, _ := time.ParseInLocation("2006-01-02", todayStr, loc)
	yesterday := startOfToday.AddDate(0, 0, -1).Format("2006-01-02")

	// 创建习惯
	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily"}
	tx.Create(&habit)

	// 今天打卡 1 个
	tx.Create(&model.HabitLog{HabitID: habit.ID, Date: todayStr})
	// 昨天打卡 0 个 → habit_delta = +1

	// 今天完成 1 个任务
	task := createTestTask(t, tx, userID, list.ID, "今日任务")
	tx.Model(&task).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
	})

	// 昨天完成 2 个任务
	for i := 0; i < 2; i++ {
		t := createTestTask(t, tx, userID, list.ID, "昨日任务")
		tx.Model(&t).Updates(map[string]interface{}{
			"is_completed": true,
			"completed_at": yesterday + " 10:00:00",
		})
	}

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/review/today", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var review TodayReview
	json.Unmarshal(w.Body.Bytes(), &review)

	// 今天1个习惯 - 昨天0个 = +1
	assertEqual(t, review.Patterns.HabitDelta, 1, "HabitDelta")
	// 今天1个任务 - 昨天2个 = -1
	assertEqual(t, review.Patterns.TaskDelta, -1, "TaskDelta")
}

func TestGetTodayTimeline_MixedFactsAndCorrections(t *testing.T) {
    tx, h, userID := setupReviewTest(t)
    list := createTestList(t, tx, userID, "读书")
    task := createTestTask(t, tx, userID, list.ID, "读完一章")
    now := time.Now().UTC()
    if err := tx.Model(&task).Updates(map[string]interface{}{
        "is_completed": true, "completed_at": now,
    }).Error; err != nil { t.Fatal(err) }
    habit := model.Habit{UserID: userID, Name: "日记", Frequency: "daily"}
    if err := tx.Create(&habit).Error; err != nil { t.Fatal(err) }
    rows := []model.BehaviorEvent{
        {UserID: userID, EntityType: "task", EntityID: task.ID, EventType: "task_completed", OccurredAt: now.Add(-30*time.Minute)},
        {UserID: userID, EntityType: "habit", EntityID: habit.ID, EventType: "habit_checked", OccurredAt: now.Add(-25*time.Minute)},
        {UserID: userID, EntityType: "session", EntityID: 12, EventType: "session_ended", OccurredAt: now.Add(-20*time.Minute), DurationMin: 25},
        {UserID: userID, EntityType: "session", EntityID: 13, EventType: "session_ended", OccurredAt: now.Add(-15*time.Minute), IsDeleted: true},
        {UserID: userID, EntityType: "session", EntityID: 14, EventType: "session_ended", OccurredAt: now.AddDate(0, 0, -2)},
    }
    for _, row := range rows {
        if err := tx.Create(&row).Error; err != nil { t.Fatal(err) }
    }
    entry := model.Reflection{UserID: userID, EntryType: "observation", Content: "今天读得很投入", Context: "{}", CreatedAt: now.Add(-10*time.Minute)}
    if err := tx.Create(&entry).Error; err != nil { t.Fatal(err) }
    r := newReviewRouter(h, userID)
    w := httptest.NewRecorder()
    req := httptest.NewRequest(http.MethodGet, "/review/today/timeline", nil)
    r.ServeHTTP(w, req)
    if w.Code != http.StatusOK { t.Fatalf("status=%d body=%s", w.Code, w.Body.String()) }
    var result struct { Items []todayTimelineItem `json:"items"` }
    if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
    if len(result.Items) != 4 { t.Fatalf("want 4 real records, got %#v", result.Items) }
    if result.Items[0].Kind != "observation" ||
        result.Items[1].Kind != "session_ended" ||
        result.Items[2].Kind != "habit_checked" ||
        result.Items[3].Kind != "task_completed" {
        t.Fatalf("timeline order mismatch: %#v", result.Items)
    }
}
