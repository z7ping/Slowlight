package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"slowlight/internal/model"
)

func migrationRouter(h *MigrationHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.POST("/migration/preview", h.PreviewMigration)
	r.POST("/migration/execute", h.ExecuteMigration)
	return r
}

func TestExecuteMigrationCloudPolicyReusesSameNameEntities(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	list := model.List{UserID: user.ID, Name: uniqueName("云端清单")}
	if err := tx.Create(&list).Error; err != nil {
		t.Fatal(err)
	}
	r := migrationRouter(NewMigrationHandler(tx), user.ID)
	body, _ := json.Marshal(map[string]interface{}{
		"conflict_policy": "cloud",
		"lists":           []map[string]interface{}{{"id": 1, "name": list.Name}},
		"tasks":           []map[string]interface{}{{"id": 2, "list_id": 1, "title": "复用云端清单"}},
	})
	w := httptest.NewRecorder()
	req, _ := http.NewRequest(http.MethodPost, "/migration/execute", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d: %s", w.Code, w.Body.String())
	}
	var task model.Task
	if err := tx.Where("user_id = ? AND title = ?", user.ID, "复用云端清单").First(&task).Error; err != nil || task.ListID != list.ID {
		t.Fatalf("未复用云端清单: task=%#v err=%v", task, err)
	}
}

func TestExecuteMigrationCreatesCoreEntities(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	r := migrationRouter(NewMigrationHandler(tx), user.ID)
	payload := map[string]interface{}{
		"lists":       []map[string]interface{}{{"id": 11, "name": uniqueName("迁移清单"), "icon": "📋", "color": "#1890ff"}},
		"tags":        []map[string]interface{}{{"id": 12, "name": uniqueName("迁移标签"), "color": "#0075de"}},
		"system_tags": []map[string]interface{}{{"id": 16, "name": uniqueName("迁移系统标签"), "icon": "🏷️", "color": "#1890ff"}},
		"habits":      []map[string]interface{}{{"id": 13, "name": uniqueName("迁移习惯"), "icon": "✅", "color": "#52c41a", "frequency": "daily", "system_tag_id": 16}},
		"tasks":       []map[string]interface{}{{"id": 14, "list_id": 11, "title": "迁移任务", "priority": "high", "tag_ids": []int{12}, "system_tag_id": 16}},
		"subtasks":    []map[string]interface{}{{"id": 18, "task_id": 14, "title": "迁移子任务", "is_completed": true, "sort_order": 1}},
		"habit_logs":  []map[string]interface{}{{"id": 15, "habit_id": 13, "task_id": 14, "date": "2026-08-27", "note": "迁移日志"}},
		"sessions":    []map[string]interface{}{{"id": 17, "session_type": "work", "task_id": 14, "system_tag_id": 16, "started_at": "2026-08-27T10:00:00Z", "ended_at": "2026-08-27T10:25:00Z", "duration_sec": 1500, "device": "windows"}},
	}
	body, _ := json.Marshal(payload)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest(http.MethodPost, "/migration/execute", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d: %s", w.Code, w.Body.String())
	}
	var response map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &response)
	created := response["created"].(map[string]interface{})
	if created["tasks"].(float64) != 1 || created["subtasks"].(float64) != 1 || created["habits"].(float64) != 1 || created["habit_logs"].(float64) != 1 || created["sessions"].(float64) != 1 || created["system_tags"].(float64) != 1 {
		t.Fatalf("创建数量错误: %#v", created)
	}
	var report model.MigrationReport
	if err := tx.Where("user_id = ?", user.ID).First(&report).Error; err != nil || report.Status != "succeeded" || report.Created == "" {
		t.Fatalf("迁移审计报告不完整: report=%#v err=%v", report, err)
	}
	var task model.Task
	if err := tx.Preload("Tags").Where("user_id = ? AND title = ?", user.ID, "迁移任务").First(&task).Error; err != nil || len(task.Tags) != 1 || task.SystemTagID == nil {
		t.Fatalf("任务关联未迁移: task=%#v err=%v", task, err)
	}
	var subtask model.Subtask
	if err := tx.Where("task_id = ? AND title = ?", task.ID, "迁移子任务").First(&subtask).Error; err != nil || !subtask.IsCompleted || subtask.SortOrder != 1 {
		t.Fatalf("子任务未迁移: subtask=%#v err=%v", subtask, err)
	}
	var session model.WorkSession
	if err := tx.Where("user_id = ?", user.ID).First(&session).Error; err != nil || session.TaskID == nil || session.SystemTagID == nil || session.DurationSec != 1500 || session.StartedAt.IsZero() || session.EndedAt == nil || !session.EndedAt.Equal(time.Date(2026, 8, 27, 10, 25, 0, 0, time.UTC)) {
		t.Fatalf("专注记录关联未迁移: session=%#v err=%v", session, err)
	}
}
