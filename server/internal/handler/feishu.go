package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
	"slowlight/internal/secureconfig"
)

type FeishuHandler struct {
	DB *gorm.DB
}

func NewFeishuHandler(db *gorm.DB) *FeishuHandler {
	return &FeishuHandler{DB: db}
}

// FeishuConfig 飞书配置
type FeishuConfig struct {
	AppID     string `json:"app_id"`
	AppSecret string `json:"app_secret"`
	TableURL  string `json:"table_url"` // 飞书多维表格链接
}

// FeishuToken 飞书 Token 响应
type FeishuToken struct {
	Code              int    `json:"code"`
	Msg               string `json:"msg"`
	TenantAccessToken string `json:"tenant_access_token"`
	Expire            int    `json:"expire"`
}

// GetConfig 获取飞书配置
func (h *FeishuHandler) GetConfig(c *gin.Context) {
	userID := c.GetUint("userID")
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "feishu").First(&config)

	if config.ID == 0 {
		c.JSON(http.StatusOK, gin.H{"configured": false})
		return
	}

	var raw map[string]interface{}
	json.Unmarshal([]byte(config.Value), &raw)

	// 提取各字段（不返回 app_secret）
	resp := gin.H{
		"configured": true,
		"app_id":     raw["app_id"],
		"table_url":  raw["table_url"],
	}

	// 返回 tables 信息用于排查
	if tables, ok := raw["tables"].(map[string]interface{}); ok && len(tables) > 0 {
		resp["tables"] = tables
	}

	c.JSON(http.StatusOK, resp)
}

// SaveConfig 保存飞书配置
func (h *FeishuHandler) SaveConfig(c *gin.Context) {
	userID := c.GetUint("userID")
	var req FeishuConfig
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 验证飞书凭据
	token, err := h.getTenantToken(req.AppID, req.AppSecret)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "飞书凭据验证失败: " + err.Error()})
		return
	}

	// 读取已有配置，保留 tables 等字段不被覆盖
	var existingConfig model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "feishu").First(&existingConfig)

	var merged map[string]interface{}
	if existingConfig.ID != 0 {
		json.Unmarshal([]byte(existingConfig.Value), &merged)
	} else {
		merged = map[string]interface{}{}
	}

	// 只更新用户提交的字段，不覆盖 tables
	encryptedSecret, err := secureconfig.Encrypt(req.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法安全保存凭据: " + err.Error()})
		return
	}
	merged["app_id"] = req.AppID
	merged["app_secret"] = encryptedSecret
	if req.TableURL != "" {
		merged["table_url"] = req.TableURL
	}

	configJSON, _ := json.Marshal(merged)
	existingConfig.UserID = userID
	existingConfig.Key = "feishu"
	existingConfig.Value = string(configJSON)

	if existingConfig.ID == 0 {
		h.DB.Create(&existingConfig)
	} else {
		h.DB.Save(&existingConfig)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "配置保存成功",
		"configured": true,
		"token":      token[:20] + "...",
	})
}

// SyncToFeishu 同步任务到飞书
func (h *FeishuHandler) SyncToFeishu(c *gin.Context) {
	userID := c.GetUint("userID")

	config, tables, err := h.getFeishuConfigWithTables(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败"})
		return
	}

	// 获取用户的任务
	var tasks []model.Task
	h.DB.Preload("List").Where("user_id = ?", userID).Find(&tasks)

	// 从保存的表 ID 中获取任务表
	appToken, tableID, err := h.parseTableURL(token, config.TableURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解析多维表格失败: " + err.Error()})
		return
	}

	// 优先使用保存的任务表 ID
	if savedTableID := tables["任务表"]; savedTableID != "" {
		tableID = savedTableID
	}

	// 同步每个任务
	synced := 0
	var lastErr error
	for _, task := range tasks {
		fields := map[string]interface{}{
			"标题":   task.Title,
			"描述":   task.Description,
			"清单":   task.List.Name,
			"完成":   task.IsCompleted,
			"优先级":  priorityText(task.Priority),
			"创建时间": task.CreatedAt.UnixMilli(),
		}
		if task.DueDate != nil {
			fields["截止日期"] = task.DueDate.UnixMilli()
		}
		if task.CompletedAt != nil {
			fields["完成时间"] = task.CompletedAt.UnixMilli()
		}

		err := h.createRecord(token, appToken, tableID, fields)
		if err == nil {
			synced++
		} else {
			lastErr = err
			log.Printf("[SyncToFeishu] createRecord failed: %v, task: %s", err, task.Title)
		}
	}

	if synced == 0 && lastErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("同步失败: %v", lastErr)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("同步完成，共 %d 条任务", synced),
		"synced":  synced,
		"total":   len(tasks),
	})
}

// ImportFromFeishu 从飞书导入任务
func (h *FeishuHandler) ImportFromFeishu(c *gin.Context) {
	userID := c.GetUint("userID")

	config, tables, err := h.getFeishuConfigWithTables(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败"})
		return
	}

	appToken, tableID, err := h.parseTableURL(token, config.TableURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解析多维表格失败: " + err.Error()})
		return
	}

	// 优先使用保存的任务表 ID
	if savedTableID := tables["任务表"]; savedTableID != "" {
		tableID = savedTableID
	}

	// 获取飞书记录
	records, err := h.listRecords(token, appToken, tableID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书记录失败: " + err.Error()})
		return
	}

	// 获取用户的默认清单
	var defaultList model.List
	h.DB.Where("user_id = ?", userID).Order("sort_order ASC").First(&defaultList)

	// 导入记录
	imported := 0
	for _, record := range records {
		fields, ok := record["fields"].(map[string]interface{})
		if !ok {
			continue
		}

		title, _ := fields["标题"].(string)
		if title == "" {
			continue
		}

		// 查找或创建清单
		listName, _ := fields["清单"].(string)
		var list model.List
		if listName != "" {
			h.DB.Where("user_id = ? AND name = ?", userID, listName).First(&list)
			if list.ID == 0 {
				list = model.List{UserID: userID, Name: listName, Icon: "📋", Color: "#1890ff"}
				h.DB.Create(&list)
			}
		} else {
			list = defaultList
		}

		desc, _ := fields["描述"].(string)
		completed, _ := fields["完成"].(bool)

		task := model.Task{
			UserID:      userID,
			ListID:      list.ID,
			Title:       title,
			Description: desc,
			IsCompleted: completed,
		}
		h.DB.Create(&task)
		imported++
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  fmt.Sprintf("导入完成，共 %d 条任务", imported),
		"imported": imported,
	})
}

// ===== 飞书 API 方法 =====

func (h *FeishuHandler) getTenantToken(appID, appSecret string) (string, error) {
	url := "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"
	body := map[string]string{
		"app_id":     appID,
		"app_secret": appSecret,
	}
	bodyJSON, _ := json.Marshal(body)

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(bodyJSON))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var tokenResp FeishuToken
	json.NewDecoder(resp.Body).Decode(&tokenResp)

	if tokenResp.Code != 0 {
		return "", fmt.Errorf("飞书认证失败: %s", tokenResp.Msg)
	}

	return tokenResp.TenantAccessToken, nil
}

// parseTableURL 从飞书多维表格 URL 中解析 app_token
// 支持格式：
//
//	https://xxx.feishu.cn/base/{app_token}
//	https://xxx.feishu.cn/base/{app_token}?table={table_id}
//	https://xxx.feishu.cn/wiki/{app_token}
//	https://xxx.feishu.cn/wiki/{space_id}/{node_token}
//	https://xxx.feishu.cn/drive/folder/{app_token}
func (h *FeishuHandler) parseTableURL(token, tableURL string) (appToken, tableID string, err error) {
	// 先尝试 wiki/{a}/{b} 格式（两段路径，app_token 是第二段）
	re2 := regexp.MustCompile(`feishu\.(cn|com)/wiki/([a-zA-Z0-9]+)/([a-zA-Z0-9]+)`)
	m2 := re2.FindStringSubmatch(tableURL)
	if len(m2) >= 4 {
		appToken = m2[3] // 第二段是 node_token，即真正的 app_token
	} else {
		// 回退：单段格式 /base/{token} 或 /wiki/{token} 或 /drive/folder/{token}
		re1 := regexp.MustCompile(`feishu\.(cn|com)/(?:base|wiki|drive/folder)/([a-zA-Z0-9]+)`)
		m1 := re1.FindStringSubmatch(tableURL)
		if len(m1) < 3 {
			return "", "", fmt.Errorf("无法从 URL 解析 app_token，请检查链接格式: %s", tableURL)
		}
		appToken = m1[2]
	}

	// 尝试从 URL 的 ?table= 参数提取 table_id
	tableRe := regexp.MustCompile(`[?&]table=([a-zA-Z0-9]+)`)
	tableMatches := tableRe.FindStringSubmatch(tableURL)
	if len(tableMatches) >= 2 {
		tableID = tableMatches[1]
	}

	// 如果没有 table_id，获取第一个数据表的 ID
	if tableID == "" {
		tableID, err = h.getFirstTableID(token, appToken)
		if err != nil {
			return appToken, "", fmt.Errorf("app_token 解析成功，但获取数据表失败: %v", err)
		}
	}

	return appToken, tableID, nil
}

// getFirstTableID 获取多维表格中第一个数据表的 ID
func (h *FeishuHandler) getFirstTableID(token, appToken string) (string, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables?page_size=1", appToken)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []struct {
				TableID string `json:"table_id"`
			} `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return "", fmt.Errorf("获取数据表列表失败，code: %d", result.Code)
	}
	if len(result.Data.Items) == 0 {
		return "", fmt.Errorf("多维表格中没有数据表")
	}

	return result.Data.Items[0].TableID, nil
}

func (h *FeishuHandler) createRecord(token, appToken, tableID string, fields map[string]interface{}) error {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records", appToken, tableID)
	body := map[string]interface{}{"fields": fields}
	bodyJSON, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	var result struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		log.Printf("[createRecord] appToken=%s tableID=%s code=%d msg=%s", appToken, tableID, result.Code, result.Msg)
		return fmt.Errorf("创建记录失败: %s (code: %d)", result.Msg, result.Code)
	}
	return nil
}

func (h *FeishuHandler) listRecords(token, appToken, tableID string) ([]map[string]interface{}, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records?page_size=500", appToken, tableID)

	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []map[string]interface{} `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return nil, fmt.Errorf("获取记录失败，code: %d", result.Code)
	}
	return result.Data.Items, nil
}

func (h *FeishuHandler) getFeishuConfig(userID uint) (*FeishuConfig, error) {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "feishu").First(&config)
	if config.ID == 0 {
		return nil, fmt.Errorf("未配置飞书")
	}

	var feishuConfig FeishuConfig
	if err := json.Unmarshal([]byte(config.Value), &feishuConfig); err != nil {
		return nil, fmt.Errorf("飞书配置格式无效: %w", err)
	}
	decryptedSecret, err := secureconfig.Decrypt(feishuConfig.AppSecret)
	if err != nil {
		return nil, fmt.Errorf("读取飞书凭据失败: %w", err)
	}
	feishuConfig.AppSecret = decryptedSecret
	return &feishuConfig, nil
}

func priorityText(priority string) string {
	switch priority {
	case "high":
		return "高"
	case "medium":
		return "中"
	case "low":
		return "低"
	default:
		return "无"
	}
}

// ===== 批量操作 =====

// SyncAll 一键同步所有数据到飞书
func (h *FeishuHandler) SyncAll(c *gin.Context) {
	userID := c.GetUint("userID")

	config, tables, err := h.getFeishuConfigWithTables(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败"})
		return
	}

	appToken, _, err := h.parseTableURL(token, config.TableURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解析多维表格失败: " + err.Error()})
		return
	}

	results := map[string]int{}
	errors := []string{}

	// 1. 同步任务
	if tableID := tables["任务表"]; tableID != "" {
		var tasks []model.Task
		h.DB.Preload("List").Where("user_id = ?", userID).Find(&tasks)
		records := make([]map[string]interface{}, 0, len(tasks))
		for _, task := range tasks {
			fields := map[string]interface{}{
				"标题":   task.Title,
				"描述":   task.Description,
				"清单":   task.List.Name,
				"完成":   task.IsCompleted,
				"优先级":  priorityText(task.Priority),
				"创建时间": task.CreatedAt.UnixMilli(),
			}
			if task.DueDate != nil {
				fields["截止日期"] = task.DueDate.UnixMilli()
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := h.batchCreateRecords(token, appToken, tableID, records); err != nil {
			errors = append(errors, "任务表: "+err.Error())
		} else {
			results["任务表"] = len(records)
		}
	}

	// 2. 同步番茄钟
	if tableID := tables["番茄钟表"]; tableID != "" {
		var sessions []model.WorkSession
		h.DB.Where("user_id = ?", userID).Order("started_at ASC").Find(&sessions)
		records := make([]map[string]interface{}, 0, len(sessions))
		for _, s := range sessions {
			typeName := "工作"
			switch s.SessionType {
			case "break":
				typeName = "短休息"
			case "long_break":
				typeName = "长休息"
			}
			fields := map[string]interface{}{
				"类型":    typeName,
				"开始时间":  s.StartedAt.UnixMilli(),
				"时长(秒)": s.DurationSec,
				"设备":    s.Device,
			}
			if s.EndedAt != nil {
				fields["结束时间"] = s.EndedAt.UnixMilli()
			}
			if s.TaskID != nil {
				fields["关联任务ID"] = *s.TaskID
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := h.batchCreateRecords(token, appToken, tableID, records); err != nil {
			errors = append(errors, "番茄钟表: "+err.Error())
		} else {
			results["番茄钟表"] = len(records)
		}
	}

	// 3. 同步休息提醒
	if tableID := tables["休息提醒表"]; tableID != "" {
		var sessions []model.ReminderSession
		h.DB.Where("user_id = ? AND rest_ended_at IS NOT NULL", userID).Order("started_at ASC").Find(&sessions)
		records := make([]map[string]interface{}, 0, len(sessions))
		for _, s := range sessions {
			fields := map[string]interface{}{
				"开始时间":    s.StartedAt.UnixMilli(),
				"工作时长(秒)": s.WorkSeconds,
				"休息时长(秒)": s.RestSeconds,
				"跳过休息":    s.SkippedRest,
				"设备":      s.Device,
			}
			if s.WorkEndedAt != nil {
				fields["工作结束"] = s.WorkEndedAt.UnixMilli()
			}
			if s.RestEndedAt != nil {
				fields["休息结束"] = s.RestEndedAt.UnixMilli()
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := h.batchCreateRecords(token, appToken, tableID, records); err != nil {
			errors = append(errors, "休息提醒表: "+err.Error())
		} else {
			results["休息提醒表"] = len(records)
		}
	}

	// 4. 同步标签
	if tableID := tables["标签表"]; tableID != "" {
		var tags []model.Tag
		h.DB.Where("user_id = ?", userID).Find(&tags)
		records := make([]map[string]interface{}, 0, len(tags))
		for _, t := range tags {
			var count int64
			h.DB.Table("task_tags").Joins("JOIN tasks ON tasks.id = task_tags.task_id").
				Where("task_tags.tag_id = ? AND tasks.user_id = ?", t.ID, userID).Count(&count)
			fields := map[string]interface{}{
				"名称":    t.Name,
				"颜色":    t.Color,
				"关联任务数": count,
			}
			records = append(records, map[string]interface{}{"fields": fields})
		}
		if err := h.batchCreateRecords(token, appToken, tableID, records); err != nil {
			errors = append(errors, "标签表: "+err.Error())
		} else {
			results["标签表"] = len(records)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "全部同步完成",
		"results": results,
		"errors":  errors,
	})
}

func (h *FeishuHandler) batchCreateRecords(token, appToken, tableID string, records []map[string]interface{}) error {
	if len(records) == 0 {
		return nil
	}
	// 飞书批量接口上限 500 条
	for i := 0; i < len(records); i += 500 {
		end := i + 500
		if end > len(records) {
			end = len(records)
		}
		batch := records[i:end]

		url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/records/batch_create", appToken, tableID)
		body := map[string]interface{}{"records": batch}
		bodyJSON, _ := json.Marshal(body)

		req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return err
		}
		resp.Body.Close()

		var result struct {
			Code int `json:"code"`
		}
		json.NewDecoder(resp.Body).Decode(&result)
		if result.Code != 0 {
			return fmt.Errorf("批量创建记录失败，code: %d", result.Code)
		}
	}
	return nil
}

// getFeishuConfigWithTables 获取飞书配置，包含各表 ID
func (h *FeishuHandler) getFeishuConfigWithTables(userID uint) (*FeishuConfig, map[string]string, error) {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "feishu").First(&config)
	if config.ID == 0 {
		return nil, nil, fmt.Errorf("未配置飞书")
	}

	var raw map[string]interface{}
	json.Unmarshal([]byte(config.Value), &raw)

	var feishuConfig FeishuConfig
	if err := json.Unmarshal([]byte(config.Value), &feishuConfig); err != nil {
		return nil, nil, fmt.Errorf("飞书配置格式无效: %w", err)
	}
	var err error
	feishuConfig.AppSecret, err = secureconfig.Decrypt(feishuConfig.AppSecret)
	if err != nil {
		return nil, nil, fmt.Errorf("读取飞书凭据失败: %w", err)
	}

	tables := map[string]string{}
	if ts, ok := raw["tables"].(map[string]interface{}); ok {
		for k, v := range ts {
			if s, ok := v.(string); ok {
				tables[k] = s
			}
		}
	}

	return &feishuConfig, tables, nil
}

// saveTableIDs 保存表 ID 到用户飞书配置
func (h *FeishuHandler) saveTableIDs(userID uint, newTables map[string]string) {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "feishu").First(&config)
	if config.ID == 0 {
		return
	}

	var raw map[string]interface{}
	json.Unmarshal([]byte(config.Value), &raw)

	tables, _ := raw["tables"].(map[string]interface{})
	if tables == nil {
		tables = map[string]interface{}{}
	}
	for k, v := range newTables {
		tables[k] = v
	}
	raw["tables"] = tables

	configJSON, _ := json.Marshal(raw)
	config.Value = string(configJSON)
	h.DB.Save(&config)
}

// ===== 多维表格模板创建 =====

// BitableField 多维表格字段定义
type BitableField struct {
	FieldName string      `json:"field_name"`
	Type      int         `json:"type"`
	Property  interface{} `json:"property,omitempty"`
}

// CreateTemplate 创建飞书多维表格模板
func (h *FeishuHandler) CreateTemplate(c *gin.Context) {
	userID := c.GetUint("userID")
	log.Printf("[CreateTemplate] userID=%d", userID)

	// 获取飞书配置
	config, err := h.getFeishuConfig(userID)
	if err != nil {
		log.Printf("[CreateTemplate] getFeishuConfig error: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败"})
		return
	}

	// 创建多维表格
	appToken, err := h.createBitable(token, "所行映我数据")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建多维表格失败: " + err.Error()})
		return
	}

	// 定义任务表字段
	taskFields := []BitableField{
		{FieldName: "标题", Type: 1}, // 文本, 必填
		{FieldName: "描述", Type: 1}, // 文本
		{FieldName: "清单", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
			{"name": "工作"}, {"name": "生活"}, {"name": "学习"},
		}}}, // 单选
		{FieldName: "优先级", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
			{"name": "高"}, {"name": "中"}, {"name": "低"}, {"name": "无"},
		}}}, // 单选
		{FieldName: "状态", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
			{"name": "进行中"}, {"name": "已完成"},
		}}}, // 单选
		{FieldName: "截止日期", Type: 5},    // 日期
		{FieldName: "创建时间", Type: 1001}, // 创建时间, 自动
		{FieldName: "标签", Type: 4},      // 多选
	}

	// 定义清单表字段
	listFields := []BitableField{
		{FieldName: "名称", Type: 1}, // 文本
		{FieldName: "颜色", Type: 1}, // 文本
		{FieldName: "图标", Type: 1}, // 文本
		{FieldName: "排序", Type: 2}, // 数字
	}

	// 定义习惯表字段
	habitFields := []BitableField{
		{FieldName: "名称", Type: 1}, // 文本
		{FieldName: "图标", Type: 1}, // 文本
		{FieldName: "颜色", Type: 1}, // 文本
		{FieldName: "频率", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
			{"name": "每天"}, {"name": "每周"}, {"name": "每月"},
		}}}, // 单选
		{FieldName: "连续天数", Type: 2}, // 数字
		{FieldName: "目标天数", Type: 2}, // 数字
	}

	// 创建3个数据表
	taskTableID, err := h.createTable(token, appToken, "任务表", "全部任务", taskFields)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建任务表失败: " + err.Error()})
		return
	}

	listTableID, err := h.createTable(token, appToken, "清单表", "全部清单", listFields)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建清单表失败: " + err.Error()})
		return
	}

	habitTableID, err := h.createTable(token, appToken, "习惯表", "全部习惯", habitFields)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建习惯表失败: " + err.Error()})
		return
	}

	// 定义番茄钟表字段
	sessionFields := []BitableField{
		{FieldName: "类型", Type: 3, Property: map[string]interface{}{"options": []map[string]interface{}{
			{"name": "工作"}, {"name": "短休息"}, {"name": "长休息"},
		}}}, // 单选
		{FieldName: "开始时间", Type: 5},   // 日期
		{FieldName: "结束时间", Type: 5},   // 日期
		{FieldName: "时长(秒)", Type: 2},  // 数字
		{FieldName: "设备", Type: 1},     // 文本
		{FieldName: "关联任务ID", Type: 2}, // 数字
	}

	// 定义休息提醒表字段
	reminderFields := []BitableField{
		{FieldName: "开始时间", Type: 5},    // 日期
		{FieldName: "工作结束", Type: 5},    // 日期
		{FieldName: "休息结束", Type: 5},    // 日期
		{FieldName: "工作时长(秒)", Type: 2}, // 数字
		{FieldName: "休息时长(秒)", Type: 2}, // 数字
		{FieldName: "跳过休息", Type: 7},    // 复选框
		{FieldName: "设备", Type: 1},      // 文本
	}

	// 定义标签表字段
	tagFields := []BitableField{
		{FieldName: "名称", Type: 1},    // 文本
		{FieldName: "颜色", Type: 1},    // 文本
		{FieldName: "关联任务数", Type: 2}, // 数字
	}

	// 创建 3 张新表
	sessionTableID, err := h.createTable(token, appToken, "番茄钟表", "全部记录", sessionFields)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建番茄钟表失败: " + err.Error()})
		return
	}

	reminderTableID, err := h.createTable(token, appToken, "休息提醒表", "全部记录", reminderFields)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建休息提醒表失败: " + err.Error()})
		return
	}

	tagTableID, err := h.createTable(token, appToken, "标签表", "全部标签", tagFields)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建标签表失败: " + err.Error()})
		return
	}

	// 保存所有表 ID
	tableIDMap := map[string]string{
		"任务表":   taskTableID,
		"清单表":   listTableID,
		"习惯表":   habitTableID,
		"番茄钟表":  sessionTableID,
		"休息提醒表": reminderTableID,
		"标签表":   tagTableID,
	}
	h.saveTableIDs(userID, tableIDMap)

	// 查询真实的多维表格 URL（通过 app_token 获取元信息）
	bitableURL := h.resolveBitableURL(token, appToken, taskTableID)

	// 更新用户的飞书配置，保存 table_url
	var userConfig model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "feishu").First(&userConfig)
	if userConfig.ID != 0 {
		var feishuConfig FeishuConfig
		json.Unmarshal([]byte(userConfig.Value), &feishuConfig)
		feishuConfig.TableURL = bitableURL
		configJSON, _ := json.Marshal(feishuConfig)
		userConfig.Value = string(configJSON)
		h.DB.Save(&userConfig)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "多维表格模板创建成功",
		"app_token":   appToken,
		"bitable_url": bitableURL,
		"tables":      tableIDMap,
	})
}

// ConnectExisting 绑定已有的飞书多维表格
func (h *FeishuHandler) ConnectExisting(c *gin.Context) {
	userID := c.GetUint("userID")

	var req struct {
		TableURL string `json:"table_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.TableURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请提供多维表格链接"})
		return
	}

	// 获取飞书配置
	config, _, err := h.getFeishuConfigWithTables(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书 App ID 和 Secret"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败: " + err.Error()})
		return
	}

	// 解析 app_token
	appToken, _, err := h.parseTableURL(token, req.TableURL)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无法解析表格链接: " + err.Error()})
		return
	}

	// 获取所有数据表
	tables, err := h.listBitableTables(token, appToken)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取数据表列表失败: " + err.Error()})
		return
	}

	if len(tables) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "该多维表格中没有数据表"})
		return
	}

	// 自动识别每张表的类型（通过字段名匹配）
	tableIDMap := map[string]string{}
	tableDetails := []map[string]interface{}{}
	for _, table := range tables {
		detail := map[string]interface{}{
			"table_id":    table.TableID,
			"name":        table.Name,
			"field_count": len(table.Fields),
		}
		tableDetails = append(tableDetails, detail)

		// 通过字段名自动匹配表类型
		fieldNames := map[string]bool{}
		for _, f := range table.Fields {
			fieldNames[f.FieldName] = true
		}

		switch {
		case fieldNames["标题"] && fieldNames["清单"]:
			tableIDMap["任务表"] = table.TableID
		case fieldNames["名称"] && fieldNames["颜色"] && fieldNames["图标"] && !fieldNames["频率"]:
			tableIDMap["清单表"] = table.TableID
		case fieldNames["名称"] && fieldNames["频率"]:
			tableIDMap["习惯表"] = table.TableID
		case fieldNames["类型"] && fieldNames["开始时间"] && fieldNames["时长(秒)"]:
			tableIDMap["番茄钟表"] = table.TableID
		case fieldNames["工作结束"] || (fieldNames["工作时长(秒)"] && fieldNames["休息时长(秒)"]):
			tableIDMap["休息提醒表"] = table.TableID
		case fieldNames["关联任务数"]:
			tableIDMap["标签表"] = table.TableID
		}
	}

	// 保存配置：table_url + tables
	var existingConfig model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "feishu").First(&existingConfig)

	var merged map[string]interface{}
	if existingConfig.ID != 0 {
		json.Unmarshal([]byte(existingConfig.Value), &merged)
	} else {
		merged = map[string]interface{}{}
	}
	merged["table_url"] = req.TableURL
	merged["tables"] = tableIDMap

	configJSON, _ := json.Marshal(merged)
	existingConfig.UserID = userID
	existingConfig.Key = "feishu"
	existingConfig.Value = string(configJSON)
	if existingConfig.ID == 0 {
		h.DB.Create(&existingConfig)
	} else {
		h.DB.Save(&existingConfig)
	}

	log.Printf("[ConnectExisting] userID=%d appToken=%s tables=%v", userID, appToken, tableIDMap)

	c.JSON(http.StatusOK, gin.H{
		"message":    "绑定成功",
		"app_token":  appToken,
		"table_url":  req.TableURL,
		"tables":     tableIDMap,
		"all_tables": tableDetails,
	})
}

// bitableTableInfo 数据表信息
type bitableTableInfo struct {
	TableID string `json:"table_id"`
	Name    string `json:"name"`
	Fields  []struct {
		FieldName string `json:"field_name"`
		Type      int    `json:"type"`
	} `json:"fields"`
}

// listBitableTables 获取多维表格中所有数据表及其字段
func (h *FeishuHandler) listBitableTables(token, appToken string) ([]bitableTableInfo, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables?page_size=100", appToken)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []bitableTableInfo `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return nil, fmt.Errorf("获取表列表失败，code: %d", result.Code)
	}

	// 为每个表获取字段列表
	for i := range result.Data.Items {
		h.fillTableFields(token, appToken, &result.Data.Items[i])
	}

	return result.Data.Items, nil
}

// fillTableFields 获取单个数据表的字段列表
func (h *FeishuHandler) fillTableFields(token, appToken string, table *bitableTableInfo) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables/%s/fields?page_size=100", appToken, table.TableID)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			Items []struct {
				FieldName string `json:"field_name"`
				Type      int    `json:"type"`
			} `json:"items"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code == 0 {
		table.Fields = result.Data.Items
	}
}

// SyncSessions 同步番茄钟记录到飞书
func (h *FeishuHandler) SyncSessions(c *gin.Context) {
	userID := c.GetUint("userID")

	config, tables, err := h.getFeishuConfigWithTables(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书"})
		return
	}
	tableID := tables["番茄钟表"]
	if tableID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "番茄钟表不存在，请重新创建模板"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败"})
		return
	}

	appToken, _, err := h.parseTableURL(token, config.TableURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解析多维表格失败: " + err.Error()})
		return
	}

	var sessions []model.WorkSession
	h.DB.Where("user_id = ?", userID).Order("started_at ASC").Find(&sessions)

	records := make([]map[string]interface{}, 0, len(sessions))
	for _, s := range sessions {
		typeName := "工作"
		switch s.SessionType {
		case "break":
			typeName = "短休息"
		case "long_break":
			typeName = "长休息"
		}
		fields := map[string]interface{}{
			"类型":    typeName,
			"开始时间":  s.StartedAt.UnixMilli(),
			"时长(秒)": s.DurationSec,
			"设备":    s.Device,
		}
		if s.EndedAt != nil {
			fields["结束时间"] = s.EndedAt.UnixMilli()
		}
		if s.TaskID != nil {
			fields["关联任务ID"] = *s.TaskID
		}
		records = append(records, map[string]interface{}{"fields": fields})
	}

	if err := h.batchCreateRecords(token, appToken, tableID, records); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "同步失败: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("番茄钟同步完成，共 %d 条", len(records)), "synced": len(records)})
}

// SyncReminders 同步休息提醒记录到飞书
func (h *FeishuHandler) SyncReminders(c *gin.Context) {
	userID := c.GetUint("userID")

	config, tables, err := h.getFeishuConfigWithTables(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书"})
		return
	}
	tableID := tables["休息提醒表"]
	if tableID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "休息提醒表不存在，请重新创建模板"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败"})
		return
	}

	appToken, _, err := h.parseTableURL(token, config.TableURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解析多维表格失败: " + err.Error()})
		return
	}

	var sessions []model.ReminderSession
	h.DB.Where("user_id = ? AND rest_ended_at IS NOT NULL", userID).Order("started_at ASC").Find(&sessions)

	records := make([]map[string]interface{}, 0, len(sessions))
	for _, s := range sessions {
		fields := map[string]interface{}{
			"开始时间":    s.StartedAt.UnixMilli(),
			"工作时长(秒)": s.WorkSeconds,
			"休息时长(秒)": s.RestSeconds,
			"跳过休息":    s.SkippedRest,
			"设备":      s.Device,
		}
		if s.WorkEndedAt != nil {
			fields["工作结束"] = s.WorkEndedAt.UnixMilli()
		}
		if s.RestEndedAt != nil {
			fields["休息结束"] = s.RestEndedAt.UnixMilli()
		}
		records = append(records, map[string]interface{}{"fields": fields})
	}

	if err := h.batchCreateRecords(token, appToken, tableID, records); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "同步失败: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("休息提醒同步完成，共 %d 条", len(records)), "synced": len(records)})
}

// SyncTags 同步标签到飞书
func (h *FeishuHandler) SyncTags(c *gin.Context) {
	userID := c.GetUint("userID")

	config, tables, err := h.getFeishuConfigWithTables(userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置飞书"})
		return
	}
	tableID := tables["标签表"]
	if tableID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "标签表不存在，请重新创建模板"})
		return
	}

	token, err := h.getTenantToken(config.AppID, config.AppSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取飞书 token 失败"})
		return
	}

	appToken, _, err := h.parseTableURL(token, config.TableURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解析多维表格失败: " + err.Error()})
		return
	}

	var tags []model.Tag
	h.DB.Where("user_id = ?", userID).Find(&tags)

	records := make([]map[string]interface{}, 0, len(tags))
	for _, t := range tags {
		// 统计关联任务数
		var count int64
		h.DB.Table("task_tags").Joins("JOIN tasks ON tasks.id = task_tags.task_id").
			Where("task_tags.tag_id = ? AND tasks.user_id = ?", t.ID, userID).Count(&count)

		fields := map[string]interface{}{
			"名称":    t.Name,
			"颜色":    t.Color,
			"关联任务数": count,
		}
		records = append(records, map[string]interface{}{"fields": fields})
	}

	if err := h.batchCreateRecords(token, appToken, tableID, records); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "同步失败: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("标签同步完成，共 %d 条", len(records)), "synced": len(records)})
}

// createBitable 创建多维表格
func (h *FeishuHandler) createBitable(token, name string) (string, error) {
	url := "https://open.feishu.cn/open-apis/bitable/v1/apps"
	body := map[string]string{"name": name}
	bodyJSON, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
		Data struct {
			App struct {
				AppToken string `json:"app_token"`
			} `json:"app"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return "", fmt.Errorf("创建多维表格失败: %s (code: %d)", result.Msg, result.Code)
	}

	return result.Data.App.AppToken, nil
}

// createTable 在多维表格中创建数据表
func (h *FeishuHandler) createTable(token, appToken, tableName, viewName string, fields []BitableField) (string, error) {
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s/tables", appToken)

	// 构建字段列表，第一个字段（标题）设置为必填
	var fieldList []map[string]interface{}
	for _, field := range fields {
		fieldData := map[string]interface{}{
			"field_name": field.FieldName,
			"type":       field.Type,
		}
		if field.Property != nil {
			fieldData["property"] = field.Property
		}
		fieldList = append(fieldList, fieldData)
	}

	body := map[string]interface{}{
		"table": map[string]interface{}{
			"name":              tableName,
			"default_view_name": viewName,
			"fields":            fieldList,
		},
	}
	bodyJSON, _ := json.Marshal(body)

	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(bodyJSON))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
		Data struct {
			TableId string `json:"table_id"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code != 0 {
		return "", fmt.Errorf("创建表失败: %s (code: %d)", result.Msg, result.Code)
	}

	return result.Data.TableId, nil
}

// resolveBitableURL 通过飞书 API 获取多维表格的真实 URL
func (h *FeishuHandler) resolveBitableURL(token, appToken, tableID string) string {
	// 调用 bitable 信息接口，响应中可能包含 URL
	url := fmt.Sprintf("https://open.feishu.cn/open-apis/bitable/v1/apps/%s", appToken)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Sprintf("https://my.feishu.cn/base/%s?table=%s", appToken, tableID)
	}
	defer resp.Body.Close()

	var result struct {
		Code int `json:"code"`
		Data struct {
			App struct {
				URL string `json:"url"`
			} `json:"app"`
		} `json:"data"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	if result.Code == 0 && result.Data.App.URL != "" {
		// 如果 API 返回了 URL，追加 table 参数
		baseURL := result.Data.App.URL
		if tableID != "" {
			if strings.Contains(baseURL, "?") {
				baseURL += "&table=" + tableID
			} else {
				baseURL += "?table=" + tableID
			}
		}
		return baseURL
	}

	// fallback
	return fmt.Sprintf("https://my.feishu.cn/base/%s?table=%s", appToken, tableID)
}
