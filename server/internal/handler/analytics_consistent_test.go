package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
)

func newConsistentAnalyticsRouter(h *AnalyticsHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) {
		withUser(c, userID)
		c.Next()
	})
	r.GET("/analytics/daily-trend", h.GetDailyTrendConsistent)
	r.GET("/analytics/dimension-summary", h.GetDimensionSummaryConsistent)
	return r
}

func TestGetDailyTrendConsistent_UsesCreatedCohortForRate(t *testing.T) {
	tx, handler, userID := setupAnalyticsTest(t)
	list := createTestList(t, tx, userID, "工作")
	r := newConsistentAnalyticsRouter(handler, userID)

	now := time.Now()
	loc := handler.getUserLocation(userID)
	today := time.Date(now.In(loc).Year(), now.In(loc).Month(), now.In(loc).Day(), 10, 0, 0, 0, loc)
	yesterday := today.AddDate(0, 0, -1)

	createdDone := createTestTask(t, tx, userID, list.ID, "今天创建并完成")
	tx.Model(&createdDone).Updates(map[string]interface{}{
		"created_at": today, "is_completed": true, "completed_at": today.Add(time.Hour),
	})
	createdPending := createTestTask(t, tx, userID, list.ID, "今天创建未完成")
	tx.Model(&createdPending).Updates(map[string]interface{}{
		"created_at": today.Add(time.Minute), "is_completed": false, "completed_at": nil,
	})
	oldCompletedToday := createTestTask(t, tx, userID, list.ID, "昨天创建今天完成")
	tx.Model(&oldCompletedToday).Updates(map[string]interface{}{
		"created_at": yesterday, "is_completed": true, "completed_at": today.Add(2 * time.Hour),
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/daily-trend?days=1", nil)
	r.ServeHTTP(w, req)
	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var response struct {
		Days []DailyTrendPoint `json:"days"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Days) != 1 {
		t.Fatalf("days = %d, want 1", len(response.Days))
	}
	point := response.Days[0]
	assertEqual(t, point.TaskCompleted, 2, "TaskCompleted")
	assertEqual(t, point.TaskTotal, 2, "TaskTotal")
	assertEqual(t, point.CompletionRate, 50, "CompletionRate")
	if point.CompletionRate > 100 {
		t.Fatalf("completion rate must be <= 100, got %d", point.CompletionRate)
	}
}

func TestGetDimensionSummaryConsistent_AggregatesTagsByCanonicalDimension(t *testing.T) {
	tx, handler, userID := setupAnalyticsTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	customBodyTag := model.SystemTag{
		UserID: userID, Name: "跑步", Icon: "🏃", Color: "#52c41a", DimensionKey: model.DimensionBody,
	}
	if err := tx.Create(&customBodyTag).Error; err != nil {
		t.Fatal(err)
	}
	r := newConsistentAnalyticsRouter(handler, userID)

	now := time.Now()
	for index, eventType := range []string{"task_completed", "habit_checked", "session_ended"} {
		tx.Create(&model.BehaviorEvent{
			UserID: userID, EventType: eventType,
			EntityType: []string{"task", "habit", "session"}[index],
			EntityID: uint(index + 1), SystemTagID: &tags[0].ID,
			DurationMin: map[string]int{"session_ended": 25}[eventType], OccurredAt: now,
		})
	}
	// 第二个标签仍归属 body，应聚合到同一个 Dimension，而不是新增第五维度。
	tx.Create(&model.BehaviorEvent{
		UserID: userID, EventType: "task_completed", EntityType: "task",
		EntityID: 99, SystemTagID: &customBodyTag.ID, OccurredAt: now,
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/analytics/dimension-summary", nil)
	r.ServeHTTP(w, req)
	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var response struct {
		Dimensions []canonicalDimensionItem `json:"dimensions"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	assertEqual(t, len(response.Dimensions), 4, "DimensionCount")

	var body *canonicalDimensionItem
	for i := range response.Dimensions {
		if response.Dimensions[i].Key == model.DimensionBody {
			body = &response.Dimensions[i]
			break
		}
	}
	if body == nil {
		t.Fatal("body dimension not found")
	}
	assertEqual(t, body.Value, 4, "Value")
	assertEqual(t, body.Unit, "次活动", "Unit")
}
