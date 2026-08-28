package model

import "time"

// ReminderConfig 休息提醒配置
type ReminderConfig struct {
	ID                   uint      `json:"id" gorm:"primaryKey"`
	UserID               uint      `json:"user_id" gorm:"not null;uniqueIndex"`
	WorkMinutes          int       `json:"work_minutes" gorm:"default:25"`            // 工作时长（分钟）
	MicroRestSeconds     int       `json:"micro_rest_seconds" gorm:"default:20"`      // 小憩时长（秒）
	LongRestMinutes      int       `json:"long_rest_minutes" gorm:"default:5"`        // 休息时长（分钟）
	MicroRestsBeforeLong int       `json:"micro_rests_before_long" gorm:"default:2"`  // 几次小憩后触发长休息
	LockScreenMode       string    `json:"lock_screen_mode" gorm:"default:window;size:20"` // 锁屏模式: window(窗口) / fullscreen(全屏)
	NotifyBeforeSec      int       `json:"notify_before_seconds" gorm:"default:30"`  // 提前提醒秒数
	AutoLoop             bool      `json:"auto_loop" gorm:"default:true"`             // 自动循环
	AutoStartOnLaunch    bool      `json:"auto_start_on_launch" gorm:"default:true"`  // 开机自动启动
	MicroRestStrict      bool      `json:"micro_rest_strict" gorm:"default:false"`    // 小憩严格模式（不能跳过）
	LongRestStrict       bool      `json:"long_rest_strict" gorm:"default:false"`     // 休息严格模式（不能跳过）
	AllowPostponeMicro   bool      `json:"allow_postpone_micro" gorm:"default:true"`  // 允许延后小憩
	AllowPostponeLong    bool      `json:"allow_postpone_long" gorm:"default:true"`   // 允许延后休息
	CreatedAt            time.Time `json:"created_at" gorm:"autoCreateTime"`
	UpdatedAt            time.Time `json:"updated_at" gorm:"autoUpdateTime"`
}

// ReminderSession 休息提醒会话记录（每次完整的 工作+休息 为一个会话）
type ReminderSession struct {
	ID           uint       `json:"id" gorm:"primaryKey"`
	UserID       uint       `json:"user_id" gorm:"not null;index"`
	StartedAt    time.Time  `json:"started_at" gorm:"not null"`
	WorkEndedAt  *time.Time `json:"work_ended_at"` // 工作阶段结束时间
	RestEndedAt  *time.Time `json:"rest_ended_at"` // 休息阶段结束时间
	WorkSeconds  int        `json:"work_seconds"`  // 实际工作时长
	RestSeconds  int        `json:"rest_seconds"`  // 实际休息时长
	SkippedRest  bool       `json:"skipped_rest"`  // 是否跳过休息
	Device       string     `json:"device" gorm:"size:50"` // 设备来源
	CreatedAt    time.Time  `json:"created_at" gorm:"autoCreateTime"`
}

// ReminderStats 休息提醒统计数据
type ReminderStats struct {
	TotalWorkSeconds  int                `json:"total_work_seconds"`
	TotalRestSeconds  int                `json:"total_rest_seconds"`
	SessionCount      int                `json:"session_count"`
	SkipCount         int                `json:"skip_count"`
	Daily             []DailyReminderStats `json:"daily,omitempty"`
}

// DailyReminderStats 每日休息提醒统计
type DailyReminderStats struct {
	Date            string `json:"date"`
	WorkSeconds     int    `json:"work_seconds"`
	RestSeconds     int    `json:"rest_seconds"`
	SessionCount    int    `json:"session_count"`
	SkipCount       int    `json:"skip_count"`
}