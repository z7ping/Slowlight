package handler

import (
	"database/sql"
	"net/http"
	"strconv"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type AnalyticsHandler struct {
	DB *gorm.DB
}

func NewAnalyticsHandler(db *gorm.DB) *AnalyticsHandler {
	return &AnalyticsHandler{DB: db}
}

// ========== 2.3 输出追踪 ==========

// OutputStats 输出统计
type OutputStats struct {
	TotalCount   int            `json:"total_count"`
	ByLevel      map[string]int `json:"by_level"`      // S/A/B/C 各多少
	ByTaskType   map[string]int `json:"by_task_type"`  // main/branch/daily/explore
	Milestones   int            `json:"milestones"`    // 里程碑数量
	ThisWeek     int            `json:"this_week"`     // 本周输出
	ThisMonth    int            `json:"this_month"`    // 本月输出
}

// GetOutputStats 获取输出统计
func (h *AnalyticsHandler) GetOutputStats(c *gin.Context) {
	userID := c.GetUint("userID")
	period := c.DefaultQuery("period", "all") // week, month, all

	var since time.Time
	now := time.Now()
	loc := h.getUserLocation(userID)

	switch period {
	case "week":
		weekday := int(now.In(loc).Weekday())
		if weekday == 0 {
			weekday = 7
		}
		since = time.Date(now.Year(), now.Month(), now.Day()-weekday+1, 0, 0, 0, 0, loc)
	case "month":
		since = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)
	default:
		since = time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	}

	// 有输出等级的任务
	var tasks []model.Task
	query := h.DB.Where("user_id = ? AND output_level != '' AND is_completed = true", userID)
	if !since.IsZero() {
		query = query.Where("completed_at >= ?", since)
	}
	query.Find(&tasks)

	stats := OutputStats{
		ByLevel:    make(map[string]int),
		ByTaskType: make(map[string]int),
	}

	// 本周/本月统计（独立查询）
	var weekCount int64
	weekStart := h.getWeekStart(now, loc)
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND output_level != '' AND is_completed = true AND completed_at >= ?",
			userID, weekStart).
		Count(&weekCount)
	stats.ThisWeek = int(weekCount)

	var monthStart time.Time
	monthStart = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)
	var monthCount int64
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND output_level != '' AND is_completed = true AND completed_at >= ?",
			userID, monthStart).
		Count(&monthCount)
	stats.ThisMonth = int(monthCount)

	for _, t := range tasks {
		stats.TotalCount++
		if t.OutputLevel != "" {
			stats.ByLevel[t.OutputLevel]++
		}
		if t.TaskType != "" {
			stats.ByTaskType[t.TaskType]++
		}
		if t.IsMilestone {
			stats.Milestones++
		}
	}

	c.JSON(http.StatusOK, stats)
}

// ========== 2.4 时间分配可视化 ==========

// TagTimeDistribution 时间按系统标签分布
type TagTimeDistribution struct {
	TagID      uint   `json:"tag_id"`
	Name       string `json:"name"`
	Icon       string `json:"icon"`
	TotalMin   int    `json:"total_min"`
	SessionCnt int    `json:"session_count"`
	Percent    float64 `json:"percent"`
}

// TimeDistribution 时间分配统计
type TimeDistribution struct {
	TotalMin    int                   `json:"total_min"`
	Tags        []TagTimeDistribution `json:"tags"`
	ByDay       []DailyTime           `json:"by_day"` // 最近 7 天每天
}

// DailyTime 每日时间
type DailyTime struct {
	Date      string `json:"date"`
	TotalMin  int    `json:"total_min"`
	WorkCount int    `json:"work_count"`
}

// GetTimeDistribution 获取时间分配（按系统标签聚合）
func (h *AnalyticsHandler) GetTimeDistribution(c *gin.Context) {
	userID := c.GetUint("userID")
	days := 7 // 默认最近 7 天

	now := time.Now()
	loc := h.getUserLocation(userID)
	since := now.AddDate(0, 0, -days)

	// 获取所有系统标签
	var allTags []model.SystemTag
	h.DB.Where("user_id = ?", userID).Find(&allTags)
	tagMap := make(map[uint]model.SystemTag)
	for _, t := range allTags {
		tagMap[t.ID] = t
	}

	// 查询 behavior_events
	var events []model.BehaviorEvent
	h.DB.Where("user_id = ? AND event_type = 'session_ended' AND occurred_at >= ?",
		userID, since).Find(&events)

	// 按标签聚合
	tagMinutes := make(map[uint]int)
	tagCounts := make(map[uint]int)
	totalMin := 0

	// 按天聚合
	dailyMap := make(map[string]*DailyTime)

	for _, e := range events {
		totalMin += e.DurationMin

		// 按天
		dateKey := e.OccurredAt.In(loc).Format("2006-01-02")
		if _, ok := dailyMap[dateKey]; !ok {
			dailyMap[dateKey] = &DailyTime{Date: dateKey}
		}
		dailyMap[dateKey].TotalMin += e.DurationMin
		dailyMap[dateKey].WorkCount++

		// 按标签
		if e.SystemTagID != nil {
			tagMinutes[*e.SystemTagID] += e.DurationMin
			tagCounts[*e.SystemTagID]++
		}
	}

	// 组装结果
	dist := TimeDistribution{
		TotalMin: totalMin,
		Tags:     make([]TagTimeDistribution, 0),
		ByDay:    make([]DailyTime, 0),
	}

	for tagID, mins := range tagMinutes {
		tag := tagMap[tagID]
		pct := float64(0)
		if totalMin > 0 {
			pct = float64(mins) / float64(totalMin) * 100
		}
		dist.Tags = append(dist.Tags, TagTimeDistribution{
			TagID:      tagID,
			Name:       tag.Name,
			Icon:       tag.Icon,
			TotalMin:   mins,
			SessionCnt: tagCounts[tagID],
			Percent:    pct,
		})
	}

	// 填充 7 天的数据
	for i := days - 1; i >= 0; i-- {
		date := now.AddDate(0, 0, -i).In(loc).Format("2006-01-02")
		if dt, ok := dailyMap[date]; ok {
			dist.ByDay = append(dist.ByDay, *dt)
		} else {
			dist.ByDay = append(dist.ByDay, DailyTime{Date: date})
		}
	}

	c.JSON(http.StatusOK, dist)
}

// ========== 2.5 每周回顾 ==========

// WeeklyReview 每周回顾
type WeeklyReview struct {
	WeekStart string `json:"week_start"`
	WeekEnd   string `json:"week_end"`
	// 趋势
	HabitChecked  int `json:"habit_checked"`
	HabitLastWeek int `json:"habit_last_week"`
	TaskCompleted int `json:"task_completed"`
	TaskLastWeek  int `json:"task_last_week"`
	FocusMinutes  int `json:"focus_minutes"`
	FocusLastWeek int `json:"focus_last_week"`
	// 输出
	OutputCount int            `json:"output_count"`
	OutputByLvl map[string]int `json:"output_by_level"`
	Milestones  int            `json:"milestones"`
	// 时间分配
	TimeDistribution []TagTimeDistribution `json:"time_distribution"`
}

// GetWeeklyReview 获取本周回顾
func (h *AnalyticsHandler) GetWeeklyReview(c *gin.Context) {
	userID := c.GetUint("userID")
	now := time.Now()
	loc := h.getUserLocation(userID)

	// 本周范围
	weekday := int(now.In(loc).Weekday())
	if weekday == 0 {
		weekday = 7
	}
	thisWeekStart := time.Date(now.Year(), now.Month(), now.Day()-weekday+1, 0, 0, 0, 0, loc)
	thisWeekEnd := thisWeekStart.AddDate(0, 0, 7)

	// 上周范围
	lastWeekStart := thisWeekStart.AddDate(0, 0, -7)
	lastWeekEnd := thisWeekStart

	review := WeeklyReview{
		WeekStart:  thisWeekStart.Format("2006-01-02"),
		WeekEnd:    thisWeekEnd.AddDate(0, 0, -1).Format("2006-01-02"),
		OutputByLvl: make(map[string]int),
	}

	// 本周习惯打卡
	review.HabitChecked = h.countHabitLogs(userID, thisWeekStart, thisWeekEnd)
	review.HabitLastWeek = h.countHabitLogs(userID, lastWeekStart, lastWeekEnd)

	// 本周完成任务
	review.TaskCompleted = h.countCompletedTasks(userID, thisWeekStart, thisWeekEnd)
	review.TaskLastWeek = h.countCompletedTasks(userID, lastWeekStart, lastWeekEnd)

	// 本周专注
	review.FocusMinutes = h.countFocusMinutes(userID, thisWeekStart, thisWeekEnd)
	review.FocusLastWeek = h.countFocusMinutes(userID, lastWeekStart, lastWeekEnd)

	// 本周输出
	var outputTasks []model.Task
	h.DB.Where("user_id = ? AND output_level != '' AND is_completed = true AND completed_at >= ? AND completed_at < ?",
		userID, thisWeekStart, thisWeekEnd).Find(&outputTasks)

	for _, t := range outputTasks {
		review.OutputCount++
		review.OutputByLvl[t.OutputLevel]++
		if t.IsMilestone {
			review.Milestones++
		}
	}

	// 时间分配
	var events []model.BehaviorEvent
	h.DB.Where("user_id = ? AND event_type = 'session_ended' AND occurred_at >= ? AND occurred_at < ?",
		userID, thisWeekStart, thisWeekEnd).Find(&events)

	tagMinutes := make(map[uint]int)
	tagCounts := make(map[uint]int)
	totalMin := 0

	var allTags []model.SystemTag
	h.DB.Where("user_id = ?", userID).Find(&allTags)
	tagMap := make(map[uint]model.SystemTag)
	for _, t := range allTags {
		tagMap[t.ID] = t
	}

	for _, e := range events {
		totalMin += e.DurationMin
		if e.SystemTagID != nil {
			tagMinutes[*e.SystemTagID] += e.DurationMin
			tagCounts[*e.SystemTagID]++
		}
	}

	for tagID, mins := range tagMinutes {
		tag := tagMap[tagID]
		pct := float64(0)
		if totalMin > 0 {
			pct = float64(mins) / float64(totalMin) * 100
		}
		review.TimeDistribution = append(review.TimeDistribution, TagTimeDistribution{
			TagID:      tagID,
			Name:       tag.Name,
			Icon:       tag.Icon,
			TotalMin:   mins,
			SessionCnt: tagCounts[tagID],
			Percent:    pct,
		})
	}

	c.JSON(http.StatusOK, review)
}

// ========== 每日趋势（折线图数据）==========

// DailyTrendPoint 每日趋势数据点
type DailyTrendPoint struct {
	Date            string `json:"date"`             // YYYY-MM-DD
	TaskCompleted   int    `json:"task_completed"`   // 当日完成任务数
	TaskTotal       int    `json:"task_total"`       // 当日总任务数
	FocusMinutes    int    `json:"focus_minutes"`    // 专注分钟数
	HabitChecked    int    `json:"habit_checked"`    // 打卡数
	HabitTotal      int    `json:"habit_total"`      // 总习惯数
	CompletionRate  int    `json:"completion_rate"`  // 完成率 0-100
}

// GetDailyTrend 获取最近 N 天的每日趋势
func (h *AnalyticsHandler) GetDailyTrend(c *gin.Context) {
	userID := c.GetUint("userID")
	loc := h.getUserLocation(userID)
	now := time.Now().In(loc)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)

	days := 7
	if d := c.Query("days"); d != "" {
		if parsed, err := strconv.Atoi(d); err == nil && parsed > 0 && parsed <= 365 {
			days = parsed
		}
	}

	// 获取总习惯数（当前）
	var habitTotal int64
	h.DB.Model(&model.Habit{}).Where("user_id = ?", userID).Count(&habitTotal)

	points := make([]DailyTrendPoint, 0, days)
	for i := days - 1; i >= 0; i-- {
		dayStart := today.AddDate(0, 0, -i)
		dayEnd := dayStart.Add(24 * time.Hour)
		dateStr := dayStart.Format("2006-01-02")

		completed := h.countCompletedTasks(userID, dayStart, dayEnd)

		// 当日创建的任务数（作为总任务数的近似）
		var taskTotal int64
		h.DB.Model(&model.Task{}).
			Where("user_id = ? AND created_at >= ? AND created_at < ?", userID, dayStart, dayEnd).
			Count(&taskTotal)
		total := int(taskTotal)

		focusMin := h.countFocusMinutes(userID, dayStart, dayEnd)

		var checked int64
		h.DB.Model(&model.HabitLog{}).
			Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND date = ?",
				userID, dateStr).
			Count(&checked)

		rate := 0
		if total > 0 {
			rate = completed * 100 / total
		}

		points = append(points, DailyTrendPoint{
			Date:           dateStr,
			TaskCompleted:  completed,
			TaskTotal:      total,
			FocusMinutes:   focusMin,
			HabitChecked:   int(checked),
			HabitTotal:     int(habitTotal),
			CompletionRate: rate,
		})
	}

	c.JSON(http.StatusOK, gin.H{"days": points})
}

// ========== 四维度状态摘要 ==========

// DimensionItem 单个维度数据
type DimensionItem struct {
	ID         uint   `json:"id"`          // 系统标签 ID
	Name       string `json:"name"`
	Icon       string `json:"icon"`
	Color      string `json:"color"`
	Value      int    `json:"value"`     // 本周活动总数（已完成任务+习惯打卡）
	Total      int    `json:"total"`     // 本周目标（暂为0，不做进度条）
	Unit       string `json:"unit"`
	Trend      string `json:"trend"`     // up/down/warning/flat
	TrendDesc  string `json:"trend_desc"`
	LastRecord string `json:"last_record"` // 最后记录时间
}

// GetDimensionSummary 四维度状态摘要
func (h *AnalyticsHandler) GetDimensionSummary(c *gin.Context) {
	userID := c.GetUint("userID")
	now := time.Now()
	loc := h.getUserLocation(userID)

	// 本周范围（周一到周日）
	weekday := int(now.In(loc).Weekday())
	if weekday == 0 {
		weekday = 7
	}
	thisWeekStart := time.Date(now.Year(), now.Month(), now.Day()-weekday+1, 0, 0, 0, 0, loc)
	thisWeekEnd := thisWeekStart.AddDate(0, 0, 7)
	lastWeekStart := thisWeekStart.AddDate(0, 0, -7)

	// 获取所有系统标签
	var tags []model.SystemTag
	h.DB.Where("user_id = ?", userID).Order("id ASC").Find(&tags)

	if len(tags) == 0 {
		c.JSON(http.StatusOK, gin.H{"dimensions": []DimensionItem{}})
		return
	}

	dimensions := make([]DimensionItem, 0, len(tags))

	for _, tag := range tags {
		tagID := tag.ID

		// 本周完成任务数
		var thisWeekTaskCount int64
		h.DB.Model(&model.Task{}).
			Where("user_id = ? AND system_tag_id = ? AND is_completed = true AND completed_at >= ? AND completed_at < ?",
				userID, tagID, thisWeekStart, thisWeekEnd).
			Count(&thisWeekTaskCount)

		// 上周完成任务数
		var lastWeekTaskCount int64
		h.DB.Model(&model.Task{}).
			Where("user_id = ? AND system_tag_id = ? AND is_completed = true AND completed_at >= ? AND completed_at < ?",
				userID, tagID, lastWeekStart, thisWeekStart).
			Count(&lastWeekTaskCount)

		// 本周习惯打卡数
		var thisWeekHabitCount int64
		h.DB.Model(&model.HabitLog{}).
			Where("habit_id IN (SELECT id FROM habits WHERE user_id = ? AND system_tag_id = ?) AND created_at >= ? AND created_at < ?",
				userID, tagID, thisWeekStart, thisWeekEnd).
			Count(&thisWeekHabitCount)

		// 上周习惯打卡数
		var lastWeekHabitCount int64
		h.DB.Model(&model.HabitLog{}).
			Where("habit_id IN (SELECT id FROM habits WHERE user_id = ? AND system_tag_id = ?) AND created_at >= ? AND created_at < ?",
				userID, tagID, lastWeekStart, thisWeekStart).
			Count(&lastWeekHabitCount)

		// 最后完成时间（任务）
		var lastTaskTime sql.NullTime
		h.DB.Model(&model.Task{}).
			Select("MAX(completed_at)").
			Where("user_id = ? AND system_tag_id = ? AND is_completed = true", userID, tagID).
			Scan(&lastTaskTime)

		// 最后打卡时间（习惯）
		var lastHabitTime sql.NullTime
		h.DB.Model(&model.HabitLog{}).
			Select("MAX(created_at)").
			Where("habit_id IN (SELECT id FROM habits WHERE user_id = ? AND system_tag_id = ?)", userID, tagID).
			Scan(&lastHabitTime)

		// 取较晚的时间作为 lastRecord
		lastRecord := ""
		if lastTaskTime.Valid && lastHabitTime.Valid {
			if lastTaskTime.Time.After(lastHabitTime.Time) {
				lastRecord = lastTaskTime.Time.In(loc).Format("2006-01-02 15:04:05")
			} else {
				lastRecord = lastHabitTime.Time.In(loc).Format("2006-01-02 15:04:05")
			}
		} else if lastTaskTime.Valid {
			lastRecord = lastTaskTime.Time.In(loc).Format("2006-01-02 15:04:05")
		} else if lastHabitTime.Valid {
			lastRecord = lastHabitTime.Time.In(loc).Format("2006-01-02 15:04:05")
		}

		thisWeek := int(thisWeekTaskCount) + int(thisWeekHabitCount)
		lastWeek := int(lastWeekTaskCount) + int(lastWeekHabitCount)

		// 计算趋势
		trend := "flat"
		trendDesc := "持平"

		if lastRecord == "" {
			trend = "warning"
			trendDesc = "暂无记录"
		} else {
			lastTime, err := time.ParseInLocation("2006-01-02 15:04:05", lastRecord, loc)
			if err == nil {
				days := int(now.In(loc).Sub(lastTime).Hours() / 24)
				if days >= 3 {
					trend = "warning"
					trendDesc = strconv.Itoa(days) + "天未记录"
				} else if lastWeek == 0 {
					if thisWeek > 0 {
						trend = "up"
						trendDesc = "本周+" + strconv.Itoa(thisWeek)
					} else {
						trendDesc = "本周" + strconv.Itoa(thisWeek) + "次"
					}
				} else {
					diff := thisWeek - lastWeek
					ratio := float64(diff) / float64(lastWeek) * 100
					if ratio > 20 {
						trend = "up"
						trendDesc = "+" + strconv.Itoa(diff) + " 次"
					} else if ratio < -20 {
						trend = "down"
						trendDesc = strconv.Itoa(diff) + " 次"
					} else {
						trendDesc = "持平"
					}
				}
			}
		}

		dimensions = append(dimensions, DimensionItem{
			ID:         tag.ID,
			Name:       tag.Name,
			Icon:       tag.Icon,
			Color:      tag.Color,
			Value:      thisWeek,
			Total:      0,
			Unit:       "次活动",
			Trend:      trend,
			TrendDesc:  trendDesc,
			LastRecord: lastRecord,
		})
	}

	c.JSON(http.StatusOK, gin.H{"dimensions": dimensions})
}

// ========== 辅助方法 ==========

func (h *AnalyticsHandler) getUserLocation(userID uint) *time.Location {
	var user model.User
	h.DB.Select("timezone").First(&user, userID)
	return model.UserLocation(user.Timezone)
}

func (h *AnalyticsHandler) getWeekStart(now time.Time, loc *time.Location) time.Time {
	weekday := int(now.In(loc).Weekday())
	if weekday == 0 {
		weekday = 7
	}
	return time.Date(now.Year(), now.Month(), now.Day()-weekday+1, 0, 0, 0, 0, loc)
}

func (h *AnalyticsHandler) countHabitLogs(userID uint, start, end time.Time) int {
	var count int64
	h.DB.Model(&model.HabitLog{}).
		Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND created_at >= ? AND created_at < ?",
			userID, start, end).
		Count(&count)
	return int(count)
}

func (h *AnalyticsHandler) countCompletedTasks(userID uint, start, end time.Time) int {
	var count int64
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND is_completed = true AND completed_at >= ? AND completed_at < ?",
			userID, start, end).
		Count(&count)
	return int(count)
}

func (h *AnalyticsHandler) countFocusMinutes(userID uint, start, end time.Time) int {
	var total int
	h.DB.Model(&model.BehaviorEvent{}).
		Select("COALESCE(SUM(duration_min), 0)").
		Where("user_id = ? AND event_type = 'session_ended' AND occurred_at >= ? AND occurred_at < ?",
			userID, start, end).
		Scan(&total)
	return total
}
