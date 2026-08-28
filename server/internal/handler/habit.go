package handler

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type HabitHandler struct {
	DB *gorm.DB
}

func NewHabitHandler(db *gorm.DB) *HabitHandler {
	return &HabitHandler{DB: db}
}

// GetHabits 获取当前用户的习惯列表
func (h *HabitHandler) GetHabits(c *gin.Context) {
	userID := c.GetUint("userID")

	var tzUser model.User
	h.DB.Select("timezone").First(&tzUser, userID)
	loc := model.UserLocation(tzUser.Timezone)
	now := time.Now().In(loc)
	today := now.Format("2006-01-02")

	weekday := now.Weekday()
	if weekday == time.Sunday {
		weekday = 7
	}
	weekStart := now.AddDate(0, 0, -int(weekday-time.Monday))
	weekStartStr := weekStart.Format("2006-01-02")

	var habits []model.Habit
	h.DB.Where("user_id = ?", userID).Order("created_at DESC").Find(&habits)

	var weekLogs []model.HabitLog
	h.DB.Where("date >= ? AND date <= ?", weekStartStr, today).Find(&weekLogs)

	type logGroup struct {
		days []string
	}
	logMap := make(map[uint]*logGroup)
	for _, log := range weekLogs {
		if _, ok := logMap[log.HabitID]; !ok {
			logMap[log.HabitID] = &logGroup{}
		}
		logMap[log.HabitID].days = append(logMap[log.HabitID].days, log.Date)
	}

	for i := range habits {
		if g, ok := logMap[habits[i].ID]; ok {
			habits[i].CheckedDays = g.days
			for _, d := range g.days {
				if d == today {
					habits[i].CheckedToday = true
					break
				}
			}
		}
	}

	c.JSON(http.StatusOK, habits)
}

// CreateHabit 创建习惯。客户端 reminder_at 是 JSON 对象，而数据库字段保存 JSON 字符串，
// 因此不能直接把请求绑定到 model.Habit。
func (h *HabitHandler) CreateHabit(c *gin.Context) {
	userID := c.GetUint("userID")
	var payload map[string]interface{}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	name := strings.TrimSpace(habitString(payload, "name", ""))
	if name == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "习惯名称不能为空"})
		return
	}

	systemTagID, _ := habitUintPtr(payload, "system_tag_id")
	if systemTagID != nil && !h.ownsSystemTag(userID, *systemTagID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "观察标签不存在"})
		return
	}

	habit := model.Habit{
		UserID:            userID,
		Name:              name,
		Icon:              habitString(payload, "icon", "✅"),
		Color:             habitString(payload, "color", "#52c41a"),
		Frequency:         habitString(payload, "frequency", "daily"),
		TargetDays:        habitInt(payload, "target_days", 0),
		PreferredPeriod:   habitString(payload, "preferred_period", ""),
		SystemTagID:       systemTagID,
		GenerateTask:      habitBool(payload, "generate_task", false),
		DurationMin:       habitInt(payload, "duration_min", 0),
		SpecificTime:      habitString(payload, "specific_time", ""),
		ShowCheckinDialog: habitBool(payload, "show_checkin_dialog", false),
		ReminderAt:        habitJSON(payload["reminder_at"], "{}"),
	}
	if err := h.DB.Create(&habit).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, habit)
}

// UpdateHabit 更新习惯。使用 map 更新以保留 false/0，并允许 system_tag_id=null。
func (h *HabitHandler) UpdateHabit(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var habit model.Habit
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "习惯不存在"})
		return
	}

	var payload map[string]interface{}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updates := map[string]interface{}{}
	for _, key := range []string{"name", "icon", "color", "frequency", "preferred_period", "specific_time"} {
		if value, ok := payload[key]; ok {
			text, ok := value.(string)
			if !ok {
				c.JSON(http.StatusBadRequest, gin.H{"error": key + " 格式错误"})
				return
			}
			if key == "name" && strings.TrimSpace(text) == "" {
				c.JSON(http.StatusBadRequest, gin.H{"error": "习惯名称不能为空"})
				return
			}
			updates[key] = text
		}
	}
	for _, key := range []string{"target_days", "duration_min"} {
		if value, ok := payload[key]; ok {
			number, ok := habitNumber(value)
			if !ok {
				c.JSON(http.StatusBadRequest, gin.H{"error": key + " 格式错误"})
				return
			}
			updates[key] = number
		}
	}
	for _, key := range []string{"generate_task", "show_checkin_dialog"} {
		if value, ok := payload[key]; ok {
			flag, ok := value.(bool)
			if !ok {
				c.JSON(http.StatusBadRequest, gin.H{"error": key + " 格式错误"})
				return
			}
			updates[key] = flag
		}
	}
	if _, ok := payload["system_tag_id"]; ok {
		tagID, valid := habitUintPtr(payload, "system_tag_id")
		if !valid {
			c.JSON(http.StatusBadRequest, gin.H{"error": "system_tag_id 格式错误"})
			return
		}
		if tagID != nil && !h.ownsSystemTag(userID, *tagID) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "观察标签不存在"})
			return
		}
		updates["system_tag_id"] = tagID
	}
	if value, ok := payload["reminder_at"]; ok {
		updates["reminder_at"] = habitJSON(value, "{}")
	}

	if len(updates) > 0 {
		if err := h.DB.Model(&habit).Updates(updates).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "更新习惯失败"})
			return
		}
	}
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "读取更新结果失败"})
		return
	}
	c.JSON(http.StatusOK, habit)
}

// DeleteHabit 删除习惯
func (h *HabitHandler) DeleteHabit(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	result := h.DB.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Habit{})
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "习惯不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// CheckInHabit 打卡。date 是用户日历日期；不传时使用用户时区的今天。
func (h *HabitHandler) CheckInHabit(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var tzUser model.User
	h.DB.Select("timezone").First(&tzUser, userID)
	loc := model.UserLocation(tzUser.Timezone)
	now := time.Now().In(loc)
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)

	var habit model.Habit
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "习惯不存在"})
		return
	}

	var payload map[string]interface{}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	checkDay := todayStart
	if raw := habitString(payload, "date", ""); raw != "" {
		parsed, err := time.ParseInLocation("2006-01-02", raw, loc)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "date 必须是 YYYY-MM-DD"})
			return
		}
		if parsed.After(todayStart) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "不能记录未来日期"})
			return
		}
		createdDay := time.Date(
			habit.CreatedAt.In(loc).Year(), habit.CreatedAt.In(loc).Month(), habit.CreatedAt.In(loc).Day(),
			0, 0, 0, 0, loc,
		)
		if parsed.Before(createdDay) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "打卡日期早于习惯创建日期"})
			return
		}
		checkDay = parsed
	}
	checkDate := checkDay.Format("2006-01-02")

	var existingLog model.HabitLog
	if h.DB.Where("habit_id = ? AND date = ?", id, checkDate).First(&existingLog).RowsAffected > 0 {
		c.JSON(http.StatusOK, gin.H{
			"message":         "该日期已打卡",
			"already_checked": true,
			"log":             existingLog,
			"streak_count":    habit.StreakCount,
		})
		return
	}

	durationMin := habitInt(payload, "duration_min", 0)
	if durationMin == 0 {
		durationMin = habit.DurationMin
	}
	period := habitString(payload, "period", "")
	if period == "" {
		period = habit.PreferredPeriod
	}
	note := habitString(payload, "note", "")

	log := model.HabitLog{
		HabitID:     habit.ID,
		Date:        checkDate,
		Note:        note,
		DurationMin: durationMin,
		Period:      period,
	}
	if err := h.DB.Create(&log).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "打卡失败"})
		return
	}

	habit.StreakCount = h.currentHabitStreak(habit.ID, loc)
	h.DB.Model(&habit).Update("streak_count", habit.StreakCount)

	eventAt := now
	if checkDate != todayStart.Format("2006-01-02") {
		eventAt = time.Date(checkDay.Year(), checkDay.Month(), checkDay.Day(), 12, 0, 0, 0, loc)
	}
	metadata, _ := json.Marshal(map[string]string{"habit_date": checkDate})
	event := model.BehaviorEvent{
		UserID:      userID,
		EventType:   "habit_checked",
		EntityType:  "habit",
		EntityID:    habit.ID,
		SystemTagID: habit.SystemTagID,
		DurationMin: durationMin,
		OccurredAt:  eventAt.UTC(),
		Metadata:    string(metadata),
	}
	if err := h.DB.Create(&event).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "行为事件写入失败"})
		return
	}

	triggerWebhooks(h.DB, userID, model.EventHabitChecked, map[string]interface{}{
		"habit_id":     habit.ID,
		"name":         habit.Name,
		"streak_count": habit.StreakCount,
		"date":         checkDate,
		"note":         note,
	})

	c.JSON(http.StatusOK, gin.H{
		"message":      "打卡成功",
		"habit":        habit,
		"log":          log,
		"streak_count": habit.StreakCount,
	})
}

// UncheckInHabit 取消今天的打卡。
func (h *HabitHandler) UncheckInHabit(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var tzUser model.User
	h.DB.Select("timezone").First(&tzUser, userID)
	loc := model.UserLocation(tzUser.Timezone)
	now := time.Now().In(loc)
	startLocal := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	endLocal := startLocal.AddDate(0, 0, 1)
	today := startLocal.Format("2006-01-02")

	var habit model.Habit
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "习惯不存在"})
		return
	}

	var log model.HabitLog
	if err := h.DB.Where("habit_id = ? AND date = ?", id, today).First(&log).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "今日未打卡，无法取消"})
		return
	}
	if err := h.DB.Delete(&log).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "取消打卡失败"})
		return
	}

	h.DB.Where(
		"user_id = ? AND event_type = ? AND entity_type = ? AND entity_id = ? AND occurred_at >= ? AND occurred_at < ?",
		userID, "habit_checked", "habit", habit.ID, startLocal.UTC(), endLocal.UTC(),
	).Delete(&model.BehaviorEvent{})

	habit.StreakCount = h.currentHabitStreak(habit.ID, loc)
	h.DB.Model(&habit).Update("streak_count", habit.StreakCount)

	triggerWebhooks(h.DB, userID, "habit.unchecked", map[string]interface{}{
		"habit_id":     habit.ID,
		"name":         habit.Name,
		"streak_count": habit.StreakCount,
		"date":         today,
	})

	c.JSON(http.StatusOK, gin.H{
		"message":      "取消打卡成功",
		"streak_count": habit.StreakCount,
	})
}

// GetHabitLogs 获取习惯的打卡记录
func (h *HabitHandler) GetHabitLogs(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	month := c.Query("month")

	var habit model.Habit
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "习惯不存在"})
		return
	}

	var logs []model.HabitLog
	query := h.DB.Where("habit_id = ?", id)
	if month != "" {
		query = query.Where("date LIKE ?", month+"%")
	}
	query.Order("date DESC").Find(&logs)

	c.JSON(http.StatusOK, gin.H{
		"habit": habit,
		"logs":  logs,
	})
}

// UpdateHabitLog 更新已有打卡记录的备注、时长和时段。
func (h *HabitHandler) UpdateHabitLog(c *gin.Context) {
	userID := c.GetUint("userID")
	habitID := c.Param("id")
	logID := c.Param("logId")
	var habit model.Habit
	if err := h.DB.Where("id = ? AND user_id = ?", habitID, userID).First(&habit).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "习惯不存在"})
		return
	}
	var log model.HabitLog
	if err := h.DB.Where("id = ? AND habit_id = ?", logID, habit.ID).First(&log).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "打卡记录不存在"})
		return
	}
	var payload struct {
		Note        *string `json:"note"`
		DurationMin *int    `json:"duration_min"`
		Period      *string `json:"period"`
	}
	if err := c.ShouldBindJSON(&payload); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	updates := map[string]interface{}{}
	if payload.Note != nil {
		updates["note"] = *payload.Note
	}
	if payload.DurationMin != nil {
		if *payload.DurationMin < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "duration_min 不能为负数"})
			return
		}
		updates["duration_min"] = *payload.DurationMin
	}
	if payload.Period != nil {
		updates["period"] = *payload.Period
	}
	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "没有可更新字段"})
		return
	}
	if err := h.DB.Model(&log).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新打卡记录失败"})
		return
	}
	h.DB.First(&log, log.ID)
	c.JSON(http.StatusOK, log)
}

// GetHabitStreak 获取习惯的连续打卡天数
func (h *HabitHandler) GetHabitStreak(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var habit model.Habit
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "习惯不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"habit_id":     habit.ID,
		"streak_count": habit.StreakCount,
	})
}

func (h *HabitHandler) currentHabitStreak(habitID uint, loc *time.Location) int {
	now := time.Now().In(loc)
	cursor := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	var count int64
	h.DB.Model(&model.HabitLog{}).
		Where("habit_id = ? AND date = ?", habitID, cursor.Format("2006-01-02")).
		Count(&count)
	if count == 0 {
		cursor = cursor.AddDate(0, 0, -1)
	}

	streak := 0
	for {
		count = 0
		h.DB.Model(&model.HabitLog{}).
			Where("habit_id = ? AND date = ?", habitID, cursor.Format("2006-01-02")).
			Count(&count)
		if count == 0 {
			break
		}
		streak++
		cursor = cursor.AddDate(0, 0, -1)
	}
	return streak
}

func (h *HabitHandler) ownsSystemTag(userID uint, tagID uint) bool {
	var count int64
	h.DB.Model(&model.SystemTag{}).
		Where("id = ? AND user_id = ?", tagID, userID).
		Count(&count)
	return count > 0
}

func habitString(payload map[string]interface{}, key string, fallback string) string {
	value, ok := payload[key]
	if !ok || value == nil {
		return fallback
	}
	text, ok := value.(string)
	if !ok {
		return fallback
	}
	return text
}

func habitInt(payload map[string]interface{}, key string, fallback int) int {
	value, ok := payload[key]
	if !ok {
		return fallback
	}
	number, ok := habitNumber(value)
	if !ok {
		return fallback
	}
	return number
}

func habitNumber(value interface{}) (int, bool) {
	switch number := value.(type) {
	case float64:
		return int(number), true
	case float32:
		return int(number), true
	case int:
		return number, true
	case int64:
		return int(number), true
	case json.Number:
		parsed, err := number.Int64()
		return int(parsed), err == nil
	default:
		return 0, false
	}
}

func habitBool(payload map[string]interface{}, key string, fallback bool) bool {
	value, ok := payload[key]
	if !ok {
		return fallback
	}
	flag, ok := value.(bool)
	if !ok {
		return fallback
	}
	return flag
}

func habitUintPtr(payload map[string]interface{}, key string) (*uint, bool) {
	value, ok := payload[key]
	if !ok || value == nil {
		return nil, true
	}
	number, ok := habitNumber(value)
	if !ok || number <= 0 {
		return nil, false
	}
	result := uint(number)
	return &result, true
}

func habitJSON(value interface{}, fallback string) string {
	if value == nil {
		return fallback
	}
	if text, ok := value.(string); ok {
		if strings.TrimSpace(text) == "" {
			return fallback
		}
		return text
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return fallback
	}
	return string(encoded)
}
