package handler

import (
	"net/http"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type SessionHandler struct {
	DB *gorm.DB
}

func NewSessionHandler(db *gorm.DB) *SessionHandler {
	// 自动建表
	db.AutoMigrate(&model.WorkSession{})
	return &SessionHandler{DB: db}
}

// resolveSessionSystemTag 统一解析会话系统标签：已有值优先，其次继承关联任务。
func (h *SessionHandler) resolveSessionSystemTag(db *gorm.DB, session *model.WorkSession) *uint {
	if session.SystemTagID != nil {
		return session.SystemTagID
	}
	if session.TaskID == nil {
		return nil
	}

	var task model.Task
	if err := db.Select("system_tag_id").
		Where("id = ? AND user_id = ?", *session.TaskID, session.UserID).
		First(&task).Error; err == nil {
		return task.SystemTagID
	}
	return nil
}

// createSessionEndedBehaviorEvent 让 WorkSession 与 BehaviorEvent 保持一一对应。
func (h *SessionHandler) createSessionEndedBehaviorEvent(db *gorm.DB, session *model.WorkSession, occurredAt time.Time) error {
	if session.SessionType != "work" {
		return nil
	}

	durationMin := session.DurationSec / 60
	if durationMin < 1 {
		durationMin = 1
	}
	event := model.BehaviorEvent{
		UserID:      session.UserID,
		EventType:   "session_ended",
		EntityType:  "session",
		EntityID:    session.ID,
		SystemTagID: session.SystemTagID,
		DurationMin: durationMin,
		OccurredAt:  occurredAt,
	}
	return db.Create(&event).Error
}

// StartSession 开始一个工作/休息会话
func (h *SessionHandler) StartSession(c *gin.Context) {
	userID := c.GetUint("userID")

	var req struct {
		SessionType string `json:"session_type" binding:"required,oneof=work break long_break"`
		TaskID      *uint  `json:"task_id"`
		Device      string `json:"device"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}
	if req.TaskID != nil {
		var count int64
		h.DB.Model(&model.Task{}).
			Where("id = ? AND user_id = ?", *req.TaskID, userID).
			Count(&count)
		if count == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "关联任务不存在"})
			return
		}
	}

	// 用事务保证“自动结束旧会话 + 记录行为事件 + 创建新会话”原子性。
	var session model.WorkSession
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		var existing model.WorkSession
		result := tx.Where("user_id = ? AND ended_at IS NULL", userID).First(&existing)
		if result.Error == nil {
			now := time.Now()
			existing.EndedAt = &now
			existing.DurationSec = int(now.Sub(existing.StartedAt).Seconds())
			existing.SystemTagID = h.resolveSessionSystemTag(tx, &existing)
			if err := tx.Save(&existing).Error; err != nil {
				return err
			}
			if err := h.createSessionEndedBehaviorEvent(tx, &existing, now); err != nil {
				return err
			}
		}

		session = model.WorkSession{
			UserID:      userID,
			SessionType: req.SessionType,
			StartedAt:   time.Now(),
			Device:      req.Device,
			TaskID:      req.TaskID,
		}
		return tx.Create(&session).Error
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建会话失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "会话已开始",
		"session": session,
	})
}

// EndSession 结束当前会话
func (h *SessionHandler) EndSession(c *gin.Context) {
	userID := c.GetUint("userID")

	var req struct {
		SystemTagID *uint `json:"system_tag_id"`
	}
	// body 可以为空，所以不校验 binding
	_ = c.ShouldBindJSON(&req)
	if req.SystemTagID != nil {
		var count int64
		h.DB.Model(&model.SystemTag{}).
			Where("id = ? AND user_id = ?", *req.SystemTagID, userID).
			Count(&count)
		if count == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "观察标签不存在"})
			return
		}
	}

	var session model.WorkSession
	now := time.Now()
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		result := tx.Where("user_id = ? AND ended_at IS NULL", userID).
			Order("started_at DESC").First(&session)
		if result.Error != nil {
			return result.Error
		}

		session.EndedAt = &now
		session.DurationSec = int(now.Sub(session.StartedAt).Seconds())

		// 有关联任务时优先继承任务标签；否则使用客户端显式选择。
		systemTagID := h.resolveSessionSystemTag(tx, &session)
		if systemTagID == nil && req.SystemTagID != nil {
			systemTagID = req.SystemTagID
		}
		session.SystemTagID = systemTagID

		if err := tx.Save(&session).Error; err != nil {
			return err
		}
		return h.createSessionEndedBehaviorEvent(tx, &session, now)
	})
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			c.JSON(http.StatusBadRequest, gin.H{"error": "没有进行中的会话"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "结束会话失败"})
		return
	}

	// 触发 Webhook
	triggerWebhooks(h.DB, userID, model.EventSessionEnded, map[string]interface{}{
		"session_id":   session.ID,
		"session_type": session.SessionType,
		"task_id":      session.TaskID,
		"duration_sec": session.DurationSec,
		"started_at":   session.StartedAt.Unix(),
		"ended_at":     now.Unix(),
	})

	c.JSON(http.StatusOK, gin.H{
		"message":  "会话已结束",
		"session":  session,
		"duration": session.DurationSec,
	})
}

// GetActiveSession 获取当前活跃会话
func (h *SessionHandler) GetActiveSession(c *gin.Context) {
	userID := c.GetUint("userID")

	var session model.WorkSession
	result := h.DB.Where("user_id = ? AND ended_at IS NULL", userID).Order("started_at DESC").First(&session)

	config := model.DefaultConfig()

	if result.Error != nil {
		c.JSON(http.StatusOK, gin.H{
			"active": false,
			"config": config,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"active":  true,
		"session": session,
		"config":  config,
	})
}

// GetStats 获取统计数据
func (h *SessionHandler) GetStats(c *gin.Context) {
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

	// 总体统计
	var sessions []model.WorkSession
	h.DB.Where("user_id = ? AND started_at >= ? AND ended_at IS NOT NULL", userID, since).
		Order("started_at ASC").Find(&sessions)

	stats := model.SessionStats{}
	dailyMap := make(map[string]*model.DailyStats)

	for _, s := range sessions {
		dateKey := s.StartedAt.Format("2006-01-02")
		if _, ok := dailyMap[dateKey]; !ok {
			dailyMap[dateKey] = &model.DailyStats{Date: dateKey}
		}
		d := dailyMap[dateKey]

		if s.SessionType == "work" {
			stats.TotalWorkSeconds += s.DurationSec
			stats.WorkCount++
			d.WorkSeconds += s.DurationSec
			d.WorkCount++
		} else {
			stats.TotalBreakSeconds += s.DurationSec
			stats.BreakCount++
			d.BreakSeconds += s.DurationSec
			d.BreakCount++
		}
	}

	// 按日期排序
	for _, d := range dailyMap {
		stats.Sessions = append(stats.Sessions, *d)
	}

	c.JSON(http.StatusOK, stats)
}

// GetTodayStats 获取今日统计
func (h *SessionHandler) GetTodayStats(c *gin.Context) {
	userID := c.GetUint("userID")

	// 用用户时区算"今日"
	var tzUser model.User
	h.DB.Select("timezone").First(&tzUser, userID)
	loc := model.UserLocation(tzUser.Timezone)
	today := time.Now().In(loc).Format("2006-01-02")
	startOfDay, _ := time.ParseInLocation("2006-01-02", today, loc)
	endOfDay := startOfDay.Add(24 * time.Hour)

	var sessions []model.WorkSession
	h.DB.Where("user_id = ? AND started_at >= ? AND started_at < ? AND ended_at IS NOT NULL",
		userID, startOfDay, endOfDay).Find(&sessions)

	stats := model.SessionStats{}
	for _, s := range sessions {
		if s.SessionType == "work" {
			stats.TotalWorkSeconds += s.DurationSec
			stats.WorkCount++
		} else {
			stats.TotalBreakSeconds += s.DurationSec
			stats.BreakCount++
		}
	}

	c.JSON(http.StatusOK, stats)
}
