package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
)

func newSyncChangesRouter(h *SyncChangesHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) {
		withUser(c, userID)
		c.Next()
	})
	r.GET("/sync/changes", h.GetChanges)
	return r
}

func TestSyncChanges_UserIsolationAndTombstone(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	other := createTestUser(t, tx)
	h := NewSyncChangesHandler(tx)
	r := newSyncChangesRouter(h, user.ID)

	since := time.Now().Add(-time.Hour).UTC()
	active := model.List{UserID: user.ID, Name: "active", Icon: "📋", Color: "#1890ff"}
	deleted := model.List{UserID: user.ID, Name: "deleted", Icon: "📋", Color: "#1890ff"}
	foreign := model.List{UserID: other.ID, Name: "foreign", Icon: "📋", Color: "#1890ff"}
	if err := tx.Create(&active).Error; err != nil { t.Fatal(err) }
	if err := tx.Create(&deleted).Error; err != nil { t.Fatal(err) }
	if err := tx.Create(&foreign).Error; err != nil { t.Fatal(err) }
	if err := tx.Delete(&deleted).Error; err != nil { t.Fatal(err) }

	w := httptest.NewRecorder()
	req, _ := http.NewRequest(
		"GET",
		"/sync/changes?since="+url.QueryEscape(since.Format(time.RFC3339Nano)),
		nil,
	)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GetChanges 返回 %d, 期望 200. Body: %s", w.Code, w.Body.String())
	}

	var response SyncChangesResponse
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil { t.Fatal(err) }
	if response.ServerTime.IsZero() { t.Fatal("server_time 不应为空") }

	foundActive := false
	for _, item := range response.Lists {
		if item.ID == active.ID { foundActive = true }
		if item.UserID != user.ID {
			t.Fatalf("返回了其他用户数据: user_id=%d", item.UserID)
		}
	}
	if !foundActive { t.Fatal("未返回当前用户的活动清单") }

	deletedIDs := response.Deleted["lists"]
	if !containsUint(deletedIDs, deleted.ID) {
		t.Fatalf("删除 tombstone 缺少 list id=%d: %#v", deleted.ID, deletedIDs)
	}
	if containsUint(deletedIDs, foreign.ID) {
		t.Fatal("tombstone 不应包含其他用户记录")
	}
}

func TestSyncChanges_InvalidSince(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	r := newSyncChangesRouter(NewSyncChangesHandler(tx), user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/sync/changes?since=bad-time", nil)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("invalid since 返回 %d, 期望 400", w.Code)
	}
}

func containsUint(values []uint, target uint) bool {
	for _, value := range values {
		if value == target { return true }
	}
	return false
}
