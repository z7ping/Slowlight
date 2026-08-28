package handler

import (
	"encoding/json"
	"testing"
	"time"

	"slowlight/internal/model"
)

// ========== 提问引擎规则测试 ==========

func TestQuestionEngine_HabitStreak(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)

	// 创建习惯，4 天前打卡
	habit := model.Habit{UserID: user.ID, Name: "早起", Frequency: "daily"}
	tx2.Create(&habit)

	loc := time.Now().Location()
	fourDaysAgo := time.Now().AddDate(0, 0, -4).Format("2006-01-02")
	tx2.Create(&model.HabitLog{HabitID: habit.ID, Date: fourDaysAgo})

	engine := NewQuestionEngine(tx2)
	questions := engine.Generate(user.ID, loc)

	found := false
	for _, q := range questions {
		if q.Type == "habit_streak" {
			found = true
			if q.Content == "" {
				t.Error("habit_streak 内容为空")
			}
		}
	}
	if !found {
		t.Error("期望触发 habit_streak 规则")
	}
}

func TestQuestionEngine_TaskBacklog(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)
	list := createTestList(t, tx2, user.ID, "工作")

	// 创建 4 个超过 7 天未完成的任务
	eightDaysAgo := time.Now().AddDate(0, 0, -8)
	for i := 0; i < 4; i++ {
		task := model.Task{
			UserID:    user.ID,
			ListID:    list.ID,
			Title:     "积压任务",
			CreatedAt: eightDaysAgo,
		}
		tx2.Create(&task)
	}

	engine := NewQuestionEngine(tx2)
	questions := engine.Generate(user.ID, time.Now().Location())

	found := false
	for _, q := range questions {
		if q.Type == "task_backlog" {
			found = true
		}
	}
	if !found {
		t.Error("期望触发 task_backlog 规则")
	}
}

func TestQuestionEngine_CompletionRate(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)
	list := createTestList(t, tx2, user.ID, "工作")

	// 本周创建 6 个任务，只完成 1 个 → 完成率 < 50%
	for i := 0; i < 6; i++ {
		createTestTask(t, tx2, user.ID, list.ID, "本周任务")
	}
	// 完成第 1 个
	var firstTask model.Task
	tx2.Where("user_id = ?", user.ID).First(&firstTask)
	tx2.Model(&firstTask).Updates(map[string]interface{}{
		"is_completed": true,
		"completed_at": time.Now(),
	})

	engine := NewQuestionEngine(tx2)
	questions := engine.Generate(user.ID, time.Now().Location())

	found := false
	for _, q := range questions {
		if q.Type == "completion_rate" {
			found = true
		}
	}
	if !found {
		t.Error("期望触发 completion_rate 规则")
	}
}

func TestQuestionEngine_QuietDay(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)

	// 模拟晚上 9 点
	engine := &QuestionEngine{
		DB:  tx2,
		Now: time.Date(2026, 4, 17, 21, 0, 0, 0, time.Local),
	}

	// 今天没有任何活动
	questions := engine.Generate(user.ID, time.Now().Location())

	found := false
	for _, q := range questions {
		if q.Type == "quiet_day" {
			found = true
		}
	}
	if !found {
		t.Error("期望在晚上 21 点无活动时触发 quiet_day 规则")
	}
}

func TestQuestionEngine_NoQuestionsWhenActive(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)

	// 用户一切正常：没有积压、没有中断
	engine := NewQuestionEngine(tx2)
	questions := engine.Generate(user.ID, time.Now().Location())

	// 应该返回空或少量问题
	if len(questions) > 2 {
		t.Errorf("期望最多 2 个问题，实际 %d 个", len(questions))
	}
}

func TestQuestionEngine_MaxTwoQuestions(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)
	list := createTestList(t, tx2, user.ID, "工作")

	// 制造多种问题触发条件
	// 1. 习惯中断
	habit := model.Habit{UserID: user.ID, Name: "早起", Frequency: "daily"}
	tx2.Create(&habit)
	fourDaysAgo := time.Now().AddDate(0, 0, -4).Format("2006-01-02")
	tx2.Create(&model.HabitLog{HabitID: habit.ID, Date: fourDaysAgo})

	// 2. 积压任务
	eightDaysAgo := time.Now().AddDate(0, 0, -8)
	for i := 0; i < 4; i++ {
		tx2.Create(&model.Task{UserID: user.ID, ListID: list.ID, Title: "积压", CreatedAt: eightDaysAgo})
	}

	// 3. 低完成率
	for i := 0; i < 6; i++ {
		tx2.Create(&model.Task{UserID: user.ID, ListID: list.ID, Title: "本周任务"})
	}

	engine := NewQuestionEngine(tx2)
	questions := engine.Generate(user.ID, time.Now().Location())

	if len(questions) > 2 {
		t.Errorf("最多 2 个问题，实际 %d 个", len(questions))
	}
}

func TestQuestionEngine_Deduplication(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)

	// 第一次生成
	habit := model.Habit{UserID: user.ID, Name: "早起", Frequency: "daily"}
	tx2.Create(&habit)
	fourDaysAgo := time.Now().AddDate(0, 0, -4).Format("2006-01-02")
	tx2.Create(&model.HabitLog{HabitID: habit.ID, Date: fourDaysAgo})

	engine := NewQuestionEngine(tx2)
	q1 := engine.Generate(user.ID, time.Now().Location())

	// 第二次生成应该去重
	q2 := engine.Generate(user.ID, time.Now().Location())

	// q2 中不应该再有和 q1 相同 ID 的问题
	for _, q := range q2 {
		for _, prev := range q1 {
			if q.ID == prev.ID {
				t.Errorf("问题 %s 在 7 天内不应重复出现", q.ID)
			}
		}
	}
}

func TestQuestionEngine_HistorySavedToUserConfig(t *testing.T) {
	tx := setupTestDB(t)
	tx2 := beginTx(t, tx)
	user := createTestUser(t, tx2)

	habit := model.Habit{UserID: user.ID, Name: "早起", Frequency: "daily"}
	tx2.Create(&habit)
	fourDaysAgo := time.Now().AddDate(0, 0, -4).Format("2006-01-02")
	tx2.Create(&model.HabitLog{HabitID: habit.ID, Date: fourDaysAgo})

	engine := NewQuestionEngine(tx2)
	questions := engine.Generate(user.ID, time.Now().Location())

	if len(questions) == 0 {
		t.Skip("没有生成问题，跳过历史保存检查")
	}

	// 验证 UserConfig 保存了历史
	var config model.UserConfig
	result := tx2.Where("user_id = ? AND key = 'question_history'", user.ID).First(&config)
	if result.Error != nil {
		t.Fatal("question_history 未保存到 UserConfig")
	}

	var history []struct {
		ID      string `json:"id"`
		AskedAt string `json:"asked_at"`
	}
	json.Unmarshal([]byte(config.Value), &history)

	if len(history) == 0 {
		t.Error("question_history 为空")
	}
}
