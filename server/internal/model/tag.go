package model

import (
	"time"

	"gorm.io/gorm"
)

// Tag 标签模型
type Tag struct {
	ID        uint           `json:"id" gorm:"primaryKey"`
	Name      string         `json:"name" gorm:"size:50;not null;uniqueIndex:idx_user_tag_name"`
	Color     string         `json:"color" gorm:"size:20;default:'#0075de'"`
	UserID    uint           `json:"user_id" gorm:"not null;uniqueIndex:idx_user_tag_name"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `json:"-" gorm:"index"`
}

// TaskTag 任务-标签关联表
type TaskTag struct {
	TaskID uint `json:"task_id" gorm:"primaryKey"`
	TagID  uint `json:"tag_id" gorm:"primaryKey"`
}
