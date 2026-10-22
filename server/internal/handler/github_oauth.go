package handler

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

const githubOAuthTTL = 10 * time.Minute

type githubOAuthError struct {
    Stage string
    Code string
}

func (e *githubOAuthError) Error() string { return e.Code }

func githubOAuthMessage(code string) string {
    switch code {
    case "access_denied": return "已取消 GitHub 授权，可重新发起登录"
    case "github_unavailable", "github_profile_unavailable": return "GitHub 服务暂时不可用，请稍后重新授权"
    case "oauth_config_invalid": return "GitHub 授权配置异常，请联系管理员"
    case "github_token_invalid": return "GitHub 授权码已失效，请重新授权"
    case "oauth_account_conflict": return "该 GitHub 账号已绑定其他用户"
    case "oauth_account_save_failed": return "账号信息保存失败，请稍后重新授权"
    default: return "GitHub 授权未完成，请重新发起登录"
    }
}

func githubOAuthHTTPStatus(code string) int {
    switch code {
    case "access_denied", "github_token_invalid": return http.StatusBadRequest
    case "oauth_account_conflict": return http.StatusConflict
    case "oauth_config_invalid", "github_unavailable", "github_profile_unavailable": return http.StatusServiceUnavailable
    default: return http.StatusInternalServerError
    }
}

type GitHubOAuthHandler struct {
	DB *gorm.DB
	Client *http.Client
	AuthURL string
	TokenURL string
	UserURL string
}

func NewGitHubOAuthHandler(db *gorm.DB) *GitHubOAuthHandler {
	return &GitHubOAuthHandler{
		DB: db, Client: &http.Client{Timeout: 30 * time.Second},
		AuthURL: "https://github.com/login/oauth/authorize",
		TokenURL: "https://github.com/login/oauth/access_token",
		UserURL: "https://api.github.com/user",
	}
}

func oauthRandom() (string, error) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil { return "", err }
	return base64.RawURLEncoding.EncodeToString(b[:]), nil
}

func oauthHash(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func githubConfig() (clientID, clientSecret, callback string, err error) {
	clientID = strings.TrimSpace(os.Getenv("GITHUB_OAUTH_CLIENT_ID"))
	clientSecret = os.Getenv("GITHUB_OAUTH_CLIENT_SECRET")
	callback = strings.TrimSpace(os.Getenv("GITHUB_OAUTH_CALLBACK_URL"))
	if clientID == "" || clientSecret == "" || callback == "" {
		err = errors.New("GitHub 登录尚未配置")
		return
	}
	u, parseErr := url.Parse(callback)
	if parseErr != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" ||
		(u.Scheme != "https" && !(u.Scheme == "http" && (u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1"))) {
		err = errors.New("GitHub OAuth 回调地址必须是 HTTPS（本机开发允许 HTTP loopback）")
	}
	return
}

// Start 启动登录，客户端保管 poll_token；浏览器只接触 GitHub 授权地址。
func (h *GitHubOAuthHandler) Start(c *gin.Context) { h.start(c, 0) }

// LinkStart 需 Slowlight JWT；显式绑定旧账号，禁止按邮箱静默合并。
func (h *GitHubOAuthHandler) LinkStart(c *gin.Context) { h.start(c, c.GetUint("userID")) }

func (h *GitHubOAuthHandler) start(c *gin.Context, targetUser uint) {
	// 平台仅影响授权成功后的返回方式；不会影响身份与凭据校验。
	var request struct {
		Platform string `json:"platform"`
	}
	if err := c.ShouldBindJSON(&request); err != nil ||
		(request.Platform != "" && request.Platform != "android" && request.Platform != "desktop") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "授权平台参数无效"})
		return
	}
	clientID, _, callback, err := githubConfig()
	if err != nil { c.JSON(http.StatusServiceUnavailable, gin.H{"error": err.Error()}); return }
	sessionID, err := oauthRandom()
	if err != nil { c.JSON(500, gin.H{"error": "初始化授权失败"}); return }
	state, err := oauthRandom()
	if err != nil { c.JSON(500, gin.H{"error": "初始化授权失败"}); return }
	// state 已由服务端生成且经数据库哈希校验。前缀仅选择回跳页面，
	// 不携带一次性令牌、JWT 或 GitHub 授权 code。
	if request.Platform == "android" {
		state = "android_" + state
	}
	poll, err := oauthRandom()
	if err != nil { c.JSON(500, gin.H{"error": "初始化授权失败"}); return }
	verifier, err := oauthRandom()
	if err != nil { c.JSON(500, gin.H{"error": "初始化授权失败"}); return }
	session := model.OAuthLoginSession{
		ID: sessionID, StateHash: oauthHash(state), PollHash: oauthHash(poll),
		CodeVerifier: verifier, Status: "pending", TargetUserID: targetUser,
		ExpiresAt: time.Now().Add(githubOAuthTTL),
	}
	// 清理过期会话，避免公开登录入口长期累积临时记录。
	if err := h.DB.Where("expires_at < ?", time.Now()).
		Delete(&model.OAuthLoginSession{}).Error; err != nil {
		c.JSON(500, gin.H{"error": "初始化授权失败"}); return
	}
	if err := h.DB.Create(&session).Error; err != nil {
		c.JSON(500, gin.H{"error": "初始化授权失败"}); return
	}
	challenge := sha256.Sum256([]byte(verifier))
	u, err := url.Parse(h.AuthURL)
	if err != nil { c.JSON(500, gin.H{"error": "授权地址无效"}); return }
	q := u.Query()
	q.Set("client_id", clientID)
	q.Set("redirect_uri", callback)
	q.Set("state", state)
	q.Set("code_challenge", base64.RawURLEncoding.EncodeToString(challenge[:]))
	q.Set("code_challenge_method", "S256")
	// 登录仅需 GitHub 的公开用户标识，不申请 repo / user:email 权限。
	u.RawQuery = q.Encode()
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{
		"authorization_url": u.String(), "session_id": sessionID,
		"poll_token": poll, "expires_in": int(githubOAuthTTL.Seconds()),
	})
}

type oauthPollRequest struct {
	SessionID string `json:"session_id" binding:"required"`
	PollToken string `json:"poll_token" binding:"required"`
}

// Poll 使用客户端持有的高熵凭据领取结果，成功后原子性标记 consumed。
func (h *GitHubOAuthHandler) Poll(c *gin.Context) {
	var req oauthPollRequest
	if err := c.ShouldBindJSON(&req); err != nil { c.JSON(400, gin.H{"error": "授权会话参数无效"}); return }
	var session model.OAuthLoginSession
	if err := h.DB.First(&session, "id = ?", req.SessionID).Error; err != nil {
		c.JSON(404, gin.H{"error": "授权会话不存在"}); return
	}
	expected, err := hex.DecodeString(session.PollHash)
	if err != nil { c.JSON(403, gin.H{"error": "授权验证失败"}); return }
	provided := sha256.Sum256([]byte(req.PollToken))
	if subtle.ConstantTimeCompare(expected, provided[:]) != 1 {
		c.JSON(403, gin.H{"error": "授权验证失败"}); return
	}
	if time.Now().After(session.ExpiresAt) {
		c.JSON(410, gin.H{"error": "授权已超时，请重试"}); return
	}
	switch session.Status {
	case "pending", "processing":
		c.Header("Cache-Control", "no-store")
		c.JSON(200, gin.H{"status": "pending"})
	case "failed":
        code := session.ErrorCode
        if code == "" { code = "oauth_unknown_failure" }
        c.JSON(githubOAuthHTTPStatus(code), gin.H{"code": code, "error": githubOAuthMessage(code), "stage": session.ErrorStage})
	case "ready":
		var user model.User
		if err := h.DB.First(&user, session.ResultUserID).Error; err != nil {
			c.JSON(500, gin.H{"error": "账号读取失败"}); return
		}
		token, err := generateTokenWithMethod(user.ID, "github")
		if err != nil { c.JSON(500, gin.H{"error": "签发登录凭据失败"}); return }
		updated := h.DB.Model(&model.OAuthLoginSession{}).
			Where("id = ? AND status = ? AND expires_at > ?", session.ID, "ready", time.Now()).
			Update("status", "consumed")
		if updated.Error != nil { c.JSON(500, gin.H{"error": "授权结果读取失败"}); return }
		if updated.RowsAffected != 1 { c.JSON(409, gin.H{"error": "授权结果已领取"}); return }
		c.Header("Cache-Control", "no-store")
		c.JSON(200, gin.H{"status": "complete", "token": token, "user": user})
	default:
		c.JSON(409, gin.H{"error": "授权结果已领取"})
	}
}

type githubProfile struct {
	ID int64 `json:"id"`
	Login string `json:"login"`
	Name string `json:"name"`
	AvatarURL string `json:"avatar_url"`
}

func (h *GitHubOAuthHandler) Callback(c *gin.Context) {
	state := c.Query("state")
	if state == "" { c.String(400, "授权状态无效"); return }
	var session model.OAuthLoginSession
	if err := h.DB.First(&session, "state_hash = ?", oauthHash(state)).Error; err != nil {
		c.String(400, "授权会话不存在"); return
	}
	if time.Now().After(session.ExpiresAt) {
		c.String(410, "授权已超时，请返回 Slowlight 重试"); return
	}
	updated := h.DB.Model(&model.OAuthLoginSession{}).
		Where("id = ? AND status = ? AND expires_at > ?", session.ID, "pending", time.Now()).
		Update("status", "processing")
	if updated.Error != nil || updated.RowsAffected != 1 {
		c.String(409, "授权已处理，请返回 Slowlight"); return
	}
    started := time.Now()
    fail := func(stage, code string) {
        update := h.DB.Model(&model.OAuthLoginSession{}).
            Where("id = ? AND status = ?", session.ID, "processing").
            Updates(map[string]interface{}{"status": "failed", "error_code": code, "error_stage": stage, "code_verifier": ""})
        log.Printf("github oauth failed session=%s stage=%s code=%s duration_ms=%d update_failed=%t",
            oauthHash(session.ID)[:12], stage, code, time.Since(started).Milliseconds(), update.Error != nil)
        c.Header("Cache-Control", "no-store")
        c.String(githubOAuthHTTPStatus(code), "%s", githubOAuthMessage(code))
    }
    if c.Query("error") != "" {
        code := "oauth_callback_invalid"
        if c.Query("error") == "access_denied" { code = "access_denied" }
        fail("callback", code)
        return
    }
    if c.Query("code") == "" { fail("callback", "oauth_callback_invalid"); return }
    clientID, secret, callback, err := githubConfig()
    if err != nil { fail("config", "oauth_config_invalid"); return }
    // 与浏览器连接断开解耦；后台处理时间有界，并继续更新会话状态。
    ctx, cancel := context.WithTimeout(context.WithoutCancel(c.Request.Context()), 80*time.Second)
    defer cancel()
    accessToken, err := h.exchangeToken(ctx, clientID, secret, callback, c.Query("code"), session.CodeVerifier)
    if err != nil {
        if oe, ok := err.(*githubOAuthError); ok { fail(oe.Stage, oe.Code) } else { fail("token", "github_unavailable") }
        return
    }
    profile, err := h.loadProfile(ctx, accessToken)
    if err != nil {
        if oe, ok := err.(*githubOAuthError); ok { fail(oe.Stage, oe.Code) } else { fail("profile", "github_profile_unavailable") }
        return
    }
    user, err := h.resolveUser(profile, session.TargetUserID)
    if err != nil {
        if err.Error() == "GitHub 账号已绑定其他用户" || err.Error() == "当前账号已有 GitHub 绑定" {
            fail("account", "oauth_account_conflict")
        } else { fail("account", "oauth_account_save_failed") }
        return
    }
    if err := h.DB.Model(&model.OAuthLoginSession{}).
        Where("id = ? AND status = ?", session.ID, "processing").
        Updates(map[string]interface{}{"status": "ready", "result_user_id": user.ID, "code_verifier": ""}).Error; err != nil {
        fail("session", "oauth_account_save_failed"); return
    }
    log.Printf("github oauth ready session=%s duration_ms=%d", oauthHash(session.ID)[:12], time.Since(started).Milliseconds())
	c.Header("Cache-Control", "no-store")
	c.Header("Referrer-Policy", "no-referrer")
	c.Header("X-Content-Type-Options", "nosniff")
	if strings.HasPrefix(state, "android_") {
		// Android 使用无敏感信息的私有 URI 唤醒已有 Slowlight 实例。
		// 浏览器可能禁止无手势跳转，保留显式返回按钮。
		c.Header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'")
		c.Data(200, "text/html; charset=utf-8", []byte(androidOAuthReturnHTML))
		return
	}
	c.Header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
	c.Data(200, "text/html; charset=utf-8", []byte(desktopOAuthReturnHTML))
}

const desktopOAuthReturnHTML = `<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Slowlight 登录成功</title><body style="font:16px system-ui,sans-serif;background:#0b1220;color:#fff;text-align:center;padding:12vh 1rem"><h1>GitHub 授权已完成</h1><p>请返回所行映我，等待 Windows 客户端确认登录。</p><p style="opacity:.7">如果客户端仍在等待，请点击「检查授权结果」。完成客户端验证前，这里不代表已经登录。</p></body></html>`

const androidOAuthReturnHTML = `<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Slowlight 登录成功</title><body style="font:16px system-ui,sans-serif;background:#0b1220;color:#fff;text-align:center;padding:12vh 1rem"><h1>授权成功</h1><p>正在返回所行映我…</p><p><a href="slowlight://oauth-complete" style="display:inline-block;background:#437bff;color:white;padding:14px 24px;border-radius:10px;text-decoration:none">返回所行映我</a></p><p style="opacity:.7">如果没有自动返回，请点击按钮。</p><script>window.location.replace("slowlight://oauth-complete");</script></body></html>`

func (h *GitHubOAuthHandler) exchangeToken(ctx context.Context, id, secret, redirect, code, verifier string) (string, error) {
	body := url.Values{"client_id": {id}, "client_secret": {secret}, "code": {code}, "redirect_uri": {redirect}, "code_verifier": {verifier}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, h.TokenURL, strings.NewReader(body.Encode()))
	if err != nil { return "", err }
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := h.Client.Do(req)
	if err != nil { return "", err }
	defer resp.Body.Close()
	if resp.StatusCode != 200 { return "", errors.New("GitHub token 交换失败") }
	var payload struct { AccessToken string `json:"access_token"` }
	if err := json.NewDecoder(io.LimitReader(resp.Body, 65536)).Decode(&payload); err != nil { return "", err }
	if payload.AccessToken == "" { return "", errors.New("GitHub 未返回访问令牌") }
	return payload.AccessToken, nil
}

func (h *GitHubOAuthHandler) loadProfile(ctx context.Context, accessToken string) (githubProfile, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, h.UserURL, nil)
	if err != nil { return githubProfile{}, err }
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "Slowlight")
	resp, err := h.Client.Do(req)
	if err != nil { return githubProfile{}, err }
	defer resp.Body.Close()
	if resp.StatusCode != 200 { return githubProfile{}, errors.New("GitHub 用户信息获取失败") }
	var p githubProfile
	if err := json.NewDecoder(io.LimitReader(resp.Body, 65536)).Decode(&p); err != nil { return p, err }
	if p.ID <= 0 || strings.TrimSpace(p.Login) == "" { return p, errors.New("GitHub 用户标识无效") }
	return p, nil
}

func (h *GitHubOAuthHandler) resolveUser(p githubProfile, target uint) (model.User, error) {
	var result model.User
	subject := strconv.FormatInt(p.ID, 10)
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		var identity model.OAuthIdentity
		err := tx.Where("provider = ? AND provider_user_id = ?", "github", subject).First(&identity).Error
		if err == nil {
			if target != 0 && identity.UserID != target { return errors.New("GitHub 账号已绑定其他用户") }
			return tx.First(&result, identity.UserID).Error
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) { return err }
		if target != 0 {
			var count int64
			if err := tx.Model(&model.OAuthIdentity{}).Where("provider = ? AND user_id = ?", "github", target).Count(&count).Error; err != nil { return err }
			if count > 0 { return errors.New("当前账号已有 GitHub 绑定") }
			if err := tx.First(&result, target).Error; err != nil { return err }
		} else {
			randomPassword, err := oauthRandom()
			if err != nil { return err }
			hashed, err := bcrypt.GenerateFromPassword([]byte(randomPassword), bcrypt.DefaultCost)
			if err != nil { return err }
			username := "github_" + subject
			var existing int64
			if err := tx.Model(&model.User{}).Where("username = ?", username).Count(&existing).Error; err != nil { return err }
			if existing != 0 {
				suffix, err := oauthRandom()
				if err != nil { return err }
				username += "_" + suffix[:8]
			}
			nickname := []rune(strings.TrimSpace(p.Name))
			if len(nickname) == 0 { nickname = []rune(p.Login) }
			if len(nickname) > 50 { nickname = nickname[:50] }
			passwordEnabled := false
			result = model.User{
				PasswordLoginEnabled: &passwordEnabled,
				Username: username,
				Email: "gh-" + subject + "@oauth.slowlight.invalid",
				Password: string(hashed),
				Nickname: string(nickname),
				Avatar: p.AvatarURL,
			}
			if err := tx.Create(&result).Error; err != nil { return err }
			if err := createDefaultAccountData(tx, result.ID); err != nil { return err }
		}
		return tx.Create(&model.OAuthIdentity{UserID: result.ID, Provider: "github", ProviderUserID: subject}).Error
	})
	return result, err
}

// GitHub 注册复用传统注册的默认账户数据；保持现有列表和观察标签一致。
func createDefaultAccountData(tx *gorm.DB, id uint) error {
	lists := []model.List{
		{UserID: id, Name: "收集箱", Icon: "📥", Color: "#909399", SortOrder: -1, IsInbox: true},
		{UserID: id, Name: "工作", Icon: "💼", Color: "#1890ff", SortOrder: 1},
		{UserID: id, Name: "生活", Icon: "🏠", Color: "#52c41a", SortOrder: 2},
		{UserID: id, Name: "学习", Icon: "📚", Color: "#722ed1", SortOrder: 3},
	}
	if err := tx.Create(&lists).Error; err != nil { return err }
	tags := []model.SystemTag{
		{UserID: id, Name: "身体", Icon: "💪", Color: "#52c41a", DimensionKey: model.DimensionBody, SortOrder: 1, IsDefault: true},
		{UserID: id, Name: "认知", Icon: "🧠", Color: "#1890ff", DimensionKey: model.DimensionCognition, SortOrder: 2, IsDefault: true},
		{UserID: id, Name: "产出", Icon: "🎯", Color: "#722ed1", DimensionKey: model.DimensionOutput, SortOrder: 3, IsDefault: true},
		{UserID: id, Name: "关系", Icon: "❤️", Color: "#eb2f96", DimensionKey: model.DimensionRelationship, SortOrder: 4, IsDefault: true},
	}
	if err := tx.Create(&tags).Error; err != nil { return fmt.Errorf("初始化默认观察标签失败: %w", err) }
	return nil
}
