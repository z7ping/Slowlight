package model

import "time"

// AuthRefreshSession 仅保存 Refresh Token 的 SHA-256 摘要，绝不持久化明文。
// 单设备轮换使用行锁，注销和到期记录留存以阻止令牌重放。
type AuthRefreshSession struct {
    TokenHash string     `gorm:"primaryKey;size:64"`
    UserID    uint       `gorm:"not null;index"`
    Method    string     `gorm:"size:16;not null"`
    ExpiresAt time.Time  `gorm:"not null;index"`
    ProofAt   time.Time  `gorm:"not null"`
    RevokedAt *time.Time
    CreatedAt time.Time
}
