package handler

import (
	"net/http"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ReminderHandler struct {
	DB *gorm.DB
}

func NewReminderHandler(db *gorm.DB) *ReminderHandler {
	// 自动建表
	db.AutoMigrate(&model.ReminderConfig{}, &model.ReminderSession{})
	return &ReminderHandler{DB: db}
}

// defaultReminderConfig 返回默认提醒配置
func defaultReminderConfig(userID uint) model.ReminderConfig {
	return model.ReminderConfig{
		UserID:               userID,
		WorkMinutes:          25,
		MicroRestSeconds:     20,
		LongRestMinutes:      5,
		MicroRestsBeforeLong: 2,
		LockScreenMode:       "window",
		NotifyBeforeSec:      30,
		AutoLoop:             true,
		AutoStartOnLaunch:    true,
		MicroRestStrict:      false,
		LongRestStrict:       false,
		AllowPostponeMicro:   true,
		AllowPostponeLong:    true,
	}
}

// GetConfig 获取用户提醒配置
func (h *ReminderHandler) GetConfig(c *gin.Context) {
	userID := c.GetUint("userID")

	var config model.ReminderConfig
	result := h.DB.Where("user_id = ?", userID).Limit(1).Find(&config)

	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询提醒配置失败"})
		return
	}

	if config.ID == 0 {
		config = defaultReminderConfig(userID)
	}

	c.JSON(http.StatusOK, config)
}

// SaveConfig 保存用户提醒配置
func (h *ReminderHandler) SaveConfig(c *gin.Context) {
	userID := c.GetUint("userID")

	var req struct {
		WorkMinutes          *int   `json:"work_minutes"`
		MicroRestSeconds     *int   `json:"micro_rest_seconds"`
		LongRestMinutes      *int   `json:"long_rest_minutes"`
		MicroRestsBeforeLong *int   `json:"micro_rests_before_long"`
		LockScreenMode       *string `json:"lock_screen_mode"`
		NotifyBeforeSec      *int   `json:"notify_before_seconds"`
		AutoLoop             *bool  `json:"auto_loop"`
		AutoStartOnLaunch    *bool  `json:"auto_start_on_launch"`
		MicroRestStrict      *bool  `json:"micro_rest_strict"`
		LongRestStrict       *bool  `json:"long_rest_strict"`
		AllowPostponeMicro   *bool  `json:"allow_postpone_micro"`
		AllowPostponeLong    *bool  `json:"allow_postpone_long"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}

	var config model.ReminderConfig
	result := h.DB.Where("user_id = ?", userID).Limit(1).Find(&config)

	if result.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询提醒配置失败"})
		return
	}

	if config.ID == 0 {
		config = defaultReminderConfig(userID)
	}

	if req.WorkMinutes != nil {
		config.WorkMinutes = *req.WorkMinutes
	}
	if req.MicroRestSeconds != nil {
		config.MicroRestSeconds = *req.MicroRestSeconds
	}
	if req.LongRestMinutes != nil {
		config.LongRestMinutes = *req.LongRestMinutes
	}
	if req.MicroRestsBeforeLong != nil {
		config.MicroRestsBeforeLong = *req.MicroRestsBeforeLong
	}
	if req.LockScreenMode != nil {
		config.LockScreenMode = *req.LockScreenMode
	}
	if req.NotifyBeforeSec != nil {
		config.NotifyBeforeSec = *req.NotifyBeforeSec
	}
	if req.AutoLoop != nil {
		config.AutoLoop = *req.AutoLoop
	}
	if req.AutoStartOnLaunch != nil {
		config.AutoStartOnLaunch = *req.AutoStartOnLaunch
	}
	if req.MicroRestStrict != nil {
		config.MicroRestStrict = *req.MicroRestStrict
	}
	if req.LongRestStrict != nil {
		config.LongRestStrict = *req.LongRestStrict
	}
	if req.AllowPostponeMicro != nil {
		config.AllowPostponeMicro = *req.AllowPostponeMicro
	}
	if req.AllowPostponeLong != nil {
		config.AllowPostponeLong = *req.AllowPostponeLong
	}

	h.DB.Save(&config)

	c.JSON(http.StatusOK, gin.H{
		"message": "配置已保存",
		"config":  config,
	})
}

// StartWork 开始一个工作阶段
func (h *ReminderHandler) StartWork(c *gin.Context) {
	userID := c.GetUint("userID")

	var req struct {
		Device string `json:"device"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		// 设备参数可选，不强制要求
		req.Device = ""
	}

	// 检查是否有未结束的会话
	var existing model.ReminderSession
	result := h.DB.Where("user_id = ? AND rest_ended_at IS NULL", userID).Order("started_at DESC").First(&existing)
	if result.Error == nil {
		// 有未结束的会话，自动结束它
		now := time.Now()
		existing.RestEndedAt = &now
		existing.SkippedRest = true
		h.DB.Save(&existing)
	}

	session := model.ReminderSession{
		UserID:    userID,
		StartedAt: time.Now(),
		Device:    req.Device,
	}
	h.DB.Create(&session)

	c.JSON(http.StatusOK, gin.H{
		"message": "工作阶段已开始",
		"session": session,
	})
}

// StartRest 工作结束，开始休息阶段
func (h *ReminderHandler) StartRest(c *gin.Context) {
	userID := c.GetUint("userID")

	var session model.ReminderSession
	result := h.DB.Where("user_id = ? AND work_ended_at IS NULL AND rest_ended_at IS NULL", userID).
		Order("started_at DESC").First(&session)
	if result.Error != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "没有进行中的工作阶段"})
		return
	}

	now := time.Now()
	session.WorkEndedAt = &now
	session.WorkSeconds = int(now.Sub(session.StartedAt).Seconds())
	h.DB.Save(&session)

	c.JSON(http.StatusOK, gin.H{
		"message": "休息阶段已开始",
		"session": session,
	})
}

// EndRest 休息结束
func (h *ReminderHandler) EndRest(c *gin.Context) {
	userID := c.GetUint("userID")

	var session model.ReminderSession
	result := h.DB.Where("user_id = ? AND work_ended_at IS NOT NULL AND rest_ended_at IS NULL", userID).
		Order("started_at DESC").First(&session)
	if result.Error != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "没有进行中的休息阶段"})
		return
	}

	now := time.Now()
	session.RestEndedAt = &now
	session.RestSeconds = int(now.Sub(*session.WorkEndedAt).Seconds())
	h.DB.Save(&session)

	c.JSON(http.StatusOK, gin.H{
		"message": "休息阶段已结束",
		"session": session,
	})
}

// SkipRest 跳过休息
func (h *ReminderHandler) SkipRest(c *gin.Context) {
	userID := c.GetUint("userID")

	var session model.ReminderSession
	result := h.DB.Where("user_id = ? AND work_ended_at IS NOT NULL AND rest_ended_at IS NULL", userID).
		Order("started_at DESC").First(&session)
	if result.Error != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "没有进行中的休息阶段"})
		return
	}

	now := time.Now()
	session.RestEndedAt = &now
	session.SkippedRest = true
	session.RestSeconds = 0
	h.DB.Save(&session)

	c.JSON(http.StatusOK, gin.H{
		"message": "休息已跳过",
		"session": session,
	})
}

// GetStats 获取统计数据
func (h *ReminderHandler) GetStats(c *gin.Context) {
	userID := c.GetUint("userID")
	period := c.DefaultQuery("period", "week") // week, month, all

	var since time.Time
	now := time.Now()
	switch period {
	case "month":
		since = now.AddDate(0, -1, 0)
	case "all":
		since = time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	default: // week
		since = now.AddDate(0, 0, -7)
	}

	// 查询会话
	var sessions []model.ReminderSession
	h.DB.Where("user_id = ? AND created_at >= ? AND rest_ended_at IS NOT NULL", userID, since).
		Order("created_at ASC").Find(&sessions)

	stats := model.ReminderStats{}
	dailyMap := make(map[string]*model.DailyReminderStats)

	for _, s := range sessions {
		dateKey := s.CreatedAt.Format("2006-01-02")
		if _, ok := dailyMap[dateKey]; !ok {
			dailyMap[dateKey] = &model.DailyReminderStats{Date: dateKey}
		}
		d := dailyMap[dateKey]

		stats.TotalWorkSeconds += s.WorkSeconds
		stats.TotalRestSeconds += s.RestSeconds
		stats.SessionCount++
		if s.SkippedRest {
			stats.SkipCount++
		}

		d.WorkSeconds += s.WorkSeconds
		d.RestSeconds += s.RestSeconds
		d.SessionCount++
		if s.SkippedRest {
			d.SkipCount++
		}
	}

	// 按日期排序
	for _, d := range dailyMap {
		stats.Daily = append(stats.Daily, *d)
	}

	c.JSON(http.StatusOK, stats)
}

// GetTodayStats 获取今日统计
func (h *ReminderHandler) GetTodayStats(c *gin.Context) {
	userID := c.GetUint("userID")

	// 用用户时区算"今日"
	var tzUser model.User
	h.DB.Select("timezone").First(&tzUser, userID)
	loc := model.UserLocation(tzUser.Timezone)
	today := time.Now().In(loc).Format("2006-01-02")
	startOfDay, _ := time.ParseInLocation("2006-01-02", today, loc)
	endOfDay := startOfDay.Add(24 * time.Hour)

	var sessions []model.ReminderSession
	h.DB.Where("user_id = ? AND created_at >= ? AND created_at < ? AND rest_ended_at IS NOT NULL",
		userID, startOfDay, endOfDay).Find(&sessions)

	stats := model.ReminderStats{}
	for _, s := range sessions {
		stats.TotalWorkSeconds += s.WorkSeconds
		stats.TotalRestSeconds += s.RestSeconds
		stats.SessionCount++
		if s.SkippedRest {
			stats.SkipCount++
		}
	}

	c.JSON(http.StatusOK, stats)
}