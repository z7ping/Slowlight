package model

import (
	"time"

	"gorm.io/gorm"
)

// SystemTag 是用户可编辑的观察分类标签。
// DimensionKey 只是可选归属；SystemTag 本身不再等同于身体/认知/产出/关系。
type SystemTag struct {
	ID           uint           `json:"id" gorm:"primaryKey"`
	UserID       uint           `json:"user_id" gorm:"not null;index"`
	Name         string         `json:"name" gorm:"size:50;not null"`
	Icon         string         `json:"icon" gorm:"size:10;default:'🏷️'"`
	Color        string         `json:"color" gorm:"size:20;default:'#1890ff'"`
	DimensionKey DimensionKey   `json:"dimension_key" gorm:"size:30;default:'';index"`
	SortOrder    int            `json:"sort_order" gorm:"default:0"`
	IsDefault    bool           `json:"is_default" gorm:"default:false"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `json:"-" gorm:"index"`
}

// BehaviorEvent 统一行为事实层。
type BehaviorEvent struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	UserID       uint      `json:"user_id" gorm:"not null;index:idx_user_occurred;index:idx_user_event_occurred;index:idx_user_system_occurred"`
	EventType    string    `json:"event_type" gorm:"size:30;not null;index:idx_user_event_occurred"` // habit_checked / task_completed / session_ended / output_created
	EntityType   string    `json:"entity_type" gorm:"size:20;not null"`                              // task / habit / session
	EntityID     uint      `json:"entity_id" gorm:"not null"`
	SystemTagID  *uint     `json:"system_tag_id" gorm:"index:idx_user_system_occurred"`
	DurationMin  int       `json:"duration_min" gorm:"default:0"`
	OccurredAt   time.Time `json:"occurred_at" gorm:"not null;index:idx_user_occurred;index:idx_user_event_occurred;index:idx_user_system_occurred"`
	Metadata     string    `json:"metadata" gorm:"type:text;default:'{}'"`
	IsDeleted    bool      `json:"is_deleted" gorm:"default:false"`
	CreatedAt    time.Time `json:"created_at"`
}
