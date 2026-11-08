package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestServerVersionEndpointWithoutAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)
	beforeVersion, beforeHash, beforeTime, beforeBuild := version, commitHash, commitTime, buildTime
	t.Cleanup(func() {
		version, commitHash, commitTime, buildTime = beforeVersion, beforeHash, beforeTime, beforeBuild
	})
	version = "0.2.1"
	commitHash = strings.Repeat("a", 40)
	commitTime = "2026-11-08T12:30:00+08:00"
	buildTime = "2026-11-08T04:45:00Z"
	t.Setenv("SLOWLIGHT_DEPLOYED_AT", "2026-11-08T05:00:00Z")

	r := gin.New()
	r.GET("/api/version", serverVersionHandler)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/version", nil))
	if rec.Code != http.StatusOK || rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("unexpected status/header: %d %v", rec.Code, rec.Header())
	}
	var got versionDetails
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Version == nil || *got.Version != "0.2.1" ||
		got.CommitHash == nil || *got.CommitHash != commitHash ||
		got.CommitTime == nil || *got.CommitTime != "2026-11-08T04:30:00Z" ||
		got.DeployedAt == nil || *got.DeployedAt != "2026-11-08T05:00:00Z" ||
		got.BuiltAt == nil || *got.BuiltAt != "2026-11-08T04:45:00Z" {
		t.Fatalf("unexpected build metadata: %+v", got)
	}
}

func TestServerVersionUnknownIsNotFabricated(t *testing.T) {
	t.Setenv("SLOWLIGHT_DEPLOYED_AT", "not-a-timestamp")
	if optionalTimestamp("not-a-timestamp") != nil || optionalText("") != nil {
		t.Fatal("unknown values must remain absent")
	}
	got := currentVersion()
	if got.DeployedAt != nil {
		t.Fatalf("invalid deployment timestamp must remain unknown: %+v", got)
	}
}
