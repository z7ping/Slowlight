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
    // 空模式保留旧版一次性领取；reliable 模式需显式 ack。
    Mode string `json:"mode"`
}

// Poll 使用客户端持有的高熵凭据领取结果，成功后原子性标记 consumed。
func (h *GitHubOAuthHandler) Poll(c *gin.Context) {
	var req oauthPollRequest
	if err := c.ShouldBindJSON(&req); err != nil { c.JSON(400, gin.H{"error": "授权会话参数无效"}); return }
    if req.Mode != "" && req.Mode != "reliable" && req.Mode != "ack" { c.JSON(400, gin.H{"error": "授权会话模式无效"}); return }
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
    if req.Mode == "ack" {
        if session.Status == "consumed" {
            c.Header("Cache-Control", "no-store")
            c.JSON(200, gin.H{"status": "acknowledged"})
            return
        }
        if session.Status != "ready" {
            c.JSON(409, gin.H{"error": "授权结果尚不可确认"})
            return
        }
        updated := h.DB.Model(&model.OAuthLoginSession{}).
            Where("id = ? AND status = ? AND expires_at > ?", session.ID, "ready", time.Now()).
            Update("status", "consumed")
        if updated.Error != nil { c.JSON(500, gin.H{"error": "确认授权结果失败"}); return }
        if updated.RowsAffected != 1 {
            var latest model.OAuthLoginSession
            if err := h.DB.First(&latest, "id = ?", session.ID).Error; err != nil || latest.Status != "consumed" {
                c.JSON(409, gin.H{"error": "授权状态已变化"}); return
            }
        }
        c.Header("Cache-Control", "no-store")
        c.JSON(200, gin.H{"status": "acknowledged"})
        return
    }
	switch session.Status {
    case "pending":
        c.Header("Cache-Control", "no-store")
        c.JSON(200, gin.H{"status": "pending", "phase": "authorization"})
    case "processing", "retryable":
        h.resumeIfRequired(session)
        phase := session.ErrorStage
        if phase == "" { phase = "processing" }
        c.Header("Cache-Control", "no-store")
        c.JSON(200, gin.H{"status": "pending", "phase": phase})
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
        if req.Mode != "reliable" {
            // 旧客户端不传 mode，保持现有的一次性凭据领取行为。
            updated := h.DB.Model(&model.OAuthLoginSession{}).
                Where("id = ? AND status = ? AND expires_at > ?", session.ID, "ready", time.Now()).
                Update("status", "consumed")
            if updated.Error != nil { c.JSON(500, gin.H{"error": "授权结果读取失败"}); return }
            if updated.RowsAffected != 1 { c.JSON(409, gin.H{"error": "授权结果已领取"}); return }
        }
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
    if state == "" { c.String(http.StatusBadRequest, "授权状态无效"); return }
    var session model.OAuthLoginSession
    if err := h.DB.First(&session, "state_hash = ?", oauthHash(state)).Error; err != nil {
        c.String(http.StatusNotFound, "授权会话不存在"); return
    }
    if time.Now().After(session.ExpiresAt) {
        c.String(http.StatusGone, "授权已超时，请返回 Slowlight 重试"); return
    }
    if session.Status == "pending" {
        updated := h.DB.Model(&model.OAuthLoginSession{}).
            Where("id = ? AND status = ? AND expires_at > ?", session.ID, "pending", time.Now()).
            Updates(map[string]interface{}{"status": "processing", "error_stage": "callback"})
        if updated.Error != nil {
            c.String(http.StatusInternalServerError, "授权会话状态更新失败"); return
        }
        if updated.RowsAffected == 1 {
            if c.Query("error") != "" || c.Query("code") == "" {
                code := "oauth_callback_invalid"
                if c.Query("error") == "access_denied" { code = "access_denied" }
                h.oauthFailed(session.ID, "callback", code, time.Now())
                c.Header("Cache-Control", "no-store")
                c.String(githubOAuthHTTPStatus(code), "%s", githubOAuthMessage(code))
                return
            }
            go h.processOAuthCallback(session, c.Query("code"))
        } else {
            // 两次浏览器回调并发，后一条只展示处理状态，绝不重复兑换授权码。
            if err := h.DB.First(&session, "id = ?", session.ID).Error; err != nil {
                c.String(http.StatusConflict, "授权状态未确认"); return
            }
        }
    }
    if session.Status == "failed" {
        c.Header("Cache-Control", "no-store")
        c.String(githubOAuthHTTPStatus(session.ErrorCode), "%s", githubOAuthMessage(session.ErrorCode))
        return
    }
    // 浏览器无需等待 GitHub /token、/user、数据库操作，规避代理回调超时。
    c.Header("Cache-Control", "no-store")
    c.Header("Referrer-Policy", "no-referrer")
    c.Header("X-Content-Type-Options", "nosniff")
    if strings.HasPrefix(state, "android_") {
        c.Header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'")
        c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(androidOAuthReturnHTML))
        return
    }
    c.Header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
    c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(desktopOAuthReturnHTML))
}

const desktopOAuthReturnHTML = `<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Slowlight 登录成功</title><body style="font:16px system-ui,sans-serif;background:#0b1220;color:#fff;text-align:center;padding:12vh 1rem"><h1>GitHub 授权请求已接收</h1><p>请返回所行映我，等待 Windows 客户端确认登录。</p><p style="opacity:.7">如果客户端仍在等待，请点击「检查授权结果」。完成客户端验证前，这里不代表已经登录。</p></body></html>`

const androidOAuthReturnHTML = `<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Slowlight 登录成功</title><body style="font:16px system-ui,sans-serif;background:#0b1220;color:#fff;text-align:center;padding:12vh 1rem"><h1>正在验证 GitHub 身份</h1><p>请返回所行映我，应用将继续检查登录结果。</p><p><a href="slowlight://oauth-complete" style="display:inline-block;background:#437bff;color:white;padding:14px 24px;border-radius:10px;text-decoration:none">返回所行映我</a></p><p style="opacity:.7">如果没有自动返回，请点击按钮。</p><script>window.location.replace("slowlight://oauth-complete");</script></body></html>`

func (h *GitHubOAuthHandler) exchangeToken(ctx context.Context, id, secret, redirect, code, verifier string) (string, error) {
    body := url.Values{"client_id": {id}, "client_secret": {secret}, "code": {code}, "redirect_uri": {redirect}, "code_verifier": {verifier}}
    req, err := http.NewRequestWithContext(ctx, http.MethodPost, h.TokenURL, strings.NewReader(body.Encode()))
    if err != nil { return "", &githubOAuthError{Stage: "token", Code: "oauth_config_invalid"} }
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    req.Header.Set("Accept", "application/json")
    // 授权码一次性使用；请求可能已经送达时，不自动重发。
    resp, err := h.Client.Do(req)
    if err != nil { return "", &githubOAuthError{Stage: "token", Code: "github_unavailable"} }
    defer resp.Body.Close()
    if resp.StatusCode != http.StatusOK {
        if resp.StatusCode == 429 || resp.StatusCode >= 500 {
            return "", &githubOAuthError{Stage: "token", Code: "github_unavailable"}
        }
        return "", &githubOAuthError{Stage: "token", Code: "oauth_config_invalid"}
    }
    var payload struct {
        AccessToken string `json:"access_token"`
        Error string `json:"error"`
    }
    if err := json.NewDecoder(io.LimitReader(resp.Body, 65536)).Decode(&payload); err != nil {
        return "", &githubOAuthError{Stage: "token", Code: "github_unavailable"}
    }
    if payload.Error != "" {
        switch payload.Error {
        case "bad_verification_code": return "", &githubOAuthError{Stage: "token", Code: "github_token_invalid"}
        case "incorrect_client_credentials", "redirect_uri_mismatch", "unsupported_grant_type":
            return "", &githubOAuthError{Stage: "token", Code: "oauth_config_invalid"}
        default: return "", &githubOAuthError{Stage: "token", Code: "github_unavailable"}
        }
    }
    if payload.AccessToken == "" { return "", &githubOAuthError{Stage: "token", Code: "github_unavailable"} }
    return payload.AccessToken, nil
}

// GitHub /user GET 幂等，临时错误允许有限次数的指数退避。
func (h *GitHubOAuthHandler) loadProfile(ctx context.Context, accessToken string) (githubProfile, error) {
    for attempt := 0; attempt < 3; attempt++ {
        if ctx.Err() != nil { break }
        if attempt > 0 {
            pause := time.Duration(1 << (attempt - 1)) * time.Second
            select {
            case <-time.After(pause):
            case <-ctx.Done():
                return githubProfile{}, &githubOAuthError{Stage: "profile", Code: "github_profile_unavailable"}
            }
        }
        req, err := http.NewRequestWithContext(ctx, http.MethodGet, h.UserURL, nil)
        if err != nil { return githubProfile{}, &githubOAuthError{Stage: "profile", Code: "oauth_config_invalid"} }
        req.Header.Set("Authorization", "Bearer "+accessToken)
        req.Header.Set("Accept", "application/vnd.github+json")
        req.Header.Set("User-Agent", "Slowlight")
        resp, err := h.Client.Do(req)
        if err != nil { continue }
        if resp.StatusCode == http.StatusOK {
            var profile githubProfile
            decodeErr := json.NewDecoder(io.LimitReader(resp.Body, 65536)).Decode(&profile)
            resp.Body.Close()
            if decodeErr == nil && profile.ID > 0 && strings.TrimSpace(profile.Login) != "" { return profile, nil }
            return githubProfile{}, &githubOAuthError{Stage: "profile", Code: "github_profile_unavailable"}
        }
        retryable := resp.StatusCode == 429 || resp.StatusCode >= 500
        resp.Body.Close()
        if !retryable { return githubProfile{}, &githubOAuthError{Stage: "profile", Code: "github_profile_unavailable"} }
    }
    return githubProfile{}, &githubOAuthError{Stage: "profile", Code: "github_profile_unavailable"}
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
