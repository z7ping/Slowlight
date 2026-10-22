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
