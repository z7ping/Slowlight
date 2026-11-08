package handler

import (
    "bytes"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "slowlight/internal/model"
)

func TestRefreshSessionRotationAndLogout(t *testing.T) {
    t.Setenv("JWT_SECRET", "slowlight-refresh-test-secret")
    h := setupAuthTest(t)
    user := createTestUser(t, h.DB)
    access, refresh, err := issueAuthSession(h.DB, user.ID, "github")
    if err != nil || access == "" || refresh == "" {
        t.Fatalf("issue session: %v", err)
    }
    var stored model.AuthRefreshSession
    if err := h.DB.Where("token_hash = ?", refreshHash(refresh)).First(&stored).Error; err != nil {
        t.Fatalf("refresh hash missing: %v", err)
    }
    if stored.TokenHash == refresh { t.Fatal("plaintext refresh token persisted") }
    // 模拟 GitHub 授权已过五分钟，再轮换 Access JWT。
    proof := time.Now().UTC().Add(-10 * time.Minute).Truncate(time.Second)
    if err := h.DB.Model(&stored).Update("proof_at", proof).Error; err != nil { t.Fatal(err) }
    claims := jwt.MapClaims{}
    _, _, err = jwt.NewParser(jwt.WithValidMethods([]string{"HS256"})).ParseUnverified(access, claims)
    if err != nil { t.Fatal(err) }
    if method, _ := claims["auth_method"].(string); method != "github" { t.Fatalf("method %v", method) }
    if exp, ok := claims["exp"].(float64); !ok ||
        time.Unix(int64(exp), 0).After(time.Now().Add(2*time.Hour)) {
        t.Fatal("access token should expire in one hour")
    }

    route := newTestGin()
    route.POST("/refresh", h.Refresh)
    route.POST("/logout", h.Logout)
    call := func(path, token string) *httptest.ResponseRecorder {
        t.Helper()
        data, _ := json.Marshal(map[string]string{"refresh_token": token})
        req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(data))
        req.Header.Set("Content-Type", "application/json")
        w := httptest.NewRecorder()
        route.ServeHTTP(w, req)
        return w
    }
    w := call("/refresh", refresh)
    if w.Code != http.StatusOK { t.Fatalf("refresh returned %d: %s", w.Code, w.Body.String()) }
    var response struct { Token, RefreshToken string }
    var data map[string]string
    if err := json.Unmarshal(w.Body.Bytes(), &data); err != nil { t.Fatal(err) }
    response.Token, response.RefreshToken = data["token"], data["refresh_token"]
    if response.Token == "" || response.RefreshToken == "" || response.RefreshToken == refresh {
        t.Fatal("refresh must rotate both credentials")
    }
    refreshedClaims := jwt.MapClaims{}
    if _, _, err := jwt.NewParser().ParseUnverified(response.Token, refreshedClaims); err != nil {
        t.Fatal(err)
    }
    if got, ok := refreshedClaims["auth_time"].(float64); !ok ||
        int64(got) != proof.Unix() {
        t.Fatal("refresh must preserve original GitHub authorization time")
    }
    if second := call("/refresh", refresh); second.Code != http.StatusUnauthorized {
        t.Fatalf("reused refresh token returned %d", second.Code)
    }
    if logout := call("/logout", response.RefreshToken); logout.Code != http.StatusNoContent {
        t.Fatalf("logout returned %d", logout.Code)
    }
    if after := call("/refresh", response.RefreshToken); after.Code != http.StatusUnauthorized {
        t.Fatalf("revoked refresh token returned %d", after.Code)
    }
}

func TestRefreshRejectsExpiredSession(t *testing.T) {
    t.Setenv("JWT_SECRET", "slowlight-refresh-test-secret")
    h := setupAuthTest(t)
    user := createTestUser(t, h.DB)
    _, refresh, err := issueAuthSession(h.DB, user.ID, "password")
    if err != nil { t.Fatal(err) }
    if err := h.DB.Model(&model.AuthRefreshSession{}).
        Where("token_hash = ?", refreshHash(refresh)).
        Update("expires_at", time.Now().Add(-time.Minute)).Error; err != nil { t.Fatal(err) }
    data, _ := json.Marshal(map[string]string{"refresh_token": refresh})
    r := newTestGin()
    r.POST("/refresh", h.Refresh)
    w := httptest.NewRecorder()
    req := httptest.NewRequest(http.MethodPost, "/refresh", bytes.NewReader(data))
    req.Header.Set("Content-Type", "application/json")
    r.ServeHTTP(w, req)
    if w.Code != http.StatusUnauthorized { t.Fatalf("expired refresh returned %d", w.Code) }
}
