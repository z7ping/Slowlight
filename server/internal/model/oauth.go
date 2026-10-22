package model

import "time"

// OAuthIdentity 将外部稳定用户 ID 绑定到 Slowlight 账号，不根据邮箱自动合并。
type OAuthIdentity struct {
	ID             uint      `gorm:"primaryKey"`
	UserID         uint      `gorm:"not null;uniqueIndex:idx_oauth_user_provider"`
	Provider       string    `gorm:"size:32;not null;uniqueIndex:idx_oauth_subject;uniqueIndex:idx_oauth_user_provider"`
	ProviderUserID string    `gorm:"size:100;not null;uniqueIndex:idx_oauth_subject"`
	CreatedAt      time.Time
}

// OAuthLoginSession 由数据库持久化，支持多实例回调和一次性领取。
// State/PollToken 只存 SHA256，不存 GitHub access token 或 Slowlight JWT。
type OAuthLoginSession struct {
	ID           string    `gorm:"primaryKey;size:64"`
	StateHash    string    `gorm:"size:64;uniqueIndex;not null"`
	PollHash     string    `gorm:"size:64;not null"`
	CodeVerifier string    `gorm:"size:128;not null"`
	Status       string    `gorm:"size:20;not null;index"`
	ErrorCode    string    `gorm:"size:64"`
	ErrorStage   string    `gorm:"size:32"`
	// 短时加密暂存 GitHub token，只用于已换码后的用户资料恢复，完成即清除。
	RecoveryToken string `gorm:"type:text"`
	RecoveryAttempts int `gorm:"default:0"`
	RetryAfter time.Time
	UpdatedAt time.Time
	TargetUserID uint      `gorm:"default:0"`
	ResultUserID uint      `gorm:"default:0"`
	ExpiresAt    time.Time `gorm:"not null;index"`
	CreatedAt    time.Time
}
