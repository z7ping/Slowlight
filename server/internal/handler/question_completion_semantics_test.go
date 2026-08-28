package handler

import (
	"strings"
	"testing"
	"time"

	"slowlight/internal/model"
)

func TestQuestionEngine_CompletionRateUsesCreatedCohort(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "工作")

	fixedNow := time.Date(2026, 8, 21, 21, 0, 0, 0, time.Local)
	weekStart := time.Date(2026, 8, 17, 9, 0, 0, 0, time.Local)

	// 本周创建 6 个，其中只有 2 个目前完成。
	for i := 0; i < 6; i++ {
		task := model.Task{
			UserID:    user.ID,
			ListID:    list.ID,
			Title:     "本周 cohort",
			CreatedAt: weekStart.Add(time.Duration(i) * time.Hour),
		}
		if i < 2 {
			task.IsCompleted = true
			completedAt := fixedNow.Add(-time.Duration(i) * time.Hour)
			task.CompletedAt = &completedAt
		}
		tx.Create(&task)
	}

	// 4 个更早创建的任务本周才完成；它们不能进入本周创建 cohort 的分子。
	for i := 0; i < 4; i++ {
		completedAt := fixedNow.Add(-time.Duration(i+3) * time.Hour)
		tx.Create(&model.Task{
			UserID:      user.ID,
			ListID:      list.ID,
			Title:       "旧任务本周完成",
			CreatedAt:   weekStart.AddDate(0, 0, -7),
			IsCompleted: true,
			CompletedAt: &completedAt,
		})
	}

	engine := &QuestionEngine{DB: tx, Now: fixedNow}
	questions := engine.Generate(user.ID, time.Local)

	var found *Question
	for i := range questions {
		if questions[i].Type == "completion_rate" {
			found = &questions[i]
			break
		}
	}
	if found == nil {
		t.Fatal("期望触发 completion_rate 规则")
	}
	if !strings.Contains(found.Content, "本周创建了 6 个任务") ||
		!strings.Contains(found.Content, "其中 2 个目前已完成") {
		t.Fatalf("completion question 使用了错误口径: %s", found.Content)
	}
}
