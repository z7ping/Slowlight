package handler

import (
	"net/http"
    "io"
	"time"
	"errors"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
    "gorm.io/gorm/clause"
)

type SessionHandler struct {
	DB *gorm.DB
}

// completedWorkRounds counts only sessions whose natural completion was
// durably confirmed. Manual ends, old/unknown targets and forced replacement
// do not count. This is scoped to the authenticated user across devices.
func (h *SessionHandler) completedWorkRounds(userID uint) (int64, error) {
    var count int64
    err := h.DB.Model(&model.WorkSession{}).
        Where("user_id = ? AND session_type = ? AND naturally_completed = ? AND ended_at IS NOT NULL",
            userID, "work", true).Count(&count).Error
    return count, err
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

	// 行为事件以整分钟表达；不足一分钟可为 0，不能虚构有效专注。
	durationMin := session.DurationSec / 60
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

// activeSeconds 只计算真正运行的秒数；尚未恢复的暂停段不会继续计时。
func activeSeconds(session model.WorkSession, now time.Time) int {
    until := now
    if session.PausedAt != nil && session.PausedAt.Before(until) {
        until = *session.PausedAt
    }
    seconds := int(until.Sub(session.StartedAt).Seconds()) - session.PausedDurationSec
    if seconds < 0 { return 0 }
    return seconds
}

func finishSessionTiming(session *model.WorkSession, now time.Time) {
    session.DurationSec = activeSeconds(*session, now)
    if session.PausedAt != nil {
        paused := int(now.Sub(*session.PausedAt).Seconds())
        if paused > 0 { session.PausedDurationSec += paused }
    }
    session.PausedAt = nil
    session.EndedAt = &now
}

var errSessionRevisionConflict = errors.New("stale session revision")
var errSessionAlreadyActive = errors.New("another active session exists")

// transitionSession 以会话 ID 限定操作目标，避免多端重试误修改后来开启的新会话。
// 条件写保证连续暂停/继续的重试幂等，同一暂停区间不会被重复累计。
func (h *SessionHandler) transitionSession(c *gin.Context, pause bool) {
    userID := c.GetUint("userID")
    var req struct {
        SessionID uint `json:"session_id" binding:"required"`
        ExpectedRevision *int `json:"expected_revision" binding:"required"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error":"缺少有效的会话 ID"})
        return
    }
    var session model.WorkSession
    err := h.DB.Transaction(func(tx *gorm.DB) error {
        if err := tx.Where("id = ? AND user_id = ? AND ended_at IS NULL",req.SessionID,userID).First(&session).Error; err != nil {
            return err
        }
        now := time.Now()
        if session.Revision != *req.ExpectedRevision {
            // 同一个版本的网络重试可读取结果；更旧的异步重试必须拒绝，
            // 避免 A 暂停、B 恢复后 A 的迟到重试再次暂停。
            if session.Revision == *req.ExpectedRevision + 1 &&
                ((pause && session.PausedAt != nil) || (!pause && session.PausedAt == nil)) {
                return nil
            }
            return errSessionRevisionConflict
        }
        if pause && session.PausedAt == nil {
            // 仅能从 running 进入 paused。
            result := tx.Model(&model.WorkSession{}).Where("id = ? AND user_id = ? AND ended_at IS NULL AND paused_at IS NULL AND revision = ?",req.SessionID,userID,*req.ExpectedRevision).
                Updates(map[string]interface{}{"paused_at":now,"revision":gorm.Expr("revision + 1")})
            if result.Error != nil { return result.Error }
            if result.RowsAffected == 0 { return errSessionRevisionConflict }
        } else if !pause && session.PausedAt != nil {
            paused := int(now.Sub(*session.PausedAt).Seconds())
            if paused < 0 { paused = 0 }
            result := tx.Model(&model.WorkSession{}).Where("id = ? AND user_id = ? AND ended_at IS NULL AND paused_at = ? AND revision = ?",req.SessionID,userID,*session.PausedAt,*req.ExpectedRevision).
                Updates(map[string]interface{}{"paused_at":nil,"paused_duration_sec":gorm.Expr("paused_duration_sec + ?",paused),"revision":gorm.Expr("revision + 1")})
            if result.Error != nil { return result.Error }
            if result.RowsAffected == 0 { return errSessionRevisionConflict }
        }
        session = model.WorkSession{}
        return tx.Where("id = ? AND user_id = ? AND ended_at IS NULL",req.SessionID,userID).First(&session).Error
    })
    if err != nil {
        if errors.Is(err,gorm.ErrRecordNotFound) || errors.Is(err,errSessionRevisionConflict) {
            c.JSON(http.StatusConflict,gin.H{"error":"会话已结束或不属于当前账号，请刷新"})
        } else {
            c.JSON(http.StatusInternalServerError,gin.H{"error":"更新会话状态失败"})
        }
        return
    }
    c.JSON(http.StatusOK,gin.H{"session":session})
}
func (h *SessionHandler) PauseSession(c *gin.Context) { h.transitionSession(c,true) }
func (h *SessionHandler) ResumeSession(c *gin.Context) { h.transitionSession(c,false) }

// StartSession 开始一个工作/休息会话
func (h *SessionHandler) StartSession(c *gin.Context) {
	userID := c.GetUint("userID")

	var req struct {
		SessionType   string `json:"session_type" binding:"required,oneof=work break long_break"`
		TargetMinutes int    `json:"target_minutes"`
		TaskID        *uint  `json:"task_id"`
		Device      string `json:"device"`
        RequireInactive bool `json:"require_inactive"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}
	if req.TargetMinutes < 0 || req.TargetMinutes > 180 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "目标时长必须在 1 到 180 分钟之间"})
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
        if req.RequireInactive {
            // Serialize guarded starts per account; without this lock two
            // concurrent devices could both observe no active session.
            var user model.User
            if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
                Select("id").First(&user, userID).Error; err != nil {
                return err
            }
        }
		var existing model.WorkSession
		result := tx.Where("user_id = ? AND ended_at IS NULL", userID).First(&existing)
        if result.Error != nil && !errors.Is(result.Error, gorm.ErrRecordNotFound) {
            return result.Error
        }
		if result.Error == nil {
            if req.RequireInactive { return errSessionAlreadyActive }
			now := time.Now()
			finishSessionTiming(&existing, now)
			existing.SystemTagID = h.resolveSessionSystemTag(tx, &existing)
			updated := tx.Model(&model.WorkSession{}).
				Where("id = ? AND user_id = ? AND ended_at IS NULL", existing.ID, userID).
				Updates(map[string]interface{}{
					"ended_at": existing.EndedAt,
					"duration_sec": existing.DurationSec,
					"paused_at": nil,
					"paused_duration_sec": existing.PausedDurationSec,
					"system_tag_id": existing.SystemTagID,
				})
			if updated.Error != nil {
				return updated.Error
			}
			if updated.RowsAffected > 0 {
				if err := h.createSessionEndedBehaviorEvent(tx, &existing, now); err != nil {
					return err
				}
			}
		}

		session = model.WorkSession{
			UserID:      userID,
			SessionType:   req.SessionType,
			TargetMinutes: req.TargetMinutes,
			StartedAt:     time.Now(),
			Device:      req.Device,
			TaskID:      req.TaskID,
		}
		return tx.Create(&session).Error
	})
	if err != nil {
        if errors.Is(err, errSessionAlreadyActive) {
            c.JSON(http.StatusConflict, gin.H{"error":"其他设备已有活动专注，请重新核对"})
            return
        }
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
        SessionID *uint `json:"session_id"`
        ExpectedRevision *int `json:"expected_revision"`
        NaturallyCompleted bool `json:"naturally_completed"`
	}
    // Keep legacy empty bodies, but malformed JSON must not accidentally
    // end a different active session with an all-zero request.
    if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
        c.JSON(http.StatusBadRequest, gin.H{"error":"结束会话参数无效"})
        return
    }
    if req.ExpectedRevision != nil && req.SessionID == nil {
        c.JSON(http.StatusBadRequest, gin.H{"error":"指定版本时必须提供会话 ID"})
        return
    }
    if req.NaturallyCompleted &&
        (req.SessionID == nil || req.ExpectedRevision == nil) {
        c.JSON(http.StatusBadRequest, gin.H{"error":"自然完成需提供已确认的会话 ID 和版本"})
        return
    }
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
        query := tx.Where("user_id = ? AND ended_at IS NULL", userID)
        if req.SessionID != nil {
            query = query.Where("id = ?", *req.SessionID)
        }
        result := query.Order("started_at DESC").First(&session)
		if result.Error != nil {
			return result.Error
		}
        if req.ExpectedRevision != nil && session.Revision != *req.ExpectedRevision {
            return errSessionRevisionConflict
        }

		finishSessionTiming(&session, now)
        session.NaturallyCompleted = req.NaturallyCompleted &&
            session.SessionType == "work" &&
            session.TargetMinutes > 0 &&
            session.DurationSec >= session.TargetMinutes*60

		// 有关联任务时优先继承任务标签；否则使用客户端显式选择。
		systemTagID := h.resolveSessionSystemTag(tx, &session)
		if systemTagID == nil && req.SystemTagID != nil {
			systemTagID = req.SystemTagID
		}
		session.SystemTagID = systemTagID

		result = tx.Model(&model.WorkSession{}).Where("id = ? AND user_id = ? AND ended_at IS NULL",session.ID,userID).
            Updates(map[string]interface{}{"ended_at":session.EndedAt,"paused_at":nil,"paused_duration_sec":session.PausedDurationSec,"duration_sec":session.DurationSec,"system_tag_id":session.SystemTagID,"naturally_completed":session.NaturallyCompleted})
        if result.Error != nil { return result.Error }
        if result.RowsAffected == 0 { return gorm.ErrRecordNotFound }
        return h.createSessionEndedBehaviorEvent(tx, &session, now)
	})
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) || errors.Is(err, errSessionRevisionConflict) {
            c.JSON(http.StatusConflict, gin.H{"error":"目标会话不存在、已变更或已结束，请核对当前状态"})
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

    rounds, countErr := h.completedWorkRounds(userID)
    if countErr != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error":"会话已结束，但完成轮次核对失败，请重新查询"})
        return
    }
	c.JSON(http.StatusOK, gin.H{
		"message":  "会话已结束",
		"session":  session,
		"duration": session.DurationSec,
        "completed_work_rounds": rounds,
	})
}

// GetActiveSession 获取当前活跃会话
func (h *SessionHandler) GetActiveSession(c *gin.Context) {
    userID := c.GetUint("userID")
    rounds, err := h.completedWorkRounds(userID)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error":"无法核对专注完成轮次"})
        return
    }

    var session model.WorkSession
    result := h.DB.Where("user_id = ? AND ended_at IS NULL", userID).
        Order("started_at DESC").First(&session)
    config := model.DefaultConfig()
    if errors.Is(result.Error, gorm.ErrRecordNotFound) {
        c.JSON(http.StatusOK, gin.H{
            "active": false,
            "config": config,
            "completed_work_rounds": rounds,
        })
        return
    }
    if result.Error != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error":"获取活跃会话失败"})
        return
    }
    c.JSON(http.StatusOK, gin.H{
        "active": true,
        "session": session,
        "config": config,
        "completed_work_rounds": rounds,
    })
}

// sessionTodayWindow uses the account's calendar day, not a fixed 24 hours.
// On DST transitions that day can last 23 or 25 hours.
func sessionTodayWindow(now time.Time, loc *time.Location) (time.Time, time.Time) {
    today := now.In(loc)
    start := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, loc)
    return start, start.AddDate(0, 0, 1)
}

// GetStats 获取统计数据
func (h *SessionHandler) GetStats(c *gin.Context) {
	userID := c.GetUint("userID")
	period := c.DefaultQuery("period", "week") // week, month, all

    var tzUser model.User
    if err := h.DB.Select("timezone").First(&tzUser, userID).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error":"无法核对用户专注统计时区"})
        return
    }
    loc := model.UserLocation(tzUser.Timezone)

	var since time.Time
	now := time.Now().In(loc)
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
    if err := h.DB.Where("user_id = ? AND started_at >= ? AND ended_at IS NOT NULL", userID, since).
        Order("started_at ASC").Find(&sessions).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error":"无法核对专注统计"})
        return
    }

	stats := model.SessionStats{}
	dailyMap := make(map[string]*model.DailyStats)

	for _, s := range sessions {
        dateKey := s.StartedAt.In(loc).Format("2006-01-02")
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
    if err := h.DB.Select("timezone").First(&tzUser, userID).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error":"无法核对用户今日时区"})
        return
    }
	loc := model.UserLocation(tzUser.Timezone)
    startOfDay, endOfDay := sessionTodayWindow(time.Now(), loc)

	var sessions []model.WorkSession
    if err := h.DB.Where("user_id = ? AND started_at >= ? AND started_at < ? AND ended_at IS NOT NULL",
        userID, startOfDay, endOfDay).Find(&sessions).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error":"无法核对今日专注事实"})
        return
    }

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
