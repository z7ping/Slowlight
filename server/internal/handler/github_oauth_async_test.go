package handler

import (
    "net/http"
    "net/http/httptest"
    "net/url"
    "strings"
    "testing"
    "time"
    "io"

    "slowlight/internal/model"
    "slowlight/internal/secureconfig"
)

func TestGitHubOAuthCallbackReturnsBeforeProviderCompletes(t *testing.T) {
    db := beginTx(t, setupTestDB(t))
    t.Setenv("JWT_SECRET", "test-signing-key")
    t.Setenv("CONFIG_ENCRYPTION_KEY", strings.Repeat("test-encryption", 3))
    t.Setenv("GITHUB_OAUTH_CLIENT_ID", "test-client")
    t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "test-secret")
    t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "https://example.org/api/auth/github/callback")

    begun := make(chan struct{}, 1)
    release := make(chan struct{})
    defer func() { select { case <-release: default: close(release) } }()
    provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        switch r.URL.Path {
        case "/token":
            begun <- struct{}{}
            <-release
            _, _ = io.WriteString(w, `{"access_token":"temporary-token"}`)
        case "/user":
            _, _ = io.WriteString(w, `{"id":7654321,"login":"oauth-user"}`)
        }
    }))
    defer provider.Close()

    h := NewGitHubOAuthHandler(db)
    h.TokenURL = provider.URL + "/token"
    h.UserURL = provider.URL + "/user"
    router := newTestGin()
    router.POST("/start", h.Start)
    router.GET("/callback", h.Callback)
    router.POST("/poll", h.Poll)
    grant := parseOAuthBody(t, testOAuthRequest(t, router, "/start", map[string]string{}))
    authURL, _ := url.Parse(grant["authorization_url"].(string))
    callback := httptest.NewRecorder()
    router.ServeHTTP(callback, httptest.NewRequest(http.MethodGet,
        "/callback?state="+url.QueryEscape(authURL.Query().Get("state"))+"&code=testcode", nil))
    if callback.Code != 200 { t.Fatalf("callback must return immediately: %d", callback.Code) }
    select {
    case <-begun:
    case <-time.After(time.Second): t.Fatal("background worker did not start")
    }
    creds := map[string]string{"session_id": grant["session_id"].(string), "poll_token": grant["poll_token"].(string)}
    processing := parseOAuthBody(t, testOAuthRequest(t, router, "/poll", creds))
    if processing["status"] != "pending" { t.Fatalf("worker should still be pending: %v", processing) }
    close(release)
    waitForOAuthReady(t, router, creds)
    var session model.OAuthLoginSession
    if err := db.First(&session, "id = ?", creds["session_id"]).Error; err != nil { t.Fatal(err) }
    if session.RecoveryToken != "" || session.Status != "ready" {
        t.Fatalf("temporary encrypted credential must be purged on success: %s", session.Status)
    }
}

func TestGitHubOAuthResumesOnlyEncryptedProfileRequest(t *testing.T) {
    db := beginTx(t, setupTestDB(t))
    t.Setenv("JWT_SECRET", "test-signing-key")
    t.Setenv("CONFIG_ENCRYPTION_KEY", strings.Repeat("test-encryption", 3))
    t.Setenv("GITHUB_OAUTH_CLIENT_ID", "test-client")
    t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "test-secret")
    t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "https://example.org/api/auth/github/callback")
    profileCalls := 0
    provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if r.URL.Path != "/user" { t.Errorf("never repeat one-time code exchange: %s", r.URL.Path); return }
        profileCalls++
        if r.Header.Get("Authorization") != "Bearer recovered-token" {
            t.Error("encrypted temporary credential not restored correctly")
        }
        _, _ = io.WriteString(w, `{"id":7654322,"login":"recovered-user"}`)
    }))
    defer provider.Close()
    h := NewGitHubOAuthHandler(db)
    h.TokenURL = provider.URL + "/token"
    h.UserURL = provider.URL + "/user"
    router := newTestGin()
    router.POST("/start", h.Start)
    router.POST("/poll", h.Poll)
    grant := parseOAuthBody(t, testOAuthRequest(t, router, "/start", map[string]string{}))
    encrypted, err := secureconfig.Encrypt("recovered-token")
    if err != nil { t.Fatal(err) }
    sessionID := grant["session_id"].(string)
    if err := db.Model(&model.OAuthLoginSession{}).Where("id = ?", sessionID).
        Updates(map[string]interface{}{
            "status": "retryable", "error_stage": "profile",
            "recovery_token": encrypted, "retry_after": time.Now().Add(-time.Second),
            "code_verifier": "", "recovery_attempts": 1,
        }).Error; err != nil { t.Fatal(err) }
    creds := map[string]string{"session_id": sessionID, "poll_token": grant["poll_token"].(string)}
    _ = testOAuthRequest(t, router, "/poll", creds)
    waitForOAuthReady(t, router, creds)
    if profileCalls != 1 { t.Fatalf("expected one recovery profile request: %d", profileCalls) }
    var state model.OAuthLoginSession
    if err := db.First(&state, "id = ?", sessionID).Error; err != nil { t.Fatal(err) }
    if state.RecoveryToken != "" { t.Fatal("encrypted temporary credential not cleared") }
}
