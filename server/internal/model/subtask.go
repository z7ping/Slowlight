package model

import (
	"time"
)

// Subtask 子任务模型
type Subtask struct {
	ID          uint      `json:"id" gorm:"primaryKey"`
	TaskID      uint      `json:"task_id" gorm:"not null;index"`
	Title       string    `json:"title" gorm:"size:500;not null"`
	IsCompleted bool      `json:"is_completed" gorm:"default:false"`
	SortOrder   int       `json:"sort_order" gorm:"default:0"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
