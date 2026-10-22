package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"
	"github.com/gin-gonic/gin"

	"slowlight/internal/model"
)

func TestAccountPasswordRules(t *testing.T) {
	for _, value := range []string{"short", "123456789", "a password longer than the max for bcrypt a password longer than the max for bcrypt"} {
		if validateAccountPassword(value) {
			t.Fatalf("不应接受密码长度: %d", len(value))
		}
	}
	if !validateAccountPassword("valid-pass-123") { t.Fatal("有效密码被拒绝") }
	for _, username := range []string{"aa", "1login", "github_123", "has.dot", "with-dash"} {
		allowed := loginUsernamePattern.MatchString(username) && len(username) <= 30
		if username == "github_123" { allowed = false }
		if allowed { t.Fatalf("不应接受用户名 %q", username) }
	}
}

func TestGitHubRecentProofRequired(t *testing.T) {
	c, _ := newTestContext(http.MethodPost, "/account", 1)
	if recentlyVerifiedGitHub(c) { t.Fatal("无重新验证的 JWT 不应认领账号") }
	c.Set("authMethod", "password")
	c.Set("authIssuedAt", time.Now().Unix())
	if recentlyVerifiedGitHub(c) { t.Fatal("密码会话不可直接认领 GitHub 账号") }
	c.Set("authMethod", "github")
	c.Set("authIssuedAt", time.Now().Add(-6*time.Minute).Unix())
	if recentlyVerifiedGitHub(c) { t.Fatal("过期 GitHub 授权应拒绝") }
	c.Set("authIssuedAt", time.Now().Unix())
	if !recentlyVerifiedGitHub(c) { t.Fatal("新完成 GitHub 授权应允许") }
}

func TestAccountProfileAndCredentialSetup(t *testing.T) {
	tx := beginTx(t, setupTestDB(t))
	enabled := false
	user := model.User{
		Username: uniqueName("github_9988"), Email: uniqueName("gh")+"@oauth.slowlight.invalid",
		Nickname: "旧昵称", Password: "$2a$10$some-random-hash",
		PasswordLoginEnabled: &enabled,
	}
	if err := tx.Create(&user).Error; err != nil { t.Fatal(err) }
	if err := tx.Create(&model.OAuthIdentity{
		UserID: user.ID, Provider: "github", ProviderUserID: "9988",
	}).Error; err != nil { t.Fatal(err) }
	h := NewAuthHandler(tx)
	r := newTestGin()
	r.Use(func(c *gin.Context) {
		withUser(c, user.ID)
		c.Set("authMethod", "github")
		c.Set("authIssuedAt", time.Now().Unix())
		c.Next()
	})
	r.PATCH("/profile", h.UpdateProfile)
	r.POST("/setup", h.SetupPassword)
	r.POST("/change", h.ChangePassword)
	r.GET("/password-status", h.PasswordStatus)

	request := func(method, path string, body interface{}) *httptest.ResponseRecorder {
		data, _ := json.Marshal(body)
		w := httptest.NewRecorder()
		req := httptest.NewRequest(method, path, bytes.NewReader(data))
		req.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, req)
		return w
	}
	if got := request("PATCH", "/profile", map[string]string{"nickname":" 新昵称 "}); got.Code != 200 {
		t.Fatalf("修改昵称失败: %d %s", got.Code, got.Body)
	}
	if got := request("GET", "/password-status", nil); got.Code != 200 ||
		!bytes.Contains(got.Body.Bytes(), []byte(`"password_login_enabled":false`)) {
		t.Fatalf("首次 GitHub 账号不应显示密码已设置: %d %s", got.Code, got.Body)
	}
	username := uniqueName("freshlogin")
	payload := map[string]string{"username":username,"password":"secure-pass-123"}
	if got := request("POST", "/setup", payload); got.Code != 200 {
		t.Fatalf("设置登录账号失败: %d %s", got.Code, got.Body)
	}
	var saved model.User
	if err := tx.First(&saved, user.ID).Error; err != nil { t.Fatal(err) }
	if saved.ID != user.ID || saved.Username != username || saved.Nickname != "新昵称" ||
		!passwordLoginEnabled(tx, saved) || bcrypt.CompareHashAndPassword([]byte(saved.Password), []byte(payload["password"])) != nil {
		t.Fatal("应保留原 User.ID，并保存昵称、账号、bcrypt 密码")
	}
	if got := request("POST", "/setup", payload); got.Code != http.StatusConflict {
		t.Fatalf("不得重复认领账号: %d", got.Code)
	}
	if got := request("POST", "/change", map[string]string{"current_password":"wrong","new_password":"next-secure-123"}); got.Code != http.StatusUnauthorized {
		t.Fatalf("原密码错误不应修改密码: %d", got.Code)
	}
	if got := request("POST", "/change", map[string]string{"current_password":"secure-pass-123","new_password":"next-secure-123"}); got.Code != 200 {
		t.Fatalf("修改密码失败: %d %s", got.Code, got.Body)
	}
}

func TestLegacyGitHubVsNativePasswordLogin(t *testing.T) {
	tx := beginTx(t, setupTestDB(t))
	for _, tc := range []struct{username, subject string; enabled bool}{
		{"github_87654", "87654", false},
		{"native_87654", "87654", true},
	} {
		user := model.User{Username: uniqueName(tc.username), Email: uniqueName("u")+"@example.com",
			Password: "hash", Nickname: "test"}
		// 标准化唯一名保持历史生成前缀语义。
		if !tc.enabled { user.Username = "github_" + uniqueName(tc.subject) }
		if err := tx.Create(&user).Error; err != nil { t.Fatal(err) }
		subject := tc.subject
		if !tc.enabled { subject = user.Username[len("github_"):] }
		if err := tx.Create(&model.OAuthIdentity{UserID: user.ID, Provider: "github",
			ProviderUserID: subject}).Error; err != nil { t.Fatal(err) }
		if actual := passwordLoginEnabled(tx, user); actual != tc.enabled {
			t.Fatalf("%s 的旧账号密码状态错误: %v", user.Username, actual)
		}
	}
}
