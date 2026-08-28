package handler

import (
	"encoding/json"
	"fmt"
	"time"

	"slowlight/internal/model"

	"gorm.io/gorm"
)

// Question 提问引擎生成的问题
type Question struct {
	ID      string `json:"id"`
	Content string `json:"content"`
	Type    string `json:"type"`
}

// QuestionEngine 提问引擎
type QuestionEngine struct {
	DB  *gorm.DB
	Now time.Time
}

func NewQuestionEngine(db *gorm.DB) *QuestionEngine {
	return &QuestionEngine{DB: db, Now: time.Now()}
}

// Generate 生成今日提问，最多 2 个
func (qe *QuestionEngine) Generate(userID uint, loc *time.Location) []Question {
	questions := make([]Question, 0)
	recentIDs := qe.getRecentQuestionIDs(userID)
	rules := []func(uint, *time.Location) *Question{
		qe.ruleHabitStreak,
		qe.ruleFrequencyChange,
		qe.ruleTaskBacklog,
		qe.ruleCompletionRate,
		qe.ruleTimePreference,
		qe.ruleFocusImbalance,
		qe.ruleNewHabitStruggle,
		qe.ruleQuietDay,
	}

	for _, rule := range rules {
		if len(questions) >= 2 {
			break
		}
		if q := rule(userID, loc); q != nil && !containsString(recentIDs, q.ID) {
			questions = append(questions, *q)
		}
	}
	qe.saveQuestionHistory(userID, questions)
	return questions
}

func (qe *QuestionEngine) ruleHabitStreak(userID uint, loc *time.Location) *Question {
	var habits []model.Habit
	qe.DB.Where("user_id = ?", userID).Find(&habits)
	for _, habit := range habits {
		var lastLog model.HabitLog
		result := qe.DB.Where("habit_id = ?", habit.ID).Order("date DESC").First(&lastLog)
		if result.Error != nil {
			continue
		}
		lastDate, err := time.ParseInLocation("2006-01-02", lastLog.Date, loc)
		if err != nil {
			continue
		}
		daysSince := int(qe.Now.In(loc).Sub(lastDate).Hours() / 24)
		if daysSince >= 3 && daysSince <= 30 {
			return &Question{
				ID:      fmt.Sprintf("habit_streak_%d", habit.ID),
				Content: fmt.Sprintf("你已经 %d 天没有打卡「%s」了", daysSince, habit.Name),
				Type:    "habit_streak",
			}
		}
	}
	return nil
}

func (qe *QuestionEngine) ruleFrequencyChange(userID uint, loc *time.Location) *Question {
	now := qe.Now.In(loc)
	thisMonthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)
	lastMonthStart := thisMonthStart.AddDate(0, -1, 0)
	thisMonthCount := qe.countHabitLogs(userID, thisMonthStart, thisMonthStart.AddDate(0, 1, 0))
	lastMonthCount := qe.countHabitLogs(userID, lastMonthStart, thisMonthStart)
	if lastMonthCount > 0 && thisMonthCount < lastMonthCount {
		diff := lastMonthCount - thisMonthCount
		return &Question{
			ID:      "freq_change_monthly",
			Content: fmt.Sprintf("这个月习惯打卡了 %d 次，比上月少了 %d 次", thisMonthCount, diff),
			Type:    "frequency_change",
		}
	}
	return nil
}

func (qe *QuestionEngine) ruleTaskBacklog(userID uint, loc *time.Location) *Question {
	sevenDaysAgo := qe.Now.AddDate(0, 0, -7)
	var count int64
	qe.DB.Model(&model.Task{}).
		Where("user_id = ? AND is_completed = false AND created_at < ?", userID, sevenDaysAgo).
		Count(&count)
	if count >= 3 {
		return &Question{
			ID:      "task_backlog_7d",
			Content: fmt.Sprintf("你有 %d 个任务超过 7 天没有处理", int(count)),
			Type:    "task_backlog",
		}
	}
	return nil
}

// ruleCompletionRate 使用“本周创建任务 cohort”计算完成率。
// 之前创建、本周才完成的任务只属于本周完成量，不应进入这个比例的分子。
func (qe *QuestionEngine) ruleCompletionRate(userID uint, loc *time.Location) *Question {
	now := qe.Now.In(loc)
	weekday := int(now.Weekday())
	if weekday == 0 {
		weekday = 7
	}
	weekStart := time.Date(now.Year(), now.Month(), now.Day()-weekday+1, 0, 0, 0, 0, loc)

	var created int64
	qe.DB.Model(&model.Task{}).
		Where("user_id = ? AND created_at >= ?", userID, weekStart).
		Count(&created)

	var completed int64
	qe.DB.Model(&model.Task{}).
		Where("user_id = ? AND created_at >= ? AND is_completed = true", userID, weekStart).
		Count(&completed)

	if created >= 5 {
		rate := float64(completed) / float64(created) * 100
		if rate < 50 {
			return &Question{
				ID:      "completion_rate_weekly",
				Content: fmt.Sprintf("本周创建了 %d 个任务，其中 %d 个目前已完成。和你预期的一样吗？", created, completed),
				Type:    "completion_rate",
			}
		}
	}
	return nil
}

func (qe *QuestionEngine) ruleTimePreference(userID uint, loc *time.Location) *Question {
	thirtyDaysAgo := qe.Now.AddDate(0, 0, -30)
	var logs []model.HabitLog
	qe.DB.Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND created_at >= ?", userID, thirtyDaysAgo).Find(&logs)
	if len(logs) < 10 {
		return nil
	}
	morningCount := 0
	eveningCount := 0
	for _, log := range logs {
		hour := log.CreatedAt.In(loc).Hour()
		if hour >= 6 && hour < 12 {
			morningCount++
		} else if hour >= 20 && hour < 24 {
			eveningCount++
		}
	}
	if morningCount > 0 && eveningCount > 0 {
		morningRate := float64(morningCount) / float64(len(logs)) * 100
		eveningRate := float64(eveningCount) / float64(len(logs)) * 100
		if morningRate > 60 && eveningRate < 30 {
			return &Question{
				ID:      "time_preference",
				Content: fmt.Sprintf("过去 30 天，你上午的打卡占 %.0f%%，晚上只有 %.0f%%，你的高效时段在上午？", morningRate, eveningRate),
				Type:    "time_preference",
			}
		}
	}
	return nil
}

func (qe *QuestionEngine) ruleFocusImbalance(userID uint, loc *time.Location) *Question {
	sevenDaysAgo := qe.Now.AddDate(0, 0, -7)
	var tags []model.SystemTag
	qe.DB.Where("user_id = ?", userID).Find(&tags)
	if len(tags) < 4 {
		return nil
	}
	tagMinutes := make(map[uint]int)
	for _, tag := range tags {
		tagMinutes[tag.ID] = 0
	}
	var events []model.BehaviorEvent
	qe.DB.Where("user_id = ? AND event_type = 'session_ended' AND system_tag_id IS NOT NULL AND occurred_at >= ?", userID, sevenDaysAgo).Find(&events)
	for _, e := range events {
		if e.SystemTagID != nil {
			tagMinutes[*e.SystemTagID] += e.DurationMin
		}
	}
	for tagID, minutes := range tagMinutes {
		if minutes != 0 {
			continue
		}
		for _, tag := range tags {
			if tag.ID == tagID {
				return &Question{
					ID:      fmt.Sprintf("focus_imbalance_%d", tagID),
					Content: fmt.Sprintf("过去 7 天，你在「%s%s」维度没有任何专注记录", tag.Icon, tag.Name),
					Type:    "focus_imbalance",
				}
			}
		}
	}
	return nil
}

func (qe *QuestionEngine) ruleNewHabitStruggle(userID uint, loc *time.Location) *Question {
	fourteenDaysAgo := qe.Now.AddDate(0, 0, -14)
	var newHabits []model.Habit
	qe.DB.Where("user_id = ? AND created_at >= ?", userID, fourteenDaysAgo).Find(&newHabits)
	for _, habit := range newHabits {
		var logCount int64
		qe.DB.Model(&model.HabitLog{}).Where("habit_id = ?", habit.ID).Count(&logCount)
		daysSinceCreation := int(qe.Now.Sub(habit.CreatedAt).Hours() / 24)
		if daysSinceCreation >= 3 && logCount <= 1 {
			return &Question{
				ID:      fmt.Sprintf("new_habit_%d", habit.ID),
				Content: fmt.Sprintf("「%s」是 %d 天前创建的，只打卡了 %d 次，要不要降低难度试试？", habit.Name, daysSinceCreation, int(logCount)),
				Type:    "new_habit_struggle",
			}
		}
	}
	return nil
}

func (qe *QuestionEngine) ruleQuietDay(userID uint, loc *time.Location) *Question {
	now := qe.Now.In(loc)
	today := now.Format("2006-01-02")
	startOfToday, _ := time.ParseInLocation("2006-01-02", today, loc)
	endOfToday := startOfToday.Add(24 * time.Hour)
	if now.Hour() < 20 {
		return nil
	}

	var taskCount int64
	qe.DB.Model(&model.Task{}).
		Where("user_id = ? AND (created_at >= ? AND created_at < ? OR (is_completed = true AND completed_at >= ? AND completed_at < ?))", userID, startOfToday, endOfToday, startOfToday, endOfToday).
		Count(&taskCount)
	var habitCount int64
	qe.DB.Model(&model.HabitLog{}).
		Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND date = ?", userID, today).
		Count(&habitCount)
	var sessionCount int64
	qe.DB.Model(&model.BehaviorEvent{}).
		Where("user_id = ? AND event_type = 'session_ended' AND occurred_at >= ? AND occurred_at < ?", userID, startOfToday, endOfToday).
		Count(&sessionCount)
	if taskCount == 0 && habitCount == 0 && sessionCount == 0 {
		return &Question{
			ID:      "quiet_day",
			Content: "今天还没有任何记录，有什么需要调整的吗？",
			Type:    "quiet_day",
		}
	}
	return nil
}

func (qe *QuestionEngine) countHabitLogs(userID uint, start, end time.Time) int {
	var count int64
	qe.DB.Model(&model.HabitLog{}).
		Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND created_at >= ? AND created_at < ?", userID, start, end).
		Count(&count)
	return int(count)
}

func (qe *QuestionEngine) getRecentQuestionIDs(userID uint) []string {
	var config model.UserConfig
	result := qe.DB.Where("user_id = ? AND key = 'question_history'", userID).First(&config)
	if result.Error != nil {
		return nil
	}
	var history []struct {
		ID      string `json:"id"`
		AskedAt string `json:"asked_at"`
	}
	json.Unmarshal([]byte(config.Value), &history)
	sevenDaysAgo := qe.Now.AddDate(0, 0, -7)
	ids := make([]string, 0)
	for _, h := range history {
		t, err := time.Parse(time.RFC3339, h.AskedAt)
		if err == nil && t.After(sevenDaysAgo) {
			ids = append(ids, h.ID)
		}
	}
	return ids
}

func (qe *QuestionEngine) saveQuestionHistory(userID uint, questions []Question) {
	if len(questions) == 0 {
		return
	}
	var config model.UserConfig
	qe.DB.Where("user_id = ? AND key = 'question_history'", userID).First(&config)
	var history []struct {
		ID      string `json:"id"`
		AskedAt string `json:"asked_at"`
	}
	if config.Value != "" {
		json.Unmarshal([]byte(config.Value), &history)
	}
	thirtyDaysAgo := qe.Now.AddDate(0, 0, -30)
	cleaned := make([]struct {
		ID      string `json:"id"`
		AskedAt string `json:"asked_at"`
	}, 0)
	for _, h := range history {
		t, err := time.Parse(time.RFC3339, h.AskedAt)
		if err == nil && t.After(thirtyDaysAgo) {
			cleaned = append(cleaned, h)
		}
	}
	for _, q := range questions {
		cleaned = append(cleaned, struct {
			ID      string `json:"id"`
			AskedAt string `json:"asked_at"`
		}{ID: q.ID, AskedAt: qe.Now.Format(time.RFC3339)})
	}
	data, _ := json.Marshal(cleaned)
	if config.ID == 0 {
		config = model.UserConfig{UserID: userID, Key: "question_history", Value: string(data)}
		qe.DB.Create(&config)
	} else {
		qe.DB.Model(&config).Update("value", string(data))
	}
}

func containsString(slice []string, s string) bool {
	for _, item := range slice {
		if item == s {
			return true
		}
	}
	return false
}
