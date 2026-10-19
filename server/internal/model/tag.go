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

// LegacySystemTagAlias 把旧 system_tags ID 映射到统一 tags ID。
// 两套 ID 可能数值相同但意义不同，绝不能直接用旧 ID 查询新表。
type LegacySystemTagAlias struct {
	UserID      uint `gorm:"primaryKey"`
	SystemTagID uint `gorm:"primaryKey"`
	TagID       uint `gorm:"not null;index"`
}

// HabitTag / WorkSessionTag / ReflectionTag 为同一标签提供多实体、多对多关联。
// 旧 system_tag_id 与 reflection.context 在过渡期仍保留以兼容旧客户端。
type HabitTag struct {
	HabitID uint `gorm:"primaryKey"`
	TagID   uint `gorm:"primaryKey"`
}

type WorkSessionTag struct {
	WorkSessionID uint `gorm:"primaryKey"`
	TagID         uint `gorm:"primaryKey"`
}

type ReflectionTag struct {
	ReflectionID uint `gorm:"primaryKey"`
	TagID        uint `gorm:"primaryKey"`
}
