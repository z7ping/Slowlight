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

func setupAnalyticsTest(t *testing.T) (*gorm.DB, *AnalyticsHandler, uint) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewAnalyticsHandler(tx)
	user := createTestUser(t, tx)
	return tx, handler, user.ID
}

func newAnalyticsRouter(h *AnalyticsHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.GET("/analytics/output", h.GetOutputStats)
	r.GET("/analytics/time-distribution", h.GetTimeDistribution)
	r.GET("/analytics/weekly-review", h.GetWeeklyReview)
	r.GET("/analytics/daily-trend", h.GetDailyTrend)
	return r
}

// ========== GetOutputStats ==========

func TestGetOutputStats_Empty(t *testing.T) {
	_, handler, userID := setupAnalyticsTest(t)
	r := newAnalyticsRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/output", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var stats OutputStats
	json.Unmarshal(w.Body.Bytes(), &stats)
	assertEqual(t, stats.TotalCount, 0, "TotalCount")
}

func TestGetOutputStats_WithOutputs(t *testing.T) {
	tx, handler, userID := setupAnalyticsTest(t)
	list := createTestList(t, tx, userID, "工作")
	r := newAnalyticsRouter(handler, userID)

	now := time.Now()
	// 创建有输出等级的任务
	for _, lvl := range []string{"S", "A", "B", "A"} {
		task := createTestTask(t, tx, userID, list.ID, "输出任务")
		tx.Model(&task).Updates(map[string]interface{}{
			"output_level":  lvl,
			"task_type":     "main",
			"is_completed":  true,
			"completed_at":  now,
			"is_milestone":  lvl == "S",
		})
	}

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/output", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var stats OutputStats
	json.Unmarshal(w.Body.Bytes(), &stats)
	assertEqual(t, stats.TotalCount, 4, "TotalCount")
	assertEqual(t, stats.ByLevel["S"], 1, "S_count")
	assertEqual(t, stats.ByLevel["A"], 2, "A_count")
	assertEqual(t, stats.ByLevel["B"], 1, "B_count")
	assertEqual(t, stats.Milestones, 1, "Milestones")
}

// ========== GetTimeDistribution ==========

func TestGetTimeDistribution_Empty(t *testing.T) {
	_, handler, userID := setupAnalyticsTest(t)
	r := newAnalyticsRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/time-distribution", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var dist TimeDistribution
	json.Unmarshal(w.Body.Bytes(), &dist)
	assertEqual(t, dist.TotalMin, 0, "TotalMin")
	assertEqual(t, len(dist.ByDay), 7, "ByDayCount") // 始终返回 7 天
}

func TestGetTimeDistribution_WithSessions(t *testing.T) {
	tx, handler, userID := setupAnalyticsTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	r := newAnalyticsRouter(handler, userID)

	now := time.Now()
	tx.Create(&model.BehaviorEvent{
		UserID:      userID,
		EventType:   "session_ended",
		EntityType:  "session",
		EntityID:    1,
		SystemTagID: &tags[0].ID,
		DurationMin: 25,
		OccurredAt:  now,
	})
	tx.Create(&model.BehaviorEvent{
		UserID:      userID,
		EventType:   "session_ended",
		EntityType:  "session",
		EntityID:    2,
		SystemTagID: &tags[2].ID,
		DurationMin: 50,
		OccurredAt:  now,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/time-distribution", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var dist TimeDistribution
	json.Unmarshal(w.Body.Bytes(), &dist)
	assertEqual(t, dist.TotalMin, 75, "TotalMin")
	assertEqual(t, len(dist.Tags), 2, "TagCount")
}

// ========== GetWeeklyReview ==========

func TestGetWeeklyReview_Empty(t *testing.T) {
	_, handler, userID := setupAnalyticsTest(t)
	r := newAnalyticsRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/weekly-review", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var review WeeklyReview
	json.Unmarshal(w.Body.Bytes(), &review)
	assertEqual(t, review.HabitChecked, 0, "HabitChecked")
	assertEqual(t, review.TaskCompleted, 0, "TaskCompleted")
	assertEqual(t, review.FocusMinutes, 0, "FocusMinutes")
	assertEqual(t, review.OutputCount, 0, "OutputCount")
	assertEqual(t, len(review.TimeDistribution), 0, "TimeDistEmpty")
}

func TestGetWeeklyReview_WithData(t *testing.T) {
	tx, handler, userID := setupAnalyticsTest(t)
	list := createTestList(t, tx, userID, "工作")
	tags := createDefaultSystemTags(t, tx, userID)
	r := newAnalyticsRouter(handler, userID)

	now := time.Now()

	// 本周习惯打卡
	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily"}
	tx.Create(&habit)
	tx.Create(&model.HabitLog{HabitID: habit.ID, Date: now.Format("2006-01-02")})

	// 本周完成任务
	task := createTestTask(t, tx, userID, list.ID, "本周任务")
	tx.Model(&task).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
		"output_level": "A",
		"task_type":    "main",
	})

	// 本周专注
	tx.Create(&model.BehaviorEvent{
		UserID:      userID,
		EventType:   "session_ended",
		EntityType:  "session",
		EntityID:    1,
		SystemTagID: &tags[0].ID,
		DurationMin: 25,
		OccurredAt:  now,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/weekly-review", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var review WeeklyReview
	json.Unmarshal(w.Body.Bytes(), &review)
	assertEqual(t, review.HabitChecked, 1, "HabitChecked")
	assertEqual(t, review.TaskCompleted, 1, "TaskCompleted")
	assertEqual(t, review.FocusMinutes, 25, "FocusMinutes")
	assertEqual(t, review.OutputCount, 1, "OutputCount")
	assertEqual(t, review.OutputByLvl["A"], 1, "OutputByLvl")
	assertEqual(t, review.WeekStart != "", true, "WeekStart")
}

// ========== GetDailyTrend ==========

func TestGetDailyTrend_Empty(t *testing.T) {
	_, handler, userID := setupAnalyticsTest(t)
	r := newAnalyticsRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/daily-trend", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var resp struct {
		Days []DailyTrendPoint `json:"days"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assertEqual(t, len(resp.Days), 7, "DaysCount")
	// 所有数据应该为 0
	for _, d := range resp.Days {
		if d.TaskCompleted != 0 || d.FocusMinutes != 0 || d.HabitChecked != 0 {
			t.Errorf("Day %s should have zero values", d.Date)
		}
	}
}

func TestGetDailyTrend_WithData(t *testing.T) {
	tx, handler, userID := setupAnalyticsTest(t)
	list := createTestList(t, tx, userID, "工作")
	tags := createDefaultSystemTags(t, tx, userID)
	r := newAnalyticsRouter(handler, userID)

	now := time.Now()
	loc := now.Location()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)

	// 今天完成一个任务
	task := createTestTask(t, tx, userID, list.ID, "今日任务")
	tx.Model(&task).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": now,
		"created_at":   today,
	})

	// 今天的番茄钟
	tx.Create(&model.BehaviorEvent{
		UserID:      userID,
		EventType:   "session_ended",
		EntityType:  "session",
		EntityID:    1,
		SystemTagID: &tags[0].ID,
		DurationMin: 25,
		OccurredAt:  now,
	})

	// 今天的习惯打卡
	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily"}
	tx.Create(&habit)
	tx.Create(&model.HabitLog{HabitID: habit.ID, Date: today.Format("2006-01-02")})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/daily-trend", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var resp struct {
		Days []DailyTrendPoint `json:"days"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assertEqual(t, len(resp.Days), 7, "DaysCount")

	// 最后一个元素是今天
	todayPoint := resp.Days[len(resp.Days)-1]
	assertEqual(t, todayPoint.TaskCompleted, 1, "TodayCompleted")
	assertEqual(t, todayPoint.FocusMinutes, 25, "TodayFocus")
	assertEqual(t, todayPoint.HabitChecked, 1, "TodayHabitChecked")
	assertEqual(t, todayPoint.HabitTotal, 1, "TodayHabitTotal")
}
