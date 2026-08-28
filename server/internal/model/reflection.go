package model

import (
	"time"

	"gorm.io/gorm"
)

// Reflection 保存用户对事实/问题的第一方解释。
// EntryType: observation / reflection。
type Reflection struct {
	ID           uint           `json:"id" gorm:"primaryKey"`
	UserID       uint           `json:"user_id" gorm:"not null;index"`
	EntryType    string         `json:"entry_type" gorm:"size:20;not null;default:'reflection';index"`
	QuestionID   string         `json:"question_id" gorm:"size:120;default:'';index"`
	DimensionKey DimensionKey   `json:"dimension_key" gorm:"size:30;default:'';index"`
	Content      string         `json:"content" gorm:"type:text;not null"`
	Context      string         `json:"-" gorm:"type:text;default:'{}'"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `json:"-" gorm:"index"`
}
