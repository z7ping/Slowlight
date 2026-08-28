package handler

import (
	"database/sql"
	"net/http"
	"strconv"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
)

// GetDailyTrendConsistent 使用一致 cohort 计算每日完成率。
func (h *AnalyticsHandler) GetDailyTrendConsistent(c *gin.Context) {
	userID := c.GetUint("userID")
	loc := h.getUserLocation(userID)
	now := time.Now().In(loc)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)

	days := 7
	if raw := c.Query("days"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 && parsed <= 365 {
			days = parsed
		}
	}

	var habitTotal int64
	h.DB.Model(&model.Habit{}).Where("user_id = ?", userID).Count(&habitTotal)

	points := make([]DailyTrendPoint, 0, days)
	for i := days - 1; i >= 0; i-- {
		start := today.AddDate(0, 0, -i)
		end := start.AddDate(0, 0, 1)
		date := start.Format("2006-01-02")
		actualCompleted := h.countCompletedTasks(userID, start, end)

		var created int64
		h.DB.Model(&model.Task{}).
			Where("user_id = ? AND created_at >= ? AND created_at < ?", userID, start, end).
			Count(&created)

		var cohortCompleted int64
		h.DB.Model(&model.Task{}).
			Where("user_id = ? AND created_at >= ? AND created_at < ? AND is_completed = true", userID, start, end).
			Count(&cohortCompleted)

		var checked int64
		h.DB.Model(&model.HabitLog{}).
			Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND date = ?", userID, date).
			Count(&checked)

		rate := 0
		if created > 0 {
			rate = int(cohortCompleted * 100 / created)
		}

		points = append(points, DailyTrendPoint{
			Date:           date,
			TaskCompleted:  actualCompleted,
			TaskTotal:      int(created),
			FocusMinutes:   h.countFocusMinutes(userID, start, end),
			HabitChecked:   int(checked),
			HabitTotal:     int(habitTotal),
			CompletionRate: rate,
		})
	}
	c.JSON(http.StatusOK, gin.H{"days": points})
}

type canonicalDimensionItem struct {
	Key        model.DimensionKey `json:"key"`
	Name       string             `json:"name"`
	Icon       string             `json:"icon"`
	Color      string             `json:"color"`
	Value      int                `json:"value"`
	Total      int                `json:"total"`
	Unit       string             `json:"unit"`
	Trend      string             `json:"trend"`
	TrendDesc  string             `json:"trend_desc"`
	LastRecord string             `json:"last_record"`
	ActiveDays []string           `json:"active_days"`
}

// GetDimensionSummaryConsistent 四维度按稳定 DimensionKey 计算。
//
// SystemTag 是用户分类标签；多个标签可以归属同一个 Dimension。任意自定义标签
// 不会再自动变成第五/第六个“人生维度”。
func (h *AnalyticsHandler) GetDimensionSummaryConsistent(c *gin.Context) {
	userID := c.GetUint("userID")
	loc := h.getUserLocation(userID)
	now := time.Now().In(loc)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	weekStart := h.getWeekStart(now, loc)
	weekEnd := weekStart.AddDate(0, 0, 7)
	lastWeekStart := weekStart.AddDate(0, 0, -7)

	result := make([]canonicalDimensionItem, 0, len(model.Dimensions))
	for _, dimension := range model.Dimensions {
		thisWeek := h.countDimensionActivitiesByKey(userID, dimension.Key, weekStart, weekEnd)
		lastWeek := h.countDimensionActivitiesByKey(userID, dimension.Key, lastWeekStart, weekStart)
		lastAt := h.lastDimensionActivityByKey(userID, dimension.Key)
		trend, trendDesc := dimensionTrend(now, thisWeek, lastWeek, lastAt)

		lastRecord := ""
		if lastAt.Valid {
			lastRecord = lastAt.Time.In(loc).Format("2006-01-02 15:04:05")
		}
		result = append(result, canonicalDimensionItem{
			Key:        dimension.Key,
			Name:       dimension.Name,
			Icon:       dimension.Icon,
			Color:      dimension.Color,
			Value:      thisWeek,
			Total:      0,
			Unit:       "次活动",
			Trend:      trend,
			TrendDesc:  trendDesc,
			LastRecord: lastRecord,
			ActiveDays: h.dimensionActiveDays(userID, dimension.Key, today),
		})
	}
	c.JSON(http.StatusOK, gin.H{"dimensions": result})
}

func (h *AnalyticsHandler) countDimensionActivitiesByKey(
	userID uint,
	key model.DimensionKey,
	start time.Time,
	end time.Time,
) int {
	var count int64
	h.DB.Table("behavior_events AS be").
		Joins("JOIN system_tags AS st ON st.id = be.system_tag_id").
		Where(
			"be.user_id = ? AND st.user_id = ? AND st.deleted_at IS NULL AND st.dimension_key = ? AND be.is_deleted = false AND be.event_type IN ? AND be.occurred_at >= ? AND be.occurred_at < ?",
			userID,
			userID,
			key,
			[]string{"task_completed", "habit_checked", "session_ended"},
			start,
			end,
		).
		Count(&count)
	return int(count)
}

func (h *AnalyticsHandler) dimensionActiveDays(
	userID uint,
	key model.DimensionKey,
	today time.Time,
) []string {
	result := make([]string, 0, 7)
	for offset := 6; offset >= 0; offset-- {
		start := today.AddDate(0, 0, -offset)
		end := start.AddDate(0, 0, 1)
		if h.countDimensionActivitiesByKey(userID, key, start, end) > 0 {
			result = append(result, start.Format("2006-01-02"))
		}
	}
	return result
}

func (h *AnalyticsHandler) lastDimensionActivityByKey(
	userID uint,
	key model.DimensionKey,
) sql.NullTime {
	var last sql.NullTime
	h.DB.Table("behavior_events AS be").
		Select("MAX(be.occurred_at)").
		Joins("JOIN system_tags AS st ON st.id = be.system_tag_id").
		Where(
			"be.user_id = ? AND st.user_id = ? AND st.deleted_at IS NULL AND st.dimension_key = ? AND be.is_deleted = false AND be.event_type IN ?",
			userID,
			userID,
			key,
			[]string{"task_completed", "habit_checked", "session_ended"},
		).
		Scan(&last)
	return last
}

func dimensionTrend(
	now time.Time,
	current int,
	previous int,
	last sql.NullTime,
) (string, string) {
	if !last.Valid {
		return "quiet", "暂无记录"
	}
	if days := int(now.Sub(last.Time).Hours() / 24); days >= 3 {
		return "quiet", strconv.Itoa(days) + "天未记录"
	}
	if previous == 0 {
		if current > 0 {
			return "up", "本周+" + strconv.Itoa(current)
		}
		return "flat", "本周0次"
	}

	diff := current - previous
	ratio := float64(diff) / float64(previous) * 100
	if ratio > 20 {
		return "up", "+" + strconv.Itoa(diff) + " 次"
	}
	if ratio < -20 {
		return "down", strconv.Itoa(diff) + " 次"
	}
	return "flat", "持平"
}
