package main

import (
	"net/http"
	"os"
	"runtime/debug"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// Build metadata is provided by the release build or the self-hosted deploy
// script. Never infer a deployment time from process startup or an image build.
var (
	version    string
	commitHash string
	commitTime string
	buildTime  string
)

type versionDetails struct {
	Version    *string `json:"version"`
	DeployedAt *string `json:"deployed_at"`
	CommitTime *string `json:"commit_time"`
	CommitHash *string `json:"commit_hash"`
	BuiltAt    *string `json:"built_at"`
}

func optionalText(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}

func optionalTimestamp(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil
	}
	normalized := parsed.UTC().Format(time.RFC3339)
	return &normalized
}

func currentVersion() versionDetails {
	revision, timestamp := commitHash, commitTime
	// Native go build records VCS metadata when it has access to a clean Git
	// checkout. Docker builds deliberately do not copy .git into the image.
	if revision == "" || timestamp == "" {
		if info, ok := debug.ReadBuildInfo(); ok {
			values := map[string]string{}
			for _, setting := range info.Settings {
				values[setting.Key] = setting.Value
			}
			if values["vcs.modified"] != "true" {
				if revision == "" {
					revision = values["vcs.revision"]
				}
				if timestamp == "" {
					timestamp = values["vcs.time"]
				}
			}
		}
	}
	return versionDetails{
		Version:    optionalText(version),
		DeployedAt: optionalTimestamp(os.Getenv("SLOWLIGHT_DEPLOYED_AT")),
		CommitTime: optionalTimestamp(timestamp),
		CommitHash: optionalText(revision),
		BuiltAt:    optionalTimestamp(buildTime),
	}
}

func serverVersionHandler(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, currentVersion())
}
