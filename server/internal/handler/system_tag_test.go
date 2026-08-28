package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
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
	r.POST("/system-tags", h.CreateSystemTag)
	r.PUT("/system-tags/:id", h.UpdateSystemTag)
	r.DELETE("/system-tags/:id", h.DeleteSystemTag)
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
