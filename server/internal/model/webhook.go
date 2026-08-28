package model

import "time"

// Webhook 外部 Webhook 配置
type Webhook struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"index"`
	URL       string    `json:"url" gorm:"size:1024"`          // 目标 URL
	Event     string    `json:"event" gorm:"size:50;index"`     // 事件类型
	Secret    string    `json:"-" gorm:"size:255"`              // 签名密钥（不返回给前端）
	Name      string    `json:"name" gorm:"size:100"`           // 备注名称
	IsActive  bool      `json:"is_active" gorm:"default:true"`  // 是否启用
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// 支持的事件类型
const (
	EventTaskCreated   = "task.created"    // 任务创建
	EventTaskCompleted = "task.completed"  // 任务完成
	EventTaskDeleted   = "task.deleted"    // 任务删除
	EventTaskUpdated   = "task.updated"    // 任务更新
	EventHabitChecked  = "habit.checked"   // 习惯打卡
	EventSessionEnded  = "session.ended"   // 番茄钟结束
)
