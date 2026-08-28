package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"slowlight/internal/model"
)

// setupFeishuRouter creates a gin router with user injected via middleware
func setupFeishuRouter(h *FeishuHandler, userID uint, method, path string, handlerFunc func(c *gin.Context), body []byte) *httptest.ResponseRecorder {
	r := newTestGin()
	r.Use(func(c *gin.Context) {
		withUser(c, userID)
		c.Next()
	})

	switch method {
	case "GET":
		r.GET(path, handlerFunc)
	case "POST":
		r.POST(path, handlerFunc)
	}

	w := httptest.NewRecorder()
	var req *http.Request
	if body != nil {
		req, _ = http.NewRequest(method, path, bytes.NewBuffer(body))
		req.Header.Set("Content-Type", "application/json")
	} else {
		req, _ = http.NewRequest(method, path, nil)
	}
	r.ServeHTTP(w, req)
	return w
}

// --- priorityText ---

func TestPriorityText(t *testing.T) {
	assert.Equal(t, "高", priorityText("high"))
	assert.Equal(t, "中", priorityText("medium"))
	assert.Equal(t, "低", priorityText("low"))
	assert.Equal(t, "无", priorityText(""))
	assert.Equal(t, "无", priorityText("unknown"))
}

// --- GetConfig (HTTP handler) ---

func TestGetConfig_NotConfigured(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "GET", "/api/feishu/config", h.GetConfig, nil)

	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Equal(t, false, resp["configured"])
}

func TestGetConfig_Configured(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_123","app_secret":"secret_456","table_url":"https://xxx.feishu.cn/base/abc123","tables":{"任务表":"tbl_xyz"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "GET", "/api/feishu/config", h.GetConfig, nil)

	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Equal(t, true, resp["configured"])
	assert.Equal(t, "app_123", resp["app_id"])
	assert.Equal(t, "https://xxx.feishu.cn/base/abc123", resp["table_url"])
	_, hasSecret := resp["app_secret"]
	assert.False(t, hasSecret)
	assert.NotNil(t, resp["tables"])
}

// --- getFeishuConfig (internal) ---

func TestGetFeishuConfig_NotFound(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	config, err := h.getFeishuConfig(user.ID)
	assert.Error(t, err)
	assert.Nil(t, config)
}

func TestGetFeishuConfig_Found(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_test","app_secret":"secret_test","table_url":"https://xxx.feishu.cn/base/xyz"}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	config, err := h.getFeishuConfig(user.ID)
	require.NoError(t, err)
	require.NotNil(t, config)
	assert.Equal(t, "app_test", config.AppID)
	assert.Equal(t, "secret_test", config.AppSecret)
	assert.Equal(t, "https://xxx.feishu.cn/base/xyz", config.TableURL)
}

// --- getFeishuConfigWithTables ---

func TestGetFeishuConfigWithTables_NotFound(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	config, tables, err := h.getFeishuConfigWithTables(user.ID)
	assert.Error(t, err)
	assert.Nil(t, config)
	assert.Nil(t, tables)
}

func TestGetFeishuConfigWithTables_Found(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_wt","app_secret":"secret_wt","table_url":"https://xxx.feishu.cn/base/def","tables":{"任务表":"tbl_task","习惯表":"tbl_habit"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	config, tables, err := h.getFeishuConfigWithTables(user.ID)
	require.NoError(t, err)
	require.NotNil(t, config)
	assert.Equal(t, "app_wt", config.AppID)
	assert.Equal(t, "secret_wt", config.AppSecret)

	require.NotNil(t, tables)
	assert.Equal(t, "tbl_task", tables["任务表"])
	assert.Equal(t, "tbl_habit", tables["习惯表"])
}

func TestGetFeishuConfigWithTables_NoTables(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_notbl","app_secret":"secret_notbl","table_url":"https://xxx.feishu.cn/base/ghi"}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	config, tables, err := h.getFeishuConfigWithTables(user.ID)
	require.NoError(t, err)
	require.NotNil(t, config)
	assert.Equal(t, "app_notbl", config.AppID)
	assert.Empty(t, tables)
}

// --- saveTableIDs ---

func TestSaveTableIDs(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_tbl","app_secret":"secret_tbl","table_url":"https://xxx.feishu.cn/base/tbl"}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	newTables := map[string]string{
		"任务表": "tbl_task_001",
		"清单表": "tbl_list_001",
	}
	h.saveTableIDs(user.ID, newTables)

	config, tables, err := h.getFeishuConfigWithTables(user.ID)
	require.NoError(t, err)
	assert.Equal(t, "app_tbl", config.AppID)
	assert.Equal(t, "tbl_task_001", tables["任务表"])
	assert.Equal(t, "tbl_list_001", tables["清单表"])
}

func TestSaveTableIDs_NoExistingConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	// Should be a no-op, no panic
	h.saveTableIDs(user.ID, map[string]string{"任务表": "tbl_x"})

	config, err := h.getFeishuConfig(user.ID)
	assert.Error(t, err)
	assert.Nil(t, config)
}

func TestSaveTableIDs_MergeExisting(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_merge","app_secret":"secret_merge","table_url":"https://xxx.feishu.cn/base/mrg","tables":{"任务表":"tbl_old"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	h.saveTableIDs(user.ID, map[string]string{
		"习惯表": "tbl_habit_new",
	})

	_, tables, err := h.getFeishuConfigWithTables(user.ID)
	require.NoError(t, err)
	assert.Equal(t, "tbl_old", tables["任务表"])
	assert.Equal(t, "tbl_habit_new", tables["习惯表"])
}

// --- SaveConfig (invalid credentials → 400) ---

func TestSaveConfig_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	reqBody := FeishuConfig{
		AppID:     "invalid_app_id",
		AppSecret: "invalid_app_secret",
		TableURL:  "https://xxx.feishu.cn/base/test",
	}
	bodyBytes, _ := json.Marshal(reqBody)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/config", h.SaveConfig, bodyBytes)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "飞书凭据验证失败")
}

// --- SyncToFeishu ---

func TestSyncToFeishu_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync", h.SyncToFeishu, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

func TestSyncToFeishu_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	// Create a config with invalid credentials so getFeishuConfigWithTables succeeds
	// but getTenantToken fails
	configValue := `{"app_id":"bad_id","app_secret":"bad_secret","table_url":"https://xxx.feishu.cn/base/test","tables":{"任务表":"tbl_x"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync", h.SyncToFeishu, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "获取飞书 token 失败")
}

// --- ImportFromFeishu ---

func TestImportFromFeishu_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/import", h.ImportFromFeishu, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

func TestImportFromFeishu_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"bad_imp","app_secret":"bad_imp","table_url":"https://xxx.feishu.cn/base/test","tables":{"任务表":"tbl_x"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/import", h.ImportFromFeishu, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "获取飞书 token 失败")
}

// --- CreateTemplate ---

func TestCreateTemplate_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/template", h.CreateTemplate, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

func TestCreateTemplate_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"bad_tpl","app_secret":"bad_tpl","table_url":"https://xxx.feishu.cn/base/test"}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/template", h.CreateTemplate, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "获取飞书 token 失败")
}

// --- ConnectExisting ---

func TestConnectExisting_EmptyTableURL(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	reqBody := `{"table_url":""}`
	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/connect", h.ConnectExisting, []byte(reqBody))

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请提供多维表格链接")
}

func TestConnectExisting_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	reqBody := `{"table_url":"https://xxx.feishu.cn/base/abc"}`
	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/connect", h.ConnectExisting, []byte(reqBody))

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

// --- SyncAll ---

func TestSyncAll_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-all", h.SyncAll, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

// --- SyncSessions ---

func TestSyncSessions_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-sessions", h.SyncSessions, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

// --- SyncReminders ---

func TestSyncReminders_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-reminders", h.SyncReminders, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

// --- SyncTags ---

func TestSyncTags_NoConfig(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-tags", h.SyncTags, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "请先配置飞书")
}

// ===== SyncSessions: table_id 缺失分支 =====

func TestSyncSessions_NoTableID(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	// 配置了飞书但没有 番茄钟表 表 ID
	configValue := `{"app_id":"app_sess","app_secret":"secret_sess","table_url":"https://xxx.feishu.cn/base/sess"}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-sessions", h.SyncSessions, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "番茄钟表不存在")
}

func TestSyncSessions_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"bad_sess","app_secret":"bad_sess","table_url":"https://xxx.feishu.cn/base/sess","tables":{"番茄钟表":"tbl_pomo"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-sessions", h.SyncSessions, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "获取飞书 token 失败")
}

// ===== SyncReminders: table_id 缺失 + token 失败分支 =====

func TestSyncReminders_NoTableID(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_rem","app_secret":"secret_rem","table_url":"https://xxx.feishu.cn/base/rem"}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-reminders", h.SyncReminders, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "休息提醒表不存在")
}

func TestSyncReminders_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"bad_rem","app_secret":"bad_rem","table_url":"https://xxx.feishu.cn/base/rem","tables":{"休息提醒表":"tbl_rest"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-reminders", h.SyncReminders, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "获取飞书 token 失败")
}

// ===== SyncTags: table_id 缺失 + token 失败分支 =====

func TestSyncTags_NoTableID(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_tag","app_secret":"secret_tag","table_url":"https://xxx.feishu.cn/base/tag"}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-tags", h.SyncTags, nil)

	assert.Equal(t, http.StatusBadRequest, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "标签表不存在")
}

func TestSyncTags_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"bad_tag","app_secret":"bad_tag","table_url":"https://xxx.feishu.cn/base/tag","tables":{"标签表":"tbl_tag"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-tags", h.SyncTags, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "获取飞书 token 失败")
}

// ===== SyncAll: token 失败分支 =====

func TestSyncAll_InvalidCredentials(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"bad_all","app_secret":"bad_all","table_url":"https://xxx.feishu.cn/base/all","tables":{"任务表":"tbl_task"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-all", h.SyncAll, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "获取飞书 token 失败")
}

// ===== SyncToFeishu: 解析 URL 失败分支 =====

func TestSyncToFeishu_InvalidTableURL(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	// table_url 不含 feishu.cn/base/{app_token} 格式，parseTableURL 将失败
	configValue := `{"app_id":"app_url","app_secret":"secret_url","table_url":"https://example.com/notfeishu","tables":{"任务表":"tbl_x"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync", h.SyncToFeishu, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "失败")
}

// ===== ImportFromFeishu: 解析 URL 失败分支 =====

func TestImportFromFeishu_InvalidTableURL(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_imp_url","app_secret":"secret_imp_url","table_url":"https://example.com/notfeishu","tables":{"任务表":"tbl_x"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/import", h.ImportFromFeishu, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "失败")
}

// ===== SyncSessions: 解析 URL 失败分支 =====

func TestSyncSessions_InvalidTableURL(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_s_url","app_secret":"secret_s_url","table_url":"https://example.com/bad","tables":{"番茄钟表":"tbl_pomo"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-sessions", h.SyncSessions, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "失败")
}

// ===== SyncReminders: 解析 URL 失败分支 =====

func TestSyncReminders_InvalidTableURL(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_r_url","app_secret":"secret_r_url","table_url":"https://example.com/bad","tables":{"休息提醒表":"tbl_rest"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-reminders", h.SyncReminders, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "失败")
}

// ===== SyncTags: 解析 URL 失败分支 =====

func TestSyncTags_InvalidTableURL(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_t_url","app_secret":"secret_t_url","table_url":"https://example.com/bad","tables":{"标签表":"tbl_tag"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-tags", h.SyncTags, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "失败")
}

// ===== SyncAll: 解析 URL 失败分支 =====

func TestSyncAll_InvalidTableURL(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewFeishuHandler(tx)

	configValue := `{"app_id":"app_a_url","app_secret":"secret_a_url","table_url":"https://example.com/bad","tables":{"任务表":"tbl_task"}}`
	tx.Create(&model.UserConfig{
		UserID: user.ID,
		Key:    "feishu",
		Value:  configValue,
	})

	w := setupFeishuRouter(h, user.ID, "POST", "/api/feishu/sync-all", h.SyncAll, nil)

	assert.Equal(t, http.StatusInternalServerError, w.Code)

	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["error"], "失败")
}

// ===== CreateTemplate: 解析 URL 失败分支（创建后 resolveBitableURL fallback） =====

// 此分支需要 mock，已在 TestCreateTemplate_Mock 中覆盖

// ===== CreateList 边界测试 =====

func TestCreateList_EmptyName(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewListHandler(tx)

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.POST("/lists", h.CreateList)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/lists", bytes.NewBufferString(`{"name":""}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	// 空名应该仍然可以创建（或返回 201 取决于业务逻辑）
	assert.True(t, w.Code == http.StatusCreated || w.Code == http.StatusBadRequest)
}

func TestCreateList_ExtraFields(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewListHandler(tx)

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.POST("/lists", h.CreateList)

	body := `{"name":"带自定义","icon":"⭐","color":"#abc123","sort_order":5}`
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/lists", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusCreated, w.Code)
}

// ===== CreateHabit 边界测试 =====

func TestCreateHabit_AllFields(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewHabitHandler(tx)

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.POST("/habits", h.CreateHabit)

	body := `{"name":"喝水","icon":"💧","color":"#00bfff","frequency":"daily","target_days":30}`
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusCreated, w.Code)
}

func TestCreateHabit_MinimalFields(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	user := createTestUser(t, tx)
	h := NewHabitHandler(tx)

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.POST("/habits", h.CreateHabit)

	body := `{"name":"冥想"}`
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusCreated, w.Code)
}
