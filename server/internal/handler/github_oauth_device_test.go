package handler

import (
    "io"
    "net/http"
    "net/http/httptest"
    "strings"
    "sync/atomic"
    "testing"
    "time"

    "slowlight/internal/model"
)

func TestGitHubDeviceFlowOptInAndPolling(t *testing.T) {
    db := setupTestDB(t)
    t.Setenv("JWT_SECRET", "test-signing-key")
    t.Setenv("CONFIG_ENCRYPTION_KEY", strings.Repeat("test-encryption", 3))
    t.Setenv("GITHUB_OAUTH_CLIENT_ID", "test-client")
    t.Setenv("GITHUB_OAUTH_CLIENT_SECRET", "test-secret")
    t.Setenv("GITHUB_OAUTH_CALLBACK_URL", "https://example.org/api/auth/github/callback")
    t.Setenv("GITHUB_OAUTH_ENABLE_DEVICE_FLOW", "false")

    var polls atomic.Int32
    provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        switch r.URL.Path {
        case "/device/code":
            _, _ = io.WriteString(w, `{"device_code":"secret-device-code","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}`)
        case "/token":
            _ = r.ParseForm()
            if r.Form.Get("client_secret") != "" { t.Error("device polling must not send Client Secret") }
            if r.Form.Get("device_code") != "secret-device-code" { t.Error("device code missing") }
            if polls.Add(1) == 1 {
                _, _ = io.WriteString(w, `{"error":"authorization_pending"}`)
            } else {
                _, _ = io.WriteString(w, `{"access_token":"access-for-profile"}`)
            }
        case "/user":
            if r.Header.Get("Authorization") != "Bearer access-for-profile" { t.Error("missing GitHub bearer") }
            _, _ = io.WriteString(w, `{"id":1234567,"login":"device-user"}`)
        default: w.WriteHeader(http.StatusNotFound)
        }
    }))
    defer provider.Close()

    h := NewGitHubOAuthHandler(db)
    h.DeviceAuthURL = provider.URL + "/device/code"
    h.TokenURL = provider.URL + "/token"
    h.UserURL = provider.URL + "/user"
    router := newTestGin()
    router.POST("/device/start", h.DeviceStart)
    router.POST("/poll", h.Poll)
    if disabled := testOAuthRequest(t, router, "/device/start", map[string]string{}); disabled.Code != http.StatusNotImplemented {
        t.Fatalf("device flow must be disabled by default: %d", disabled.Code)
    }
    t.Setenv("GITHUB_OAUTH_ENABLE_DEVICE_FLOW", "true")
    start := testOAuthRequest(t, router, "/device/start", map[string]string{})
    if start.Code != 200 { t.Fatalf("device flow start: %d %s", start.Code, start.Body.String()) }
    grant := parseOAuthBody(t, start)
    if grant["user_code"] != "ABCD-1234" { t.Fatalf("user code missing: %v", grant) }
    if _, ok := grant["device_code"]; ok { t.Fatal("never send secret device code to app") }
    sessionID := grant["session_id"].(string)
    var saved model.OAuthLoginSession
    if err := db.First(&saved, "id = ?", sessionID).Error; err != nil { t.Fatal(err) }
    if strings.Contains(saved.DeviceCodeCiphertext, "secret-device-code") { t.Fatal("device code stored in plaintext") }
    creds := map[string]string{"session_id": sessionID, "poll_token": grant["poll_token"].(string), "mode": "reliable"}
    ready := false
    deadline := time.Now().Add(8 * time.Second)
    for time.Now().Before(deadline) {
        db.Model(&model.OAuthLoginSession{}).Where("id = ? AND status = ?", sessionID, "device_pending").
            Update("retry_after", time.Now().Add(-time.Second))
        response := testOAuthRequest(t, router, "/poll", creds)
        if response.Code != 200 { t.Fatalf("device polling: %d %s", response.Code, response.Body.String()) }
        body := parseOAuthBody(t, response)
        if body["status"] == "complete" { ready = true; break }
        time.Sleep(20 * time.Millisecond)
    }
    if !ready || polls.Load() < 2 { t.Fatal("device flow did not complete after authorization_pending") }
}
