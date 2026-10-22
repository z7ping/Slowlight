package handler

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"testing"

	"slowlight/internal/model"
	"github.com/gin-gonic/gin"
)

func TestGitHubOAuthConfiguration(t *testing.T) {
	t.Setenv("GITHUB_OAUTH_CLIENT_ID", "test-client")
	t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "test-secret")
	t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "http://evil.example/api/auth/github/callback")
	if _, _, _, err := githubConfig(); err == nil {
		t.Fatal("不允许明文公网回调地址")
	}
	t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "https://example.org/api/auth/github/callback")
	if _, _, _, err := githubConfig(); err != nil {
		t.Fatalf("HTTPS 回调应可用: %v", err)
	}
	t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "")
	if _, _, _, err := githubConfig(); err == nil {
		t.Fatal("缺失 Secret 必须拒绝启动 OAuth")
	}
}

func testOAuthRequest(t *testing.T, router http.Handler, route string, body map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	encoded, err := json.Marshal(body)
	if err != nil { t.Fatal(err) }
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, route, bytes.NewReader(encoded))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)
	return w
}

func parseOAuthBody(t *testing.T, w *httptest.ResponseRecorder) map[string]interface{} {
	t.Helper()
	var result map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("响应不是 JSON: %v: %s", err, w.Body.String())
	}
	return result
}

func TestGitHubOAuthLoginEndToEnd(t *testing.T) {
	db := beginTx(t, setupTestDB(t))
	t.Setenv("JWT_SECRET", "a-long-test-jwt-signing-secret")
	t.Setenv("GITHUB_OAUTH_CLIENT_ID", "test-client")
	t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "test-secret")
	t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "https://example.org/api/auth/github/callback")

	var verifier string
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/token":
			if r.Method != http.MethodPost { t.Error("token 方法错误") }
			r.ParseForm()
			verifier = r.Form.Get("code_verifier")
			if verifier == "" || r.Form.Get("code") != "test-code" || r.Form.Get("client_secret") != "test-secret" {
				t.Error("token 交换参数缺失")
			}
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `{"access_token":"fake-access-token"}`)
		case "/user":
			if r.Header.Get("Authorization") != "Bearer fake-access-token" { t.Error("未正确携带 GitHub Token") }
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `{"id":99887766,"login":"fakegithub","name":"Test GitHub User"}`)
		default:
			http.NotFound(w, r)
		}
	}))
	defer mock.Close()

	h := NewGitHubOAuthHandler(db)
	h.TokenURL, h.UserURL = mock.URL+"/token", mock.URL+"/user"
	r := newTestGin()
	r.POST("/start", h.Start)
	r.GET("/callback", h.Callback)
	r.POST("/poll", h.Poll)

	start := testOAuthRequest(t, r, "/start", map[string]string{})
	if start.Code != 200 { t.Fatalf("OAuth start: %d: %s", start.Code, start.Body.String()) }
	login := parseOAuthBody(t, start)
	authURL, err := url.Parse(login["authorization_url"].(string))
	if err != nil { t.Fatal(err) }
	if authURL.Host != "github.com" || authURL.Query().Get("scope") != "" {
		t.Fatalf("登录只允许 github.com 公开身份权限: %s", authURL)
	}
	if authURL.Query().Get("code_challenge_method") != "S256" { t.Fatal("缺少 PKCE") }
	if start.Header().Get("Cache-Control") != "no-store" { t.Fatal("授权凭据不应缓存") }

	poll := map[string]string{
		"session_id": login["session_id"].(string),
		"poll_token": login["poll_token"].(string),
	}
	wrong := map[string]string{"session_id": poll["session_id"], "poll_token": "incorrect"}
	if w := testOAuthRequest(t, r, "/poll", wrong); w.Code != 403 {
		t.Fatalf("错误 poll secret 不应领取凭据: %d", w.Code)
	}
	if pending := parseOAuthBody(t, testOAuthRequest(t, r, "/poll", poll)); pending["status"] != "pending" {
		t.Fatalf("尚未授权应为 pending: %v", pending)
	}

	callbackPath := "/callback?state="+url.QueryEscape(authURL.Query().Get("state"))+"&code=test-code"
	cb := httptest.NewRecorder()
	r.ServeHTTP(cb, httptest.NewRequest(http.MethodGet, callbackPath, nil))
	if cb.Code != 200 { t.Fatalf("回调失败: %d %s", cb.Code, cb.Body.String()) }
	challenge := sha256.Sum256([]byte(verifier))
	if base64.RawURLEncoding.EncodeToString(challenge[:]) != authURL.Query().Get("code_challenge") {
		t.Fatal("PKCE verifier 与 challenge 不匹配")
	}

    // reliable 模式允许响应丢失后再次读取，且不会提前消费授权结果。
    reliable := map[string]string{
        "session_id": poll["session_id"],
        "poll_token": poll["poll_token"],
        "mode": "reliable",
    }
    for i := 0; i < 2; i++ {
        received := testOAuthRequest(t, r, "/poll", reliable)
        if received.Code != 200 { t.Fatalf("reliable poll %d: %d %s", i, received.Code, received.Body.String()) }
        result := parseOAuthBody(t, received)
        if result["status"] != "complete" || result["token"] == "" {
            t.Fatalf("可靠轮询未发放 JWT: %v", result)
        }
    }
	readyResponse := testOAuthRequest(t, r, "/poll", poll)
	if readyResponse.Code != 200 { t.Fatalf("未能领取 JWT: %d %s", readyResponse.Code, readyResponse.Body.String()) }
	ready := parseOAuthBody(t, readyResponse)
	if ready["status"] != "complete" || ready["token"] == "" { t.Fatalf("凭据响应无效: %v", ready) }
	user := ready["user"].(map[string]interface{})
	id := uint(user["id"].(float64))
	if user["username"] != "github_99887766" { t.Fatalf("账号标识不稳定: %v", user) }
	var identity model.OAuthIdentity
	if err := db.Where("provider = ? AND provider_user_id = ?", "github", "99887766").First(&identity).Error; err != nil {
		t.Fatalf("身份未建立: %v", err)
	}
	if identity.UserID != id { t.Fatal("外部身份与内部用户不一致") }
	var listCount int64
	db.Model(&model.List{}).Where("user_id = ?", id).Count(&listCount)
	if listCount != 4 { t.Fatalf("默认清单应初始化 4 个: %d", listCount) }
	var tagCount int64
	db.Model(&model.SystemTag{}).Where("user_id = ?", id).Count(&tagCount)
	if tagCount != 4 { t.Fatalf("默认标签应初始化 4 个: %d", tagCount) }
	if replay := testOAuthRequest(t, r, "/poll", poll); replay.Code != 409 { t.Fatalf("授权结果不能重复领取: %d", replay.Code) }
    // 旧客户端领取完成后，幂等 ack 不得重开授权结果。
    ack := map[string]string{
        "session_id": poll["session_id"],
        "poll_token": poll["poll_token"],
        "mode": "ack",
    }
    if confirmed := testOAuthRequest(t, r, "/poll", ack); confirmed.Code != 200 {
        t.Fatalf("consumed ack must be idempotent: %d", confirmed.Code)
    }

    // 新会话仅使用 reliable + ack：确认之前可重读，确认之后不可领取。
    nextStart := parseOAuthBody(t, testOAuthRequest(t, r, "/start", map[string]string{}))
    nextURL, err := url.Parse(nextStart["authorization_url"].(string))
    if err != nil { t.Fatal(err) }
    nextCallback := httptest.NewRecorder()
    r.ServeHTTP(nextCallback, httptest.NewRequest(http.MethodGet,
        "/callback?state="+url.QueryEscape(nextURL.Query().Get("state"))+"&code=test-code", nil))
    if nextCallback.Code != 200 { t.Fatalf("second callback: %d %s", nextCallback.Code, nextCallback.Body.String()) }
    nextPoll := map[string]string{
        "session_id": nextStart["session_id"].(string),
        "poll_token": nextStart["poll_token"].(string),
        "mode": "reliable",
    }
    if received := testOAuthRequest(t, r, "/poll", nextPoll); received.Code != 200 {
        t.Fatalf("reliable next poll: %d", received.Code)
    }
    nextPoll["mode"] = "ack"
    for i := 0; i < 2; i++ {
        if confirmed := testOAuthRequest(t, r, "/poll", nextPoll); confirmed.Code != 200 {
            t.Fatalf("idempotent ack attempt %d: %d", i, confirmed.Code)
        }
    }
    nextPoll["mode"] = "reliable"
    if replay := testOAuthRequest(t, r, "/poll", nextPoll); replay.Code != 409 {
        t.Fatalf("reliable poll after ack must be rejected: %d", replay.Code)
    }

	cb2 := httptest.NewRecorder()
	r.ServeHTTP(cb2, httptest.NewRequest(http.MethodGet, callbackPath, nil))
	if cb2.Code != 409 { t.Fatalf("回调不能重复处理: %d", cb2.Code) }
}

func TestGitHubOAuthExplicitAccountLink(t *testing.T) {
	db := beginTx(t, setupTestDB(t))
	old := createTestUser(t, db)
	t.Setenv("JWT_SECRET", "long-test-signing-secret")
	t.Setenv("GITHUB_OAUTH_CLIENT_ID", "test-client")
	t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "test-secret")
	t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "https://example.org/api/auth/github/callback")
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if strings.HasSuffix(r.URL.Path, "/token") {
			io.WriteString(w, `{"access_token":"test-token"}`)
		} else {
			io.WriteString(w, `{"id":66554433,"login":"linkeduser"}`)
		}
	}))
	defer mock.Close()
	h := NewGitHubOAuthHandler(db)
	h.TokenURL, h.UserURL = mock.URL+"/token", mock.URL+"/user"
	r := newTestGin()
	r.POST("/link/start", func(c *gin.Context) { withUser(c, old.ID); h.LinkStart(c) })
	r.GET("/callback", h.Callback)
	r.POST("/poll", h.Poll)
	start := parseOAuthBody(t, testOAuthRequest(t, r, "/link/start", map[string]string{}))
	u, _ := url.Parse(start["authorization_url"].(string))
	callback := httptest.NewRecorder()
	r.ServeHTTP(callback, httptest.NewRequest(http.MethodGet, "/callback?state="+url.QueryEscape(u.Query().Get("state"))+"&code=ok", nil))
	if callback.Code != 200 { t.Fatalf("绑定回调失败: %d", callback.Code) }
	result := parseOAuthBody(t, testOAuthRequest(t, r, "/poll", map[string]string{
		"session_id": start["session_id"].(string),
		"poll_token": start["poll_token"].(string),
	}))
	if result["user"].(map[string]interface{})["id"] != float64(old.ID) { t.Fatal("绑定不得新建账号") }
	var count int64
	db.Model(&model.User{}).Where("username = ?", "github_"+strconv.FormatInt(66554433, 10)).Count(&count)
	if count != 0 { t.Fatal("绑定不能创建额外 Slowlight 用户") }
}


func TestGitHubOAuthAndroidReturnDoesNotLeakCredentials(t *testing.T) {
	db := beginTx(t, setupTestDB(t))
	t.Setenv("GITHUB_OAUTH_CLIENT_ID", "test-client")
	t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "test-secret")
	t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "https://example.org/api/auth/github/callback")
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if strings.HasSuffix(r.URL.Path, "/token") {
			io.WriteString(w, `{"access_token":"sensitive-token"}`)
		} else {
			io.WriteString(w, `{"id":77665544,"login":"mobileuser"}`)
		}
	}))
	defer mock.Close()

	h := NewGitHubOAuthHandler(db)
	h.TokenURL, h.UserURL = mock.URL+"/token", mock.URL+"/user"
	r := newTestGin()
	r.POST("/start", h.Start)
	r.GET("/callback", h.Callback)

	bad := testOAuthRequest(t, r, "/start", map[string]string{"platform": "unknown"})
	if bad.Code != http.StatusBadRequest {
		t.Fatalf("未知平台应拒绝: %d", bad.Code)
	}

	start := testOAuthRequest(t, r, "/start", map[string]string{"platform": "android"})
	if start.Code != http.StatusOK { t.Fatalf("Android start %d: %s", start.Code, start.Body.String()) }
	grant := parseOAuthBody(t, start)
	u, err := url.Parse(grant["authorization_url"].(string))
	if err != nil { t.Fatal(err) }
	state := u.Query().Get("state")
	if !strings.HasPrefix(state, "android_") { t.Fatal("Android 状态标识缺失") }

	callback := httptest.NewRecorder()
	r.ServeHTTP(callback, httptest.NewRequest(http.MethodGet,
		"/callback?state="+url.QueryEscape(state)+"&code=mobile-code", nil))
	if callback.Code != http.StatusOK { t.Fatalf("Android callback %d: %s", callback.Code, callback.Body.String()) }
	page := callback.Body.String()
	if !strings.Contains(page, "slowlight://oauth-complete") {
		t.Fatal("授权成功页面未提供返回 Slowlight 入口")
	}
	for _, secret := range []string{"sensitive-token", "mobile-code", state, grant["poll_token"].(string), grant["session_id"].(string)} {
		if strings.Contains(page, secret) {
			t.Fatal("Android 返回页不能暴露任何授权凭据")
		}
	}
	if callback.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("回跳页不能缓存")
	}
	if callback.Header().Get("Referrer-Policy") != "no-referrer" {
		t.Fatal("回跳页应禁止 referrer 泄露")
	}
}

func TestGitHubOAuthDesktopReturnPageDoesNotUseDeepLink(t *testing.T) {
	if strings.Contains(desktopOAuthReturnHTML, "slowlight://") {
		t.Fatal("Windows 不应出现未经安装器注册的 Android deep link")
	}
	if !strings.Contains(desktopOAuthReturnHTML, "等待 Windows 客户端确认登录") ||
		!strings.Contains(desktopOAuthReturnHTML, "检查授权结果") {
		t.Fatal("桌面回调页面必须区分 GitHub 授权与客户端登录确认")
	}
}
