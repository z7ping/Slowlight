package handler

import (
	"bytes"
	"encoding/json"
    "errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"time"
	"testing"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

func setupSystemTagTest(t *testing.T) (*gorm.DB, *SystemTagHandler, uint) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewSystemTagHandler(tx)
	user := createTestUser(t, tx)
	return tx, handler, user.ID
}

func newSystemTagRouter(h *SystemTagHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.GET("/system-tags", h.GetSystemTags)
	r.GET("/system-tags/usage", h.GetSystemTagUsage)
	r.POST("/system-tags", h.CreateSystemTag)
	r.PUT("/system-tags/:id", h.UpdateSystemTag)
	r.DELETE("/system-tags/:id", h.DeleteSystemTag)
	r.POST("/system-tags/undo", h.UndoSystemTagDelete)
	r.GET("/undo-receipt", GetDeletionUndoReceipt(h.DB))
	return r
}

// ========== GetSystemTags ==========

func TestGetSystemTags_Empty(t *testing.T) {
	_, handler, userID := setupSystemTagTest(t)
	r := newSystemTagRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/system-tags", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var tags []model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tags)
	assertEqual(t, len(tags), 0, "TagCount")
}

func TestGetSystemTags_ReturnsDefaults(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/system-tags", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var tags []model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tags)
	assertEqual(t, len(tags), 4, "TagCount")
	assertEqual(t, tags[0].Name, "身体", "FirstTag")
	assertEqual(t, tags[0].Icon, "💪", "FirstTagIcon")
	assertEqual(t, tags[1].Name, "认知", "SecondTag")
	assertEqual(t, tags[2].Name, "产出", "ThirdTag")
	assertEqual(t, tags[3].Name, "关系", "FourthTag")
}

func TestGetSystemTags_OnlyOwnTags(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	createDefaultSystemTags(t, tx, userID)

	// 创建另一个用户及其标签
	otherUser := createTestUser(t, tx)
	createDefaultSystemTags(t, tx, otherUser.ID)

	r := newSystemTagRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/system-tags", nil)
	r.ServeHTTP(w, req)

	var tags []model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tags)
	assertEqual(t, len(tags), 4, "ShouldOnlySeeOwnTags")
}

func TestSystemTagUsage_P15OnlyOwnedLiveRecords(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	other := createTestUser(t, tx)
	list := createTestList(t, tx, userID, "工作")
	otherList := createTestList(t, tx, other.ID, "其他")
	tag := model.SystemTag{UserID: userID, Name: "专注", Icon: "🎯", Color: "#334455"}
	if err := tx.Create(&tag).Error; err != nil { t.Fatal(err) }
	task := createTestTask(t, tx, userID, list.ID, "标记任务")
	if err := tx.Model(&task).Update("system_tag_id", tag.ID).Error; err != nil {
		t.Fatal(err)
	}
	removed := createTestTask(t, tx, userID, list.ID, "已删任务")
	if err := tx.Model(&removed).Update("system_tag_id", tag.ID).Error; err != nil {
		t.Fatal(err)
	}
	if err := tx.Delete(&removed).Error; err != nil { t.Fatal(err) }
	unrelated := createTestTask(t, tx, other.ID, otherList.ID, "其他用户任务")
	if err := tx.Model(&unrelated).Update("system_tag_id", tag.ID).Error; err != nil {
		t.Fatal(err)
	}
	habit := model.Habit{UserID: userID, Name: "专注习惯", SystemTagID: &tag.ID}
	if err := tx.Create(&habit).Error; err != nil { t.Fatal(err) }
	session := model.WorkSession{
		UserID: userID, SessionType: "work",
		StartedAt: time.Now(), SystemTagID: &tag.ID,
	}
	if err := tx.Create(&session).Error; err != nil { t.Fatal(err) }

	router := newSystemTagRouter(handler, userID)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/system-tags/usage", nil))
	assertEqual(t, w.Code, http.StatusOK, "usage HTTP")
	var response struct {
		Counts map[string]systemTagUsage `json:"counts"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil { t.Fatal(err) }
	counts, ok := response.Counts[fmt.Sprint(tag.ID)]
	if !ok { t.Fatal("missing owned tag usage") }
	assertEqual(t, counts.Tasks, int64(1), "live owned tasks only")
	assertEqual(t, counts.Habits, int64(1), "habit usage")
	assertEqual(t, counts.Sessions, int64(1), "legacy session usage")
	assertEqual(t, counts.Reflections, int64(0), "no reflection usage")
}

func TestDeleteSystemTag_P15ClearsLegacySessions(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tag := model.SystemTag{UserID: userID, Name: "专注", Icon: "🎯", Color: "#334455"}
	if err := tx.Create(&tag).Error; err != nil { t.Fatal(err) }
	session := model.WorkSession{
		UserID: userID, SessionType: "work",
		StartedAt: time.Now(), SystemTagID: &tag.ID,
	}
	if err := tx.Create(&session).Error; err != nil { t.Fatal(err) }
	router := newSystemTagRouter(handler, userID)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(
		http.MethodDelete, fmt.Sprintf("/system-tags/%d", tag.ID), nil,
	))
	assertEqual(t, w.Code, http.StatusOK, "delete tag")
	var existing model.WorkSession
	if err := tx.First(&existing, session.ID).Error; err != nil { t.Fatal(err) }
	if existing.SystemTagID != nil { t.Fatal("session retains deleted tag") }
}

// ========== UpdateSystemTag ==========

func TestUpdateSystemTag_UpdateIcon(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"icon": "🏋️",
	}
	jsonBody, _ := json.Marshal(body)

	url := fmt.Sprintf("/system-tags/%d", tags[0].ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", url, bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var tag model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tag)
	assertEqual(t, tag.Icon, "🏋️", "UpdatedIcon")
	assertEqual(t, tag.Color, "#52c41a", "ColorUnchanged")
	assertEqual(t, tag.Name, "身体", "NameUnchanged")
	assertEqual(t, tag.IsDefault, true, "IsDefaultUnchanged")
}

func TestUpdateSystemTag_UpdateColor(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"color": "#ff0000",
	}
	jsonBody, _ := json.Marshal(body)

	url := fmt.Sprintf("/system-tags/%d", tags[1].ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", url, bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var tag model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tag)
	assertEqual(t, tag.Color, "#ff0000", "UpdatedColor")
	assertEqual(t, tag.Icon, "🧠", "IconUnchanged")
}

func TestUpdateSystemTag_UpdateBoth(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"icon":  "🚀",
		"color": "#00ff00",
	}
	jsonBody, _ := json.Marshal(body)

	url := fmt.Sprintf("/system-tags/%d", tags[2].ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", url, bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var tag model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tag)
	assertEqual(t, tag.Icon, "🚀", "UpdatedIcon")
	assertEqual(t, tag.Color, "#00ff00", "UpdatedColor")
}

func TestUpdateSystemTag_NotFound(t *testing.T) {
	_, handler, userID := setupSystemTagTest(t)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{"icon": "🏋️"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/system-tags/99999", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusNotFound, "StatusCode")
}

func TestUpdateSystemTag_EmptyBody(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	url := fmt.Sprintf("/system-tags/%d", tags[0].ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", url, bytes.NewBufferString("{}"))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusBadRequest, "StatusCode")
}

func TestUpdateSystemTag_CannotAccessOtherUserTags(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)

	// 创建另一个用户的标签
	otherUser := createTestUser(t, tx)
	otherTags := createDefaultSystemTags(t, tx, otherUser.ID)

	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{"icon": "🏋️"}
	jsonBody, _ := json.Marshal(body)

	url := fmt.Sprintf("/system-tags/%d", otherTags[0].ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", url, bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusNotFound, "StatusCode")
}

// ========== CreateSystemTag ==========

func TestCreateSystemTag_Success(t *testing.T) {
	_, handler, userID := setupSystemTagTest(t)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"name":  "创作",
		"icon":  "✍️",
		"color": "#faad14",
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/system-tags", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusCreated, "StatusCode")

	var tag model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tag)
	assertEqual(t, tag.Name, "创作", "Name")
	assertEqual(t, tag.Icon, "✍️", "Icon")
	assertEqual(t, tag.IsDefault, false, "IsDefault")
	assertEqual(t, tag.UserID, userID, "UserID")
}

func TestCreateSystemTag_Defaults(t *testing.T) {
	_, handler, userID := setupSystemTagTest(t)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"name": "极简标签",
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/system-tags", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusCreated, "StatusCode")

	var tag model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tag)
	assertEqual(t, tag.Icon, "🏷️", "DefaultIcon")
	assertEqual(t, tag.Color, "#1890ff", "DefaultColor")
}

func TestCreateSystemTag_DuplicateName(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"name": "身体",
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/system-tags", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusConflict, "StatusCode")
}

func TestCreateSystemTag_MissingName(t *testing.T) {
	_, handler, userID := setupSystemTagTest(t)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"icon": "✍️",
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/system-tags", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusBadRequest, "StatusCode")
}

func TestDeleteSystemTag_X08ReceiptConfirmsUnknownDeleteResponse(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tag := model.SystemTag{UserID: userID, Name: "响应丢失标签", Icon: "📌", Color: "#aabbcc"}
	if err := tx.Create(&tag).Error; err != nil { t.Fatal(err) }
	router := newSystemTagRouter(handler, userID)
	token := "fedcba9876543210fedcba9876543210"
	url := fmt.Sprintf("/system-tags/%d?undoable=true&undo_token=%s&expected_tasks=0&expected_habits=0&expected_sessions=0&expected_reflections=0", tag.ID, token)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusOK { t.Fatalf("标签删除失败: %d %s", w.Code, w.Body.String()) }
	proof := "/undo-receipt?kind=system_tag&token=" + token
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, proof, nil))
	if w.Code != http.StatusOK { t.Fatalf("缺少已提交凭据: %d", w.Code) }
	payload, _ := json.Marshal(map[string]string{"token": token})
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/system-tags/undo", bytes.NewReader(payload)))
	if w.Code != http.StatusOK { t.Fatalf("无法按原ID恢复标签: %d %s", w.Code, w.Body.String()) }
	var restored model.SystemTag
	if err := tx.First(&restored, tag.ID).Error; err != nil { t.Fatal(err) }
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, proof, nil))
	if w.Code != http.StatusNotFound { t.Fatalf("凭据重复可用: %d", w.Code) }
}

func TestDeleteSystemTag_X08UndoRestoresOriginalAliasAndLinks(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	list := createTestList(t, tx, userID, "X08 清单")
	tag := model.SystemTag{UserID: userID, Name: "可恢复", Icon: "🎯", Color: "#123456"}
	if err := tx.Create(&tag).Error; err != nil { t.Fatal(err) }
	if err := syncSystemTagToCanonical(tx, tag); err != nil { t.Fatal(err) }
	var alias model.LegacySystemTagAlias
	if err := tx.Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
		First(&alias).Error; err != nil { t.Fatal(err) }
	task := createTestTask(t, tx, userID, list.ID, "保留关联")
	if err := tx.Model(&task).Update("system_tag_id", tag.ID).Error; err != nil { t.Fatal(err) }
	if err := tx.Create(&model.TaskTag{TaskID: task.ID, TagID: alias.TagID}).Error; err != nil { t.Fatal(err) }
	habit := model.Habit{UserID: userID, Name: "有标签习惯", SystemTagID: &tag.ID}
	if err := tx.Create(&habit).Error; err != nil { t.Fatal(err) }
	if err := tx.Create(&model.HabitTag{HabitID: habit.ID, TagID: alias.TagID}).Error; err != nil { t.Fatal(err) }
	router := newSystemTagRouter(handler, userID)
	url := fmt.Sprintf("/system-tags/%d?undoable=true&expected_tasks=1&expected_habits=1&expected_sessions=0&expected_reflections=0", tag.ID)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusOK { t.Fatalf("删除失败: %d %s", w.Code, w.Body.String()) }
	var result struct { UndoToken string `json:"undo_token"` }
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
	if len(result.UndoToken) != 32 { t.Fatalf("无效撤销凭据: %q", result.UndoToken) }
	var old model.SystemTag
	if err := tx.First(&old, tag.ID).Error; err == nil { t.Fatal("标签删除后仍可读") }
	var canonical model.Tag
	if err := tx.First(&canonical, alias.TagID).Error; err == nil { t.Fatal("未删除统一标签") }
	body, _ := json.Marshal(map[string]string{"token": result.UndoToken})
	w = httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/system-tags/undo", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK { t.Fatalf("撤销失败: %d %s", w.Code, w.Body.String()) }
	if err := tx.First(&old, tag.ID).Error; err != nil { t.Fatal("原标签ID未恢复", err) }
	if err := tx.First(&canonical, alias.TagID).Error; err != nil { t.Fatal("原统一标签ID未恢复", err) }
	var restoredTask model.Task
	if err := tx.First(&restoredTask, task.ID).Error; err != nil { t.Fatal(err) }
	if restoredTask.SystemTagID == nil || *restoredTask.SystemTagID != tag.ID {
		t.Fatal("旧任务标签关联未恢复")
	}
	var restoredHabit model.Habit
	if err := tx.First(&restoredHabit, habit.ID).Error; err != nil { t.Fatal(err) }
	if restoredHabit.SystemTagID == nil || *restoredHabit.SystemTagID != tag.ID {
		t.Fatal("旧习惯标签关联未恢复")
	}
	var n int64
	tx.Model(&model.TaskTag{}).Where("task_id = ? AND tag_id = ?", task.ID, alias.TagID).Count(&n)
	if n != 1 { t.Fatal("旧 task_tags 关联未恢复") }
	tx.Model(&model.HabitTag{}).Where("habit_id = ? AND tag_id = ?", habit.ID, alias.TagID).Count(&n)
	if n != 1 { t.Fatal("旧 habit_tags 关联未恢复") }
	w = httptest.NewRecorder()
	again := httptest.NewRequest(http.MethodPost, "/system-tags/undo", bytes.NewReader(body))
	again.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(w, again)
	if w.Code != http.StatusConflict { t.Fatalf("重复撤销必须409: %d", w.Code) }
}

func TestDeleteSystemTag_X08UndoRefusesChangedLegacyAssociation(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	list := createTestList(t, tx, userID, "冲突")
	tag := model.SystemTag{UserID: userID, Name: "原归属", Icon: "🎯", Color: "#123456"}
	if err := tx.Create(&tag).Error; err != nil { t.Fatal(err) }
	task := createTestTask(t, tx, userID, list.ID, "改归属")
	if err := tx.Model(&task).Update("system_tag_id", tag.ID).Error; err != nil { t.Fatal(err) }
	router := newSystemTagRouter(handler, userID)
	url := fmt.Sprintf("/system-tags/%d?undoable=true&expected_tasks=1&expected_habits=0&expected_sessions=0&expected_reflections=0", tag.ID)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusOK { t.Fatalf("删除失败: %s", w.Body.String()) }
	var result struct { UndoToken string `json:"undo_token"` }
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
	other := model.SystemTag{UserID: userID, Name: "新归属", Icon: "📚", Color: "#456789"}
	if err := tx.Create(&other).Error; err != nil { t.Fatal(err) }
	if err := tx.Model(&task).Update("system_tag_id", other.ID).Error; err != nil { t.Fatal(err) }
	body, _ := json.Marshal(map[string]string{"token": result.UndoToken})
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/system-tags/undo", bytes.NewReader(body)))
	if w.Code != http.StatusConflict { t.Fatalf("旧标签撤销应拒绝新归属: %d", w.Code) }
	var previous model.SystemTag
	if err := tx.First(&previous, tag.ID).Error; err == nil {
		t.Fatal("已变化的标签被部分恢复")
	}
}

func TestDeleteSystemTag_X08RejectsStaleApprovedAssociationCount(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	list := createTestList(t, tx, userID, "专注清单")
	tag := model.SystemTag{UserID: userID, Name: "X08 核对", Icon: "🎯", Color: "#334455"}
	if err := tx.Create(&tag).Error; err != nil { t.Fatal(err) }
	router := newSystemTagRouter(handler, userID)
	// The dialog approved a zero-impact deletion, then a new task arrived.
	task := createTestTask(t, tx, userID, list.ID, "后续新增的任务")
	if err := tx.Model(&task).Update("system_tag_id", tag.ID).Error; err != nil { t.Fatal(err) }
	url := fmt.Sprintf("/system-tags/%d?expected_tasks=0&expected_habits=0&expected_sessions=0&expected_reflections=0", tag.ID)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusConflict { t.Fatalf("应拒绝过期删除: %d %s", w.Code, w.Body.String()) }
	var remaining model.SystemTag
	if err := tx.First(&remaining, tag.ID).Error; err != nil { t.Fatal("拒绝后标签丢失:", err) }
	var kept model.Task
	if err := tx.First(&kept, task.ID).Error; err != nil { t.Fatal(err) }
	if kept.SystemTagID == nil || *kept.SystemTagID != tag.ID { t.Fatal("拒绝后任务关联被清除") }
	url = fmt.Sprintf("/system-tags/%d?expected_tasks=1&expected_habits=0&expected_sessions=0&expected_reflections=0", tag.ID)
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusOK { t.Fatalf("核对后删除失败: %d %s", w.Code, w.Body.String()) }
	if err := tx.First(&kept, task.ID).Error; err != nil { t.Fatal(err) }
	if kept.SystemTagID != nil { t.Fatal("批准后仍保留旧关联") }
	partial := httptest.NewRecorder()
	tag2 := model.SystemTag{UserID: userID, Name: "参数不完整"}
	if err := tx.Create(&tag2).Error; err != nil { t.Fatal(err) }
	router.ServeHTTP(partial, httptest.NewRequest(http.MethodDelete,
		fmt.Sprintf("/system-tags/%d?expected_tasks=0", tag2.ID), nil))
	if partial.Code != http.StatusBadRequest { t.Fatalf("残缺参数应400: %d", partial.Code) }
}

// ========== DeleteSystemTag ==========

func TestDeleteSystemTag_CustomTag(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	r := newSystemTagRouter(handler, userID)

	tag := model.SystemTag{
		UserID:    userID,
		Name:      "自定义标签",
		Icon:      "🏷️",
		Color:     "#1890ff",
		SortOrder: 5,
		IsDefault: false,
	}
	tx.Create(&tag)

	url := fmt.Sprintf("/system-tags/%d", tag.ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", url, nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var count int64
	tx.Model(&model.SystemTag{}).Where("id = ?", tag.ID).Count(&count)
	assertEqual(t, count, int64(0), "Deleted")
}

func TestDeleteSystemTag_DefaultTagForbidden(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	url := fmt.Sprintf("/system-tags/%d", tags[0].ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", url, nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusForbidden, "StatusCode")
}

func TestDeleteSystemTag_NotFound(t *testing.T) {
	_, handler, userID := setupSystemTagTest(t)
	r := newSystemTagRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/system-tags/99999", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusNotFound, "StatusCode")
}

func TestDeleteSystemTag_CleansUpReferences(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	list := createTestList(t, tx, userID, "工作")
	r := newSystemTagRouter(handler, userID)

	tag := model.SystemTag{
		UserID:    userID,
		Name:      "临时标签",
		IsDefault: false,
	}
	tx.Create(&tag)

	task := model.Task{UserID: userID, ListID: list.ID, Title: "关联任务", SystemTagID: &tag.ID}
	tx.Create(&task)
	habit := model.Habit{UserID: userID, Name: "关联习惯", SystemTagID: &tag.ID}
	tx.Create(&habit)

	url := fmt.Sprintf("/system-tags/%d", tag.ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", url, nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var updatedTask model.Task
	tx.First(&updatedTask, task.ID)
	if updatedTask.SystemTagID != nil {
		t.Error("任务的 system_tag_id 应被清空")
	}

	var updatedHabit model.Habit
	tx.First(&updatedHabit, habit.ID)
	if updatedHabit.SystemTagID != nil {
		t.Error("习惯的 system_tag_id 应被清空")
	}
}

// ========== UpdateSystemTag Phase 2: 改名 ==========

func TestUpdateSystemTag_RenameCustom(t *testing.T) {
	tx, handler, userID := setupSystemTagTest(t)
	tags := createDefaultSystemTags(t, tx, userID)
	r := newSystemTagRouter(handler, userID)

	body := map[string]interface{}{
		"name": "身体💪",
	}
	jsonBody, _ := json.Marshal(body)

	url := fmt.Sprintf("/system-tags/%d", tags[0].ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", url, bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "StatusCode")

	var tag model.SystemTag
	json.Unmarshal(w.Body.Bytes(), &tag)
	assertEqual(t, tag.Name, "身体💪", "RenamedName")
}

func TestManagedLabelsAreSelectableCanonicalTags(t *testing.T) {
    tx, handler, userID := setupSystemTagTest(t)
    if err := createDefaultAccountData(tx, userID); err != nil { t.Fatal(err) }
    var initial int64
    if err := tx.Model(&model.Tag{}).Where("user_id = ?", userID).Count(&initial).Error; err != nil { t.Fatal(err) }
    if initial != 4 { t.Fatalf("want four selectable defaults; got %d", initial) }

    router := newSystemTagRouter(handler, userID)
    add := httptest.NewRecorder()
    body := bytes.NewBufferString(`{"name":"项目复盘","icon":"✍️","color":"#445566"}`)
    req := httptest.NewRequest(http.MethodPost, "/system-tags", body)
    req.Header.Set("Content-Type", "application/json")
    router.ServeHTTP(add, req)
    if add.Code != http.StatusCreated { t.Fatalf("create failed: %d %s", add.Code, add.Body.String()) }
    var legacy model.SystemTag
    if err := json.Unmarshal(add.Body.Bytes(), &legacy); err != nil { t.Fatal(err) }

    var alias model.LegacySystemTagAlias
    if err := tx.Where("user_id = ? AND system_tag_id = ?", userID, legacy.ID).
        Take(&alias).Error; err != nil { t.Fatal(err) }
    if alias.TagID == 0 { t.Fatal("missing canonical mapping") }

    path := fmt.Sprintf("/system-tags/%d", legacy.ID)
    change := httptest.NewRecorder()
    update := httptest.NewRequest(http.MethodPut, path,
        bytes.NewBufferString(`{"name":"复盘归档","color":"#abcdef"}`))
    update.Header.Set("Content-Type", "application/json")
    router.ServeHTTP(change, update)
    if change.Code != http.StatusOK { t.Fatalf("update failed: %d %s", change.Code, change.Body.String()) }
    var canonical model.Tag
    if err := tx.First(&canonical, alias.TagID).Error; err != nil { t.Fatal(err) }
    if canonical.Name != "复盘归档" || canonical.Color != "#abcdef" {
        t.Fatalf("picker label not in sync: %#v", canonical)
    }

    remove := httptest.NewRecorder()
    router.ServeHTTP(remove, httptest.NewRequest(http.MethodDelete, path, nil))
    if remove.Code != http.StatusOK { t.Fatalf("delete failed: %d %s", remove.Code, remove.Body.String()) }
    if err := tx.First(&canonical, alias.TagID).Error; !errors.Is(err, gorm.ErrRecordNotFound) {
        t.Fatalf("deleted managed label must disappear from canonical picker: %v", err)
    }
}
