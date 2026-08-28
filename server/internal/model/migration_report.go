package model

import "time"

// MigrationReport 保留每次本地数据合并的可审计摘要，不保存原始用户内容。
type MigrationReport struct {
	ID             uint      `json:"id" gorm:"primaryKey"`
	UserID         uint      `json:"user_id" gorm:"not null;index"`
	ConflictPolicy string    `json:"conflict_policy" gorm:"size:20"`
	Status         string    `json:"status" gorm:"size:20;not null;default:succeeded"`
	Fingerprint    string    `json:"-" gorm:"size:64;index:idx_migration_report_fingerprint"`
	Created        string    `json:"created" gorm:"type:text;not null"`
	CreatedAt      time.Time `json:"created_at"`
}
