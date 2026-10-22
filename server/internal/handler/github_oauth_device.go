package handler

import (
    "context"
    "encoding/json"
    "io"
    "net/http"
    "net/url"
    "os"
    "strings"
    "time"

    "github.com/gin-gonic/gin"
    "slowlight/internal/model"
    "slowlight/internal/secureconfig"
)

type githubDeviceCodeResponse struct {
    DeviceCode string `json:"device_code"`
    UserCode string `json:"user_code"`
    VerificationURI string `json:"verification_uri"`
    ExpiresIn int `json:"expires_in"`
    Interval int `json:"interval"`
    Error string `json:"error"`
}

func githubDeviceFlowEnabled() bool {
    return strings.EqualFold(strings.TrimSpace(os.Getenv("GITHUB_OAUTH_ENABLE_DEVICE_FLOW")), "true")
}

// GitHub OAuth App 管理员必须在 GitHub 中打开 Device Flow；默认隐藏备用入口。
func (h *GitHubOAuthHandler) DeviceStatus(c *gin.Context) {
    c.Header("Cache-Control", "no-store")
    c.JSON(http.StatusOK, gin.H{"enabled": githubDeviceFlowEnabled()})
}

func (h *GitHubOAuthHandler) DeviceStart(c *gin.Context) { h.deviceStart(c, 0) }

func (h *GitHubOAuthHandler) DeviceLinkStart(c *gin.Context) {
    h.deviceStart(c, c.GetUint("userID"))
}

func (h *GitHubOAuthHandler) deviceStart(c *gin.Context, target uint) {
    if !githubDeviceFlowEnabled() {
        c.JSON(http.StatusNotImplemented, gin.H{"error": "备用验证码登录尚未启用", "code": "device_flow_disabled"})
        return
    }
    id, _, _, err := githubConfig()
    if err != nil {
        c.JSON(http.StatusServiceUnavailable, gin.H{"error": githubOAuthMessage("oauth_config_invalid")})
        return
    }
    req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodPost, h.DeviceAuthURL,
        strings.NewReader(url.Values{"client_id": {id}}.Encode()))
    if err != nil { c.JSON(500, gin.H{"error": "设备码登录初始化失败"}); return }
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    req.Header.Set("Accept", "application/json")
    resp, err := h.Client.Do(req)
    if err != nil { c.JSON(503, gin.H{"error": githubOAuthMessage("github_unavailable")}); return }
    defer resp.Body.Close()
    var grant githubDeviceCodeResponse
    if err := json.NewDecoder(io.LimitReader(resp.Body, 65536)).Decode(&grant); err != nil {
        c.JSON(502, gin.H{"error": "GitHub 设备授权响应无效"}); return
    }
    if grant.Error == "device_flow_disabled" || grant.Error == "unauthorized_client" {
        c.JSON(409, gin.H{"error": "GitHub OAuth 应用尚未启用设备码授权", "code": "device_flow_disabled"})
        return
    }
    u, parseErr := url.Parse(grant.VerificationURI)
    if resp.StatusCode != http.StatusOK || grant.DeviceCode == "" || grant.UserCode == "" ||
        parseErr != nil || u.Scheme != "https" || u.Host != "github.com" || grant.ExpiresIn <= 0 {
        c.JSON(502, gin.H{"error": "GitHub 设备授权响应无效"}); return
    }
    sessionID, err := oauthRandom()
    if err != nil { c.JSON(500, gin.H{"error": "设备授权初始化失败"}); return }
    state, err := oauthRandom()
    if err != nil { c.JSON(500, gin.H{"error": "设备授权初始化失败"}); return }
    pollToken, err := oauthRandom()
    if err != nil { c.JSON(500, gin.H{"error": "设备授权初始化失败"}); return }
    encrypted, err := secureconfig.Encrypt(grant.DeviceCode)
    if err != nil { c.JSON(503, gin.H{"error": "设备授权安全存储未配置"}); return }
    expiry := grant.ExpiresIn
    if expiry > int(githubOAuthTTL.Seconds()) { expiry = int(githubOAuthTTL.Seconds()) }
    interval := grant.Interval
    if interval < 5 { interval = 5 }
    session := model.OAuthLoginSession{
        ID: sessionID, StateHash: oauthHash(state), PollHash: oauthHash(pollToken),
        Status: "device_pending", TargetUserID: target,
        DeviceCodeCiphertext: encrypted, DevicePollInterval: interval,
        ExpiresAt: time.Now().Add(time.Duration(expiry)*time.Second),
        RetryAfter: time.Now().Add(time.Duration(interval)*time.Second),
    }
    if err := h.DB.Create(&session).Error; err != nil {
        c.JSON(500, gin.H{"error": "设备授权会话保存失败"}); return
    }
    c.Header("Cache-Control", "no-store")
    c.JSON(http.StatusOK, gin.H{
        "session_id": sessionID, "poll_token": pollToken, "expires_in": expiry,
        "user_code": grant.UserCode, "verification_uri": grant.VerificationURI,
        "interval": interval,
    })
}

func (h *GitHubOAuthHandler) resumeDeviceIfDue(session model.OAuthLoginSession) {
    if !session.ExpiresAt.After(time.Now()) { return }
    var update = h.DB.Model(&model.OAuthLoginSession{})
    now := time.Now()
    switch session.Status {
    case "device_pending":
        update = update.Where("id = ? AND status = ? AND retry_after <= ?", session.ID, "device_pending", now)
    case "device_processing":
        if now.Sub(session.UpdatedAt) < 50*time.Second { return }
        update = update.Where("id = ? AND status = ? AND updated_at < ?", session.ID, "device_processing", now.Add(-50*time.Second))
    default:
        return
    }
    done := update.Updates(map[string]interface{}{"status": "device_processing", "error_stage": "device"})
    if done.Error == nil && done.RowsAffected == 1 {
        go h.pollGitHubDevice(session.ID)
    }
}

func (h *GitHubOAuthHandler) pollGitHubDevice(sessionID string) {
    started := time.Now()
    ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
    defer cancel()
    defer func() {
        if recover() != nil { h.oauthDeviceFailure(sessionID, "oauth_internal_error", started) }
    }()
    var session model.OAuthLoginSession
    if err := h.DB.First(&session, "id = ? AND status = ?", sessionID, "device_processing").Error; err != nil { return }
    code, err := secureconfig.Decrypt(session.DeviceCodeCiphertext)
    if err != nil || code == "" { h.oauthDeviceFailure(sessionID, "oauth_config_invalid", started); return }
    clientID, _, _, err := githubConfig()
    if err != nil { h.oauthDeviceFailure(sessionID, "oauth_config_invalid", started); return }
    body := url.Values{
        "client_id": {clientID}, "device_code": {code},
        "grant_type": {"urn:ietf:params:oauth:grant-type:device_code"},
    }
    req, err := http.NewRequestWithContext(ctx, http.MethodPost, h.TokenURL, strings.NewReader(body.Encode()))
    if err != nil { h.oauthDeviceFailure(sessionID, "oauth_config_invalid", started); return }
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    req.Header.Set("Accept", "application/json")
    resp, err := h.Client.Do(req)
    if err != nil { h.oauthDeviceDefer(session, session.DevicePollInterval, "github_unavailable"); return }
    defer resp.Body.Close()
    var result struct {
        AccessToken string `json:"access_token"`
        Error string `json:"error"`
        Interval int `json:"interval"`
    }
    if err := json.NewDecoder(io.LimitReader(resp.Body, 65536)).Decode(&result); err != nil {
        h.oauthDeviceDefer(session, session.DevicePollInterval, "github_unavailable"); return
    }
    switch result.Error {
    case "authorization_pending":
        h.oauthDeviceDefer(session, session.DevicePollInterval, ""); return
    case "slow_down":
        interval := session.DevicePollInterval+5
        if result.Interval > interval { interval = result.Interval }
        h.oauthDeviceDefer(session, interval, ""); return
    case "access_denied":
        h.oauthDeviceFailure(session.ID, "access_denied", started); return
    case "expired_token":
        h.oauthDeviceFailure(session.ID, "github_token_invalid", started); return
    case "":
        // 继续处理
    default:
        h.oauthDeviceFailure(session.ID, "oauth_config_invalid", started); return
    }
    if resp.StatusCode != 200 || result.AccessToken == "" {
        h.oauthDeviceDefer(session, session.DevicePollInterval, "github_unavailable"); return
    }
    encrypted, err := secureconfig.Encrypt(result.AccessToken)
    if err != nil { h.oauthDeviceFailure(session.ID, "oauth_config_invalid", started); return }
    stored := h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status = ? AND expires_at > ?", session.ID, "device_processing", time.Now()).
        Updates(map[string]interface{}{
            "status": "processing", "recovery_token": encrypted,
            "device_code_ciphertext": "", "error_stage": "profile",
        })
    if stored.Error != nil || stored.RowsAffected != 1 {
        h.oauthDeviceFailure(session.ID, "oauth_account_save_failed", started); return
    }
    h.finishGitHubIdentity(ctx, session, result.AccessToken, started)
}

func (h *GitHubOAuthHandler) oauthDeviceDefer(session model.OAuthLoginSession, interval int, code string) {
    if interval < 5 { interval = 5 }
    h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status = ?", session.ID, "device_processing").
        Updates(map[string]interface{}{
            "status": "device_pending",
            "device_poll_interval": interval,
            "retry_after": time.Now().Add(time.Duration(interval)*time.Second),
            "error_code": code,
        })
}

func (h *GitHubOAuthHandler) oauthDeviceFailure(id, code string, started time.Time) {
    h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status IN ?", id, []string{"device_processing", "device_pending"}).
        Updates(map[string]interface{}{
            "status": "failed", "error_code": code, "error_stage": "device",
            "device_code_ciphertext": "", "recovery_token": "",
        })
}
