package handler

import (
    "context"
    "errors"
    "io"
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"
)

func TestGitHubTokenFailureClassification(t *testing.T) {
    cases := []struct { name, response, want string }{
        {"expired", `{"error":"bad_verification_code","error_description":"sensitive details"}`, "github_token_invalid"},
        {"config", `{"error":"redirect_uri_mismatch"}`, "oauth_config_invalid"},
        {"temporary", `{"error":"temporarily_unavailable"}`, "github_unavailable"},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                _, _ = io.WriteString(w, tc.response)
            }))
            defer mock.Close()
            h := NewGitHubOAuthHandler(nil)
            h.TokenURL = mock.URL
            _, err := h.exchangeToken(context.Background(), "client", "secret", mock.URL, "code", "verifier")
            var oauthErr *githubOAuthError
            if !errors.As(err, &oauthErr) || oauthErr.Code != tc.want {
                t.Fatalf("want %s, got %v", tc.want, err)
            }
            if strings.Contains(githubOAuthMessage(tc.want), "sensitive") {
                t.Fatal("public message must not expose GitHub response")
            }
        })
    }
}

func TestGitHubProfileGetRetriesTransientFailure(t *testing.T) {
    attempts := 0
    mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        attempts++
        if attempts == 1 { w.WriteHeader(http.StatusServiceUnavailable); return }
        _, _ = io.WriteString(w, `{"id":99,"login":"retry-ok"}`)
    }))
    defer mock.Close()
    h := NewGitHubOAuthHandler(nil)
    h.UserURL = mock.URL
    profile, err := h.loadProfile(context.Background(), "test-token")
    if err != nil || profile.ID != 99 || attempts != 2 {
        t.Fatalf("profile=%v attempts=%d err=%v", profile, attempts, err)
    }
}

func TestGitHubProfileGetDoesNotRetryForbidden(t *testing.T) {
    attempts := 0
    mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        attempts++
        w.WriteHeader(http.StatusForbidden)
    }))
    defer mock.Close()
    h := NewGitHubOAuthHandler(nil)
    h.UserURL = mock.URL
    _, err := h.loadProfile(context.Background(), "test-token")
    if err == nil || attempts != 1 { t.Fatalf("expected one request, attempts=%d err=%v", attempts, err) }
}

func TestGitHubOAuthFailureMessageSeparatesCancelled(t *testing.T) {
    if githubOAuthMessage("access_denied") == githubOAuthMessage("github_unavailable") {
        t.Fatal("user cancellation must be distinct from network failures")
    }
    if githubOAuthHTTPStatus("access_denied") != http.StatusBadRequest ||
        githubOAuthHTTPStatus("github_unavailable") != http.StatusServiceUnavailable {
        t.Fatal("oauth error HTTP status mismatch")
    }
}
