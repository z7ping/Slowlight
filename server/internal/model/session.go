package model

import "time"

// WorkSession 工作/休息会话记录
type WorkSession struct {
	ID             uint       `json:"id" gorm:"primaryKey"`
	UserID         uint       `json:"user_id" gorm:"not null;index"`
	SessionType    string     `json:"session_type" gorm:"size:20;not null"` // work, break, long_break
	StartedAt      time.Time  `json:"started_at" gorm:"not null"`
	EndedAt        *time.Time `json:"ended_at"`
	DurationSec    int        `json:"duration_seconds"`
	Device         string     `json:"device" gorm:"size:50"` // web, android, ios
	TaskID         *uint      `json:"task_id"`
	SystemTagID    *uint      `json:"system_tag_id" gorm:"index"` // 番茄钟关联的系统标签
	CreatedAt      time.Time  `json:"created_at" gorm:"autoCreateTime"`

	// 配置字段（不入库，仅用于前端配置同步）
	WorkMinutes    int        `json:"work_minutes" gorm:"-"`
	BreakMinutes   int        `json:"break_minutes" gorm:"-"`
}

// SessionConfig 用户的番茄钟配置
type SessionConfig struct {
	WorkMinutes     int  `json:"work_minutes"`      // 工作时长（默认25）
	BreakMinutes    int  `json:"break_minutes"`     // 短休息时长（默认5）
	LongBreakMin    int  `json:"long_break_minutes"` // 长休息时长（默认15）
	SessionsBeforeLong int `json:"sessions_before_long"` // 几个工作周期后长休息（默认4）
	LockScreen      bool `json:"lock_screen"`       // 是否启用强制锁屏
}

// DefaultConfig 默认番茄钟配置
func DefaultConfig() SessionConfig {
	return SessionConfig{
		WorkMinutes:        25,
		BreakMinutes:       5,
		LongBreakMin:       15,
		SessionsBeforeLong: 4,
		LockScreen:         false,
	}
}

// SessionStats 统计数据
type SessionStats struct {
	TotalWorkSeconds  int `json:"total_work_seconds"`
	TotalBreakSeconds int `json:"total_break_seconds"`
	WorkCount         int `json:"work_count"`
	BreakCount        int `json:"break_count"`
	Sessions          []DailyStats `json:"daily,omitempty"`
}

// DailyStats 每日统计
type DailyStats struct {
	Date             string `json:"date"`
	WorkSeconds      int    `json:"work_seconds"`
	BreakSeconds     int    `json:"break_seconds"`
	WorkCount        int    `json:"work_count"`
	BreakCount       int    `json:"break_count"`
}

// ActiveSession 当前活跃会话
type ActiveSession struct {
	*WorkSession
	Config SessionConfig `json:"config"`
}
