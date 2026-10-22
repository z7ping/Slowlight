package handler

import (
    "context"
    "errors"
    "log"
    "time"

    "gorm.io/gorm"

    "slowlight/internal/model"
    "slowlight/internal/secureconfig"
)

// Callback 的耗时工作独立于浏览器连接执行，状态写入数据库供 Windows/Android 轮询。
func (h *GitHubOAuthHandler) processOAuthCallback(session model.OAuthLoginSession, code string) {
    started := time.Now()
    defer func() {
        if recover() != nil {
            h.oauthFailed(session.ID, "worker", "oauth_internal_error", started)
        }
    }()
    ctx, cancel := context.WithTimeout(context.Background(), 80*time.Second)
    defer cancel()

    h.oauthStage(session.ID, "token")
    clientID, secret, callback, err := githubConfig()
    if err != nil {
        h.oauthFailed(session.ID, "config", "oauth_config_invalid", started)
        return
    }
    token, err := h.exchangeToken(ctx, clientID, secret, callback, code, session.CodeVerifier)
    if err != nil {
        h.oauthFailedFromError(session.ID, "token", "github_unavailable", started, err)
        return
    }

    // 服务端现有 AES-GCM 加密设施；明文令牌绝不写库。
    encrypted, err := secureconfig.Encrypt(token)
    if err != nil {
        h.oauthFailed(session.ID, "token_store", "oauth_config_invalid", started)
        return
    }
    update := h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status = ?", session.ID, "processing").
        Updates(map[string]interface{}{
            "recovery_token": encrypted, "code_verifier": "",
            "error_stage": "profile",
        })
    if update.Error != nil || update.RowsAffected != 1 {
        h.oauthFailed(session.ID, "token_store", "oauth_account_save_failed", started)
        return
    }
    log.Printf("github oauth stage=token_ok session=%s duration_ms=%d",
        oauthHash(session.ID)[:12], time.Since(started).Milliseconds())
    h.finishGitHubIdentity(ctx, session, token, started)
}

// 每次恢复只重试幂等的 /user 查询，不重放 GitHub 的一次性 authorization code。
func (h *GitHubOAuthHandler) processOAuthRecovery(sessionID string) {
    ctx, cancel := context.WithTimeout(context.Background(), 80*time.Second)
    defer cancel()
    started := time.Now()
    var session model.OAuthLoginSession
    if err := h.DB.First(&session, "id = ? AND status = ?", sessionID, "processing").Error; err != nil { return }
    if time.Now().After(session.ExpiresAt) {
        h.oauthFailed(session.ID, "profile", "github_profile_unavailable", started)
        return
    }
    token, err := secureconfig.Decrypt(session.RecoveryToken)
    if err != nil || token == "" {
        h.oauthFailed(session.ID, "profile", "oauth_config_invalid", started)
        return
    }
    h.finishGitHubIdentity(ctx, session, token, started)
}

func (h *GitHubOAuthHandler) finishGitHubIdentity(ctx context.Context, session model.OAuthLoginSession, token string, started time.Time) {
    h.oauthStage(session.ID, "profile")
    profile, err := h.loadProfile(ctx, token)
    if err != nil {
        var oauthErr *githubOAuthError
        if errors.As(err, &oauthErr) && oauthErr.Code == "github_profile_unavailable" &&
            session.RecoveryAttempts < 2 && time.Now().Before(session.ExpiresAt) {
            next := time.Now().Add(time.Duration(10*(session.RecoveryAttempts+1)) * time.Second)
            result := h.DB.Model(&model.OAuthLoginSession{}).
                Where("id = ? AND status = ?", session.ID, "processing").
                Updates(map[string]interface{}{
                    "status": "retryable", "error_stage": "profile",
                    "error_code": oauthErr.Code, "retry_after": next,
                    "recovery_attempts": session.RecoveryAttempts+1,
                })
            if result.Error == nil && result.RowsAffected == 1 {
                log.Printf("github oauth deferred_retry session=%s stage=profile attempt=%d",
                    oauthHash(session.ID)[:12], session.RecoveryAttempts+1)
                return
            }
        }
        h.oauthFailedFromError(session.ID, "profile", "github_profile_unavailable", started, err)
        return
    }
    h.oauthStage(session.ID, "account")
    user, err := h.resolveUser(profile, session.TargetUserID)
    if err != nil {
        code := "oauth_account_save_failed"
        if err.Error() == "GitHub 账号已绑定其他用户" || err.Error() == "当前账号已有 GitHub 绑定" {
            code = "oauth_account_conflict"
        }
        h.oauthFailed(session.ID, "account", code, started)
        return
    }
    result := h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status = ? AND expires_at > ?", session.ID, "processing", time.Now()).
        Updates(map[string]interface{}{
            "status": "ready", "result_user_id": user.ID,
            "recovery_token": "", "code_verifier": "", "error_stage": "",
            "error_code": "",
        })
    if result.Error != nil || result.RowsAffected != 1 {
        h.oauthFailed(session.ID, "account", "oauth_account_save_failed", started)
        return
    }
    log.Printf("github oauth ready session=%s duration_ms=%d",
        oauthHash(session.ID)[:12], time.Since(started).Milliseconds())
}

func (h *GitHubOAuthHandler) oauthStage(sessionID, stage string) {
    h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status = ?", sessionID, "processing").
        Update("error_stage", stage)
}

func (h *GitHubOAuthHandler) oauthFailedFromError(sessionID, stage, fallback string, started time.Time, err error) {
    var oauthErr *githubOAuthError
    code := fallback
    if errors.As(err, &oauthErr) { code = oauthErr.Code }
    h.oauthFailed(sessionID, stage, code, started)
}

func (h *GitHubOAuthHandler) oauthFailed(sessionID, stage, code string, started time.Time) {
    result := h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status = ?", sessionID, "processing").
        Updates(map[string]interface{}{
            "status": "failed", "error_code": code, "error_stage": stage,
            "recovery_token": "", "code_verifier": "",
        })
    log.Printf("github oauth failure session=%s stage=%s code=%s duration_ms=%d save_failed=%t",
        oauthHash(sessionID)[:12], stage, code, time.Since(started).Milliseconds(), result.Error != nil)
}

func (h *GitHubOAuthHandler) resumeIfRequired(session model.OAuthLoginSession) {
    now := time.Now()
    if !session.ExpiresAt.After(now) { return }
    if session.Status == "processing" && session.RecoveryToken == "" &&
        now.Sub(session.UpdatedAt) > 100*time.Second {
        // 已经发往 GitHub 的一次性 code 不能安全重放。明确标记未知结果，避免无限等待。
        h.DB.Model(&model.OAuthLoginSession{}).
            Where("id = ? AND status = ? AND updated_at < ?", session.ID, "processing", now.Add(-100*time.Second)).
            Updates(map[string]interface{}{
                "status": "failed", "error_code": "oauth_result_unknown",
                "error_stage": "token", "code_verifier": "",
            })
        return
    }
    if session.RecoveryToken == "" { return }
    var query *gorm.DB
    if session.Status == "retryable" && !session.RetryAfter.After(now) {
        query = h.DB.Model(&model.OAuthLoginSession{}).
            Where("id = ? AND status = ? AND retry_after <= ?", session.ID, "retryable", now)
    } else if session.Status == "processing" && now.Sub(session.UpdatedAt) > 100*time.Second {
        // 服务实例重启或处理协程意外退出，采用有条件状态更新抢占恢复。
        query = h.DB.Model(&model.OAuthLoginSession{}).
            Where("id = ? AND status = ? AND updated_at < ?", session.ID, "processing", now.Add(-100*time.Second))
    } else { return }
    result := query.Updates(map[string]interface{}{"status": "processing", "error_stage": "profile"})
    if result.Error == nil && result.RowsAffected == 1 {
        go h.processOAuthRecovery(session.ID)
    }
}
