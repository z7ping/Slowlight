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
	r.POST("/migration/recover", h.RecoverMigration)
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

func TestMigrationReportStoresReplayMap(t *testing.T) {
	db := setupTestDB(t)
	if !db.Migrator().HasColumn(&model.MigrationReport{}, "id_map") {
		t.Fatal("missing migration id_map column")
	}
}

func TestMigrationRetryReusesIDMap(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	router := migrationRouter(NewMigrationHandler(tx), user.ID)
	name := uniqueName("迁移重试")
	body, _ := json.Marshal(map[string]interface{}{
		"lists": []map[string]interface{}{{"id": 91, "name": name}},
	})
	execute := func() (int, map[string]interface{}) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest(http.MethodPost, "/migration/execute", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)
		var response map[string]interface{}
		if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil { t.Fatal(err) }
		return w.Code, response
	}
	code1, first := execute()
	code2, second := execute()
	if code1 != http.StatusOK || code2 != http.StatusOK {
		t.Fatalf("migration status %d / %d: %v", code1, code2, second)
	}
	ids1 := first["id_map"].(map[string]interface{})["lists"].(map[string]interface{})
	ids2 := second["id_map"].(map[string]interface{})["lists"].(map[string]interface{})
	if ids1["91"] != ids2["91"] || ids1["91"] == nil {
		t.Fatalf("id map lost on retry: %v / %v", ids1, ids2)
	}
	var count int64
	tx.Model(&model.List{}).Where("user_id = ? AND name = ?", user.ID, name).Count(&count)
	if count != 1 { t.Fatalf("repeated insert: %d", count) }
	// Reports created before ID mapping was persisted must not pretend to replay.
	if err := tx.Model(&model.MigrationReport{}).Where("user_id = ?", user.ID).
		Update("id_map", "").Error; err != nil { t.Fatal(err) }
	code3, _ := execute()
	if code3 != http.StatusConflict { t.Fatalf("legacy report should return 409, got %d", code3) }
}

func TestMigrationRejectsModifiedSnapshotForSameSource(t *testing.T) {
    db := setupTestDB(t)
    tx := beginTx(t, db)
    user := createTestUser(t, tx)
    router := migrationRouter(NewMigrationHandler(tx), user.ID)
    source := uniqueName("source")
    send := func(name string) int {
        data, _ := json.Marshal(map[string]interface{}{
            "source_id": source,
            "lists": []map[string]interface{}{{"id": 97, "name": name}},
        })
        w := httptest.NewRecorder()
        req, _ := http.NewRequest(http.MethodPost, "/migration/execute", bytes.NewReader(data))
        req.Header.Set("Content-Type", "application/json")
        router.ServeHTTP(w, req)
        return w.Code
    }
    if got := send(uniqueName("原始记录")); got != http.StatusOK {
        t.Fatalf("initial migration failed: %d", got)
    }
    if got := send(uniqueName("修改后记录")); got != http.StatusConflict {
        t.Fatalf("changed source snapshot should be blocked, got %d", got)
    }
}

func TestMigrationWizardPerItemPolicyAndReadOnlyRecovery(t *testing.T) {
 db := setupTestDB(t)
 tx := beginTx(t, db)
 user := createTestUser(t, tx)
 existingA := model.List{UserID: user.ID, Name: uniqueName("本地优先")}
 existingB := model.List{UserID: user.ID, Name: uniqueName("云端优先")}
 existingC := model.List{UserID: user.ID, Name: uniqueName("保留两份")}
 for _, row := range []*model.List{&existingA, &existingB, &existingC} {
   if err := tx.Create(row).Error; err != nil { t.Fatal(err) }
 }
 router := migrationRouter(NewMigrationHandler(tx), user.ID)
 snapshot := map[string]interface{}{
   "source_id": uniqueName("wizard-source"),
   "lists": []map[string]interface{}{
     {"id": 1, "name": existingA.Name},
     {"id": 2, "name": existingB.Name},
     {"id": 3, "name": existingC.Name},
   },
 }
 call := func(path string, body map[string]interface{}) (int, map[string]interface{}) {
   data, err := json.Marshal(body)
   if err != nil { t.Fatal(err) }
   w := httptest.NewRecorder()
   req, _ := http.NewRequest(http.MethodPost, path, bytes.NewReader(data))
   req.Header.Set("Content-Type", "application/json")
   router.ServeHTTP(w, req)
   out := map[string]interface{}{}
   if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil { t.Fatal(err) }
   return w.Code, out
 }
 code, preview := call("/migration/preview", snapshot)
 if code != 200 { t.Fatalf("preview: %d %v", code, preview) }
 version, ok := preview["preview_version"].(string)
 if !ok || version == "" { t.Fatalf("missing preview version: %v", preview) }
 choices := []map[string]interface{}{
   {"entity": "list", "local_id": 1, "policy": "local"},
   {"entity": "list", "local_id": 2, "policy": "cloud"},
   {"entity": "list", "local_id": 3, "policy": "both"},
 }
 execute := map[string]interface{}{
   "source_id": snapshot["source_id"],
   "lists": snapshot["lists"],
   "preview_version": version,
   "conflict_policy": "reject",
   "conflict_choices": choices,
 }
 code, result := call("/migration/execute", execute)
 if code != 200 { t.Fatalf("execute: %d %v", code, result) }
 idmap := result["id_map"].(map[string]interface{})["lists"].(map[string]interface{})
 if idmap["2"] != float64(existingB.ID) { t.Fatalf("cloud record not reused: %v", idmap) }
 var orig, renamed, duplicate model.List
 if err := tx.Where("id = ?", existingA.ID).First(&orig).Error; err != nil { t.Fatal(err) }
 if orig.Name == existingA.Name { t.Fatalf("local conflict did not back up cloud: %v", orig) }
 if err := tx.Where("user_id = ? AND name = ?", user.ID, existingA.Name).First(&renamed).Error; err != nil { t.Fatal(err) }
 if renamed.ID == existingA.ID { t.Fatalf("local record was not imported") }
 if err := tx.Where("user_id = ? AND name = ?", user.ID, existingC.Name+"（本地副本）").First(&duplicate).Error; err != nil { t.Fatalf("both copy missing: %v", err) }
 code, recovered := call("/migration/recover", execute)
 if code != 200 { t.Fatalf("recover: %d %v", code, recovered) }
 idmapRecovery := recovered["id_map"].(map[string]interface{})["lists"].(map[string]interface{})
 if idmapRecovery["3"] != idmap["3"] { t.Fatalf("recovery ID mapping mismatch: %v", idmapRecovery) }
 var count int64
 tx.Model(&model.List{}).Where("user_id = ?", user.ID).Count(&count)
 if count != 5 { t.Fatalf("unexpected list count (possible repeat import): %d", count) }
 code, replay := call("/migration/execute", execute)
 if code != 200 { t.Fatalf("same snapshot replay: %d %v", code, replay) }
 tx.Model(&model.List{}).Where("user_id = ?", user.ID).Count(&count)
 if count != 5 { t.Fatalf("replay duplicated data: %d", count) }
}

func TestMigrationWizardStalePreviewIsRejected(t *testing.T) {
 db := setupTestDB(t)
 tx := beginTx(t, db)
 user := createTestUser(t, tx)
 router := migrationRouter(NewMigrationHandler(tx), user.ID)
 snapshot := map[string]interface{}{
   "source_id": uniqueName("stale-source"),
   "lists": []map[string]interface{}{{"id": 1, "name": uniqueName("新增清单")}},
 }
 call := func(path string, value map[string]interface{}) (int, map[string]interface{}) {
   data, _ := json.Marshal(value)
   w := httptest.NewRecorder()
   req, _ := http.NewRequest(http.MethodPost, path, bytes.NewReader(data))
   req.Header.Set("Content-Type", "application/json")
   router.ServeHTTP(w, req)
   result := map[string]interface{}{}
   json.Unmarshal(w.Body.Bytes(), &result)
   return w.Code, result
 }
 code, preview := call("/migration/preview", snapshot)
 if code != 200 { t.Fatalf("preview: %d %v", code, preview) }
 name := snapshot["lists"].([]map[string]interface{})[0]["name"].(string)
 row := model.List{UserID: user.ID, Name: name}
 if err := tx.Create(&row).Error; err != nil { t.Fatal(err) }
 snapshot["preview_version"] = preview["preview_version"]
 snapshot["conflict_policy"] = "reject"
 code, result := call("/migration/execute", snapshot)
 if code != http.StatusConflict { t.Fatalf("stale preview should 409, got %d: %v", code, result) }
 var count int64
 tx.Model(&model.List{}).Where("user_id = ? AND name = ?", user.ID, name).Count(&count)
 if count != 1 { t.Fatalf("stale preview unexpectedly inserted: %d", count) }
}
