package handler

import (
	"net/http"
	"strconv"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ReviewHandler struct {
	DB *gorm.DB
}

func NewReviewHandler(db *gorm.DB) *ReviewHandler {
	return &ReviewHandler{DB: db}
}

// TodayReview 今日回顾的三层结构
type TodayReview struct {
	Facts     ReviewFacts    `json:"facts"`
	Patterns  ReviewPatterns `json:"patterns"`
	Questions []Question     `json:"questions"`
}

// ReviewFacts 第一层：事实（今天发生了什么）
type ReviewFacts struct {
	HabitChecked int `json:"habit_checked"`
	HabitTotal   int `json:"habit_total"`

	TaskCompleted int `json:"task_completed"`
	TaskCreated   int `json:"task_created"`

	FocusMinutes int `json:"focus_minutes"`
	FocusCount   int `json:"focus_count"`

	TagDistribution    []TagTime           `json:"tag_distribution"`
	TodayCompletedTasks []CompletedTaskItem `json:"today_completed_tasks"`
}

type TagTime struct {
	TagID   uint   `json:"tag_id"`
	Name    string `json:"name"`
	Icon    string `json:"icon"`
	Minutes int    `json:"minutes"`
}

type CompletedTaskItem struct {
	ID          uint   `json:"id"`
	Title       string `json:"title"`
	ListName    string `json:"list_name"`
	TaskType    string `json:"task_type"`
	OutputLevel string `json:"output_level"`
	CompletedAt string `json:"completed_at"`
	IsMilestone bool   `json:"is_milestone"`
}

type TasksSummary struct {
	CompletedCount int      `json:"completed_count"`
	CreatedCount   int      `json:"created_count"`
	TotalDays      int      `json:"total_days"`
	BestDay        *BestDay `json:"best_day,omitempty"`
}

type BestDay struct {
	Date      string `json:"date"`
	Completed int    `json:"completed"`
}

type TasksDistribution struct {
	ByTaskType map[string]int `json:"by_task_type"`
	ByQuality  map[string]int `json:"by_quality"`
}

type TasksReviewResponse struct {
	Summary        TasksSummary        `json:"summary"`
	CompletedTasks []CompletedTaskItem `json:"completed_tasks"`
	Distribution   TasksDistribution   `json:"distribution"`
}

// ReviewPatterns 第二层：模式（和之前比）
type ReviewPatterns struct {
	HabitDelta int `json:"habit_delta"`
	TaskDelta  int `json:"task_delta"`
	FocusDelta int `json:"focus_delta"`

	HabitWeekDelta int `json:"habit_week_delta"`
	TaskWeekDelta  int `json:"task_week_delta"`
	FocusWeekDelta int `json:"focus_week_delta"`
}

// GetTasksReview 获取指定天数的任务回顾。
// 日历边界始终按用户时区定义，再由数据库驱动转换为绝对时间比较。
func (h *ReviewHandler) GetTasksReview(c *gin.Context) {
	userID := c.GetUint("userID")

	var user model.User
	h.DB.Select("timezone").First(&user, userID)
	loc := model.UserLocation(user.Timezone)

	now := time.Now().In(loc)
	days := 7
	if d := c.Query("days"); d != "" {
		if parsed, err := strconv.Atoi(d); err == nil && parsed > 0 && parsed <= 365 {
			days = parsed
		}
	}

	startOfToday := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	endOfToday := startOfToday.AddDate(0, 0, 1)
	start := endOfToday.AddDate(0, 0, -days)

	var tasks []struct {
		ID          uint
		Title       string
		ListName    string
		TaskType    string
		OutputLevel string
		CompletedAt *time.Time
		IsMilestone bool
	}
	h.DB.Table("tasks").
		Select("tasks.id, tasks.title, lists.name as list_name, tasks.task_type, tasks.output_level, tasks.completed_at, tasks.is_milestone").
		Joins("LEFT JOIN lists ON lists.id = tasks.list_id").
		Where("tasks.user_id = ? AND tasks.is_completed = true AND tasks.completed_at >= ? AND tasks.completed_at < ?", userID, start, endOfToday).
		Order("tasks.completed_at DESC").
		Scan(&tasks)

	var createdCount int64
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND created_at >= ? AND created_at < ?", userID, start, endOfToday).
		Count(&createdCount)

	response := TasksReviewResponse{
		Summary: TasksSummary{
			CompletedCount: len(tasks),
			CreatedCount:   int(createdCount),
			TotalDays:      days,
		},
		CompletedTasks: make([]CompletedTaskItem, 0, len(tasks)),
		Distribution: TasksDistribution{
			ByTaskType: make(map[string]int),
			ByQuality:  make(map[string]int),
		},
	}

	dayCount := make(map[string]int)
	for _, task := range tasks {
		completedAt := ""
		dateKey := ""
		if task.CompletedAt != nil {
			localCompleted := task.CompletedAt.In(loc)
			completedAt = localCompleted.Format("15:04")
			dateKey = localCompleted.Format("2006-01-02")
		}
		response.CompletedTasks = append(response.CompletedTasks, CompletedTaskItem{
			ID:          task.ID,
			Title:       task.Title,
			ListName:    task.ListName,
			TaskType:    task.TaskType,
			OutputLevel: task.OutputLevel,
			CompletedAt: completedAt,
			IsMilestone: task.IsMilestone,
		})

		if task.TaskType != "" {
			response.Distribution.ByTaskType[task.TaskType]++
		}
		if task.OutputLevel != "" {
			response.Distribution.ByQuality[task.OutputLevel]++
		}
		if dateKey != "" {
			dayCount[dateKey]++
		}
	}

	bestDate := ""
	bestCount := 0
	for date, count := range dayCount {
		if count > bestCount {
			bestCount = count
			bestDate = date
		}
	}
	if bestDate != "" {
		response.Summary.BestDay = &BestDay{Date: bestDate, Completed: bestCount}
	}

	c.JSON(http.StatusOK, response)
}

// GetTodayReview 获取今日回顾。
func (h *ReviewHandler) GetTodayReview(c *gin.Context) {
	userID := c.GetUint("userID")

	var user model.User
	h.DB.Select("timezone").First(&user, userID)
	loc := model.UserLocation(user.Timezone)

	now := time.Now().In(loc)
	startOfToday := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	endOfToday := startOfToday.AddDate(0, 0, 1)
	startOfYesterday := startOfToday.AddDate(0, 0, -1)
	endOfYesterday := startOfToday
	startOfWeekAgo := startOfToday.AddDate(0, 0, -7)
	endOfWeekAgo := startOfWeekAgo.AddDate(0, 0, 1)

	facts := h.computeFacts(userID, startOfToday, endOfToday)
	patterns := h.computePatterns(
		userID,
		startOfToday,
		endOfToday,
		startOfYesterday,
		endOfYesterday,
		startOfWeekAgo,
		endOfWeekAgo,
	)

	engine := NewQuestionEngine(h.DB)
	questions := engine.Generate(userID, loc)

	c.JSON(http.StatusOK, TodayReview{
		Facts:     facts,
		Patterns:  patterns,
		Questions: questions,
	})
}

func (h *ReviewHandler) computeFacts(userID uint, start, end time.Time) ReviewFacts {
	facts := ReviewFacts{}

	var totalHabits int64
	h.DB.Model(&model.Habit{}).Where("user_id = ?", userID).Count(&totalHabits)
	facts.HabitTotal = int(totalHabits)

	var checkedToday int64
	h.DB.Model(&model.HabitLog{}).
		Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND date = ?", userID, start.Format("2006-01-02")).
		Count(&checkedToday)
	facts.HabitChecked = int(checkedToday)

	var completedToday int64
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND is_completed = true AND completed_at >= ? AND completed_at < ?", userID, start, end).
		Count(&completedToday)
	facts.TaskCompleted = int(completedToday)

	var createdToday int64
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND created_at >= ? AND created_at < ?", userID, start, end).
		Count(&createdToday)
	facts.TaskCreated = int(createdToday)

	var sessions []struct {
		DurationMin int
	}
	h.DB.Model(&model.BehaviorEvent{}).
		Select("duration_min").
		Where("user_id = ? AND event_type = 'session_ended' AND occurred_at >= ? AND occurred_at < ?", userID, start, end).
		Scan(&sessions)
	for _, session := range sessions {
		facts.FocusMinutes += session.DurationMin
		facts.FocusCount++
	}

	var tagDists []struct {
		TagID   *uint
		Name    string
		Icon    string
		Minutes int
	}
	h.DB.Model(&model.BehaviorEvent{}).
		Select("system_tag_id as tag_id, COALESCE((SELECT name FROM system_tags WHERE id = behavior_events.system_tag_id), '') as name, COALESCE((SELECT icon FROM system_tags WHERE id = behavior_events.system_tag_id), '') as icon, SUM(duration_min) as minutes").
		Where("user_id = ? AND event_type = 'session_ended' AND system_tag_id IS NOT NULL AND occurred_at >= ? AND occurred_at < ?", userID, start, end).
		Group("system_tag_id").
		Scan(&tagDists)

	for _, distribution := range tagDists {
		tagID := uint(0)
		if distribution.TagID != nil {
			tagID = *distribution.TagID
		}
		facts.TagDistribution = append(facts.TagDistribution, TagTime{
			TagID:   tagID,
			Name:    distribution.Name,
			Icon:    distribution.Icon,
			Minutes: distribution.Minutes,
		})
	}

	var completedTasks []struct {
		ID          uint
		Title       string
		ListName    string
		TaskType    string
		OutputLevel string
		CompletedAt *time.Time
		IsMilestone bool
	}
	h.DB.Table("tasks").
		Select("tasks.id, tasks.title, lists.name as list_name, tasks.task_type, tasks.output_level, tasks.completed_at, tasks.is_milestone").
		Joins("LEFT JOIN lists ON lists.id = tasks.list_id").
		Where("tasks.user_id = ? AND tasks.is_completed = true AND tasks.completed_at >= ? AND tasks.completed_at < ?", userID, start, end).
		Order("tasks.completed_at DESC").
		Scan(&completedTasks)

	for _, task := range completedTasks {
		completedAt := ""
		if task.CompletedAt != nil {
			completedAt = task.CompletedAt.In(start.Location()).Format("15:04")
		}
		facts.TodayCompletedTasks = append(facts.TodayCompletedTasks, CompletedTaskItem{
			ID:          task.ID,
			Title:       task.Title,
			ListName:    task.ListName,
			TaskType:    task.TaskType,
			OutputLevel: task.OutputLevel,
			CompletedAt: completedAt,
			IsMilestone: task.IsMilestone,
		})
	}

	return facts
}

func (h *ReviewHandler) computePatterns(
	userID uint,
	startToday, endToday time.Time,
	startYesterday, endYesterday time.Time,
	startWeekAgo, endWeekAgo time.Time,
) ReviewPatterns {
	patterns := ReviewPatterns{}

	yesterdayHabits := h.countHabits(userID, startYesterday.Format("2006-01-02"))
	yesterdayTasks := h.countCompletedTasks(userID, startYesterday, endYesterday)
	yesterdayFocus := h.countFocusMinutes(userID, startYesterday, endYesterday)

	todayHabits := h.countHabits(userID, startToday.Format("2006-01-02"))
	todayTasks := h.countCompletedTasks(userID, startToday, endToday)
	todayFocus := h.countFocusMinutes(userID, startToday, endToday)

	weekAgoHabits := h.countHabits(userID, startWeekAgo.Format("2006-01-02"))
	weekAgoTasks := h.countCompletedTasks(userID, startWeekAgo, endWeekAgo)
	weekAgoFocus := h.countFocusMinutes(userID, startWeekAgo, endWeekAgo)

	patterns.HabitDelta = todayHabits - yesterdayHabits
	patterns.TaskDelta = todayTasks - yesterdayTasks
	patterns.FocusDelta = todayFocus - yesterdayFocus
	patterns.HabitWeekDelta = todayHabits - weekAgoHabits
	patterns.TaskWeekDelta = todayTasks - weekAgoTasks
	patterns.FocusWeekDelta = todayFocus - weekAgoFocus

	return patterns
}

func (h *ReviewHandler) countHabits(userID uint, date string) int {
	var count int64
	h.DB.Model(&model.HabitLog{}).
		Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND date = ?", userID, date).
		Count(&count)
	return int(count)
}

func (h *ReviewHandler) countCompletedTasks(userID uint, start, end time.Time) int {
	var count int64
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND is_completed = true AND completed_at >= ? AND completed_at < ?", userID, start, end).
		Count(&count)
	return int(count)
}

func (h *ReviewHandler) countFocusMinutes(userID uint, start, end time.Time) int {
	var total int
	h.DB.Model(&model.BehaviorEvent{}).
		Select("COALESCE(SUM(duration_min), 0)").
		Where("user_id = ? AND event_type = 'session_ended' AND occurred_at >= ? AND occurred_at < ?", userID, start, end).
		Scan(&total)
	return total
}
