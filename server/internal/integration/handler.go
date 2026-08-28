package integration

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"slowlight/internal/model"
	"slowlight/internal/secureconfig"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// Handler 通用集成 Handler
type Handler struct {
	DB *gorm.DB
}

func NewHandler(db *gorm.DB) *Handler {
	return &Handler{DB: db}
}

// ===== 获取支持的平台列表 =====

func (h *Handler) ListPlatforms(c *gin.Context) {
	platforms := make([]map[string]interface{}, 0)
	for _, p := range List() {
		userID := c.GetUint("userID")
		configured := h.isConfigured(userID, p.Name())
		platforms = append(platforms, map[string]interface{}{
			"name":         p.Name(),
			"display_name": p.DisplayName(),
			"configured":   configured,
		})
	}
	c.JSON(http.StatusOK, gin.H{"platforms": platforms})
}

// ===== 获取配置 =====

func (h *Handler) GetConfig(c *gin.Context) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台: " + platform})
		return
	}

	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, platform).First(&config)

	if config.ID == 0 {
		c.JSON(http.StatusOK, gin.H{
			"configured":   false,
			"platform":     platform,
			"display_name": provider.DisplayName(),
		})
		return
	}

	var raw map[string]interface{}
	json.Unmarshal([]byte(config.Value), &raw)

	resp := gin.H{
		"configured":   true,
		"platform":     platform,
		"display_name": provider.DisplayName(),
	}

	// 返回 app_id 和 table_url（不返回 app_secret）
	if v, ok := raw["app_id"]; ok {
		resp["app_id"] = v
	}
	if v, ok := raw["table_url"]; ok {
		resp["table_url"] = v
	}
	if tables, ok := raw["tables"].(map[string]interface{}); ok && len(tables) > 0 {
		resp["tables"] = tables
	}

	c.JSON(http.StatusOK, resp)
}

// ===== 保存配置 =====

func (h *Handler) SaveConfig(c *gin.Context) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台: " + platform})
		return
	}

	var req struct {
		AppID     string `json:"app_id"`
		AppSecret string `json:"app_secret"`
		TableURL  string `json:"table_url"` // 可选
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.AppID == "" || req.AppSecret == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "App ID 和 App Secret 不能为空"})
		return
	}

	// 验证凭据
	credentials := map[string]interface{}{
		"app_id":     req.AppID,
		"app_secret": req.AppSecret,
	}
	if err := provider.ValidateCredentials(credentials); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "凭据验证失败: " + err.Error()})
		return
	}

	// 读取已有配置，保留 tables 等字段
	var existingConfig model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, platform).First(&existingConfig)

	var merged map[string]interface{}
	if existingConfig.ID != 0 {
		json.Unmarshal([]byte(existingConfig.Value), &merged)
	} else {
		merged = map[string]interface{}{}
	}

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
	existingConfig.Key = platform
	existingConfig.Value = string(configJSON)

	if existingConfig.ID == 0 {
		h.DB.Create(&existingConfig)
	} else {
		h.DB.Save(&existingConfig)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "配置保存成功",
		"configured": true,
	})
}

// ===== 创建模板 =====

func (h *Handler) CreateTemplate(c *gin.Context) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台"})
		return
	}

	credentials, err := h.getCredentials(userID, platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置 " + provider.DisplayName()})
		return
	}

	result, err := provider.CreateTemplate(credentials)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建模板失败: " + err.Error()})
		return
	}

	// 保存 table_url 和 tables
	if tableURL, ok := result["table_url"].(string); ok && tableURL != "" {
		h.updateConfigField(userID, platform, "table_url", tableURL)
	}
	if tables, ok := result["tables"].(map[string]string); ok {
		h.saveTableIDs(userID, platform, tables)
	}

	log.Printf("[CreateTemplate] platform=%s userID=%d tables=%v", platform, userID, result["tables"])

	c.JSON(http.StatusOK, gin.H{
		"message":   provider.DisplayName() + " 模板创建成功",
		"table_url": result["table_url"],
		"tables":    result["tables"],
	})
}

// ===== 绑定已有表格 =====

func (h *Handler) ConnectExisting(c *gin.Context) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台"})
		return
	}

	var req struct {
		TableURL string `json:"table_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.TableURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请提供表格链接"})
		return
	}

	credentials, err := h.getCredentials(userID, platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置 " + provider.DisplayName()})
		return
	}

	result, err := provider.ConnectExisting(credentials, req.TableURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "绑定失败: " + err.Error()})
		return
	}

	// 保存配置
	h.updateConfigField(userID, platform, "table_url", req.TableURL)
	if tables, ok := result["tables"].(map[string]string); ok {
		h.saveTableIDs(userID, platform, tables)
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "绑定成功",
		"tables":  result["tables"],
	})
}

// ===== 同步全部 =====

func (h *Handler) SyncAll(c *gin.Context) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台"})
		return
	}

	credentials, tableIDs, err := h.getFullConfig(userID, platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置 " + provider.DisplayName()})
		return
	}

	// 收集所有数据
	syncData := h.collectSyncData(userID)

	result, err := provider.SyncTo(credentials, tableIDs, syncData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "同步失败: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "全部同步完成",
		"results": result.Results,
		"errors":  result.Errors,
	})
}

// ===== 同步单个数据类型 =====

func (h *Handler) SyncTasks(c *gin.Context) {
	h.syncSingleType(c, "任务表")
}

func (h *Handler) SyncSessions(c *gin.Context) {
	h.syncSingleType(c, "番茄钟表")
}

func (h *Handler) SyncReminders(c *gin.Context) {
	h.syncSingleType(c, "休息提醒表")
}

func (h *Handler) SyncTags(c *gin.Context) {
	h.syncSingleType(c, "标签表")
}

func (h *Handler) syncSingleType(c *gin.Context, tableType string) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台"})
		return
	}

	credentials, tableIDs, err := h.getFullConfig(userID, platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置 " + provider.DisplayName()})
		return
	}

	if tableIDs[tableType] == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("未找到 %s，请先创建模板或绑定表格", tableType)})
		return
	}

	syncData := h.collectSyncData(userID)

	// 只同步指定类型
	filteredData := &SyncData{}
	switch tableType {
	case "任务表":
		filteredData.Tasks = syncData.Tasks
	case "番茄钟表":
		filteredData.Sessions = syncData.Sessions
	case "休息提醒表":
		filteredData.Reminders = syncData.Reminders
	case "标签表":
		filteredData.Tags = syncData.Tags
	}

	result, err := provider.SyncTo(credentials, tableIDs, filteredData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "同步失败: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("%s同步完成", tableType),
		"results": result.Results,
		"errors":  result.Errors,
	})
}

// ===== 导入 =====

func (h *Handler) Import(c *gin.Context) {
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台"})
		return
	}

	c.JSON(http.StatusNotImplemented, gin.H{
		"error": fmt.Sprintf("%s 导入尚未开放：当前版本不会把远端记录写入 Slowlight，请使用导出同步功能", provider.DisplayName()),
	})
}

// ===== 日历相关 =====

// ListCalendars 获取平台日历列表
func (h *Handler) ListCalendars(c *gin.Context) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台"})
		return
	}

	credentials, err := h.getCredentials(userID, platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置 " + provider.DisplayName()})
		return
	}

	calendars, err := provider.ListCalendars(credentials)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取日历列表失败: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"calendars": calendars,
	})
}

// SyncToCalendar 将任务同步到日历
func (h *Handler) SyncToCalendar(c *gin.Context) {
	userID := c.GetUint("userID")
	platform := c.Param("platform")

	provider, err := Get(platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的平台"})
		return
	}

	var req struct {
		CalendarID string `json:"calendar_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.CalendarID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请提供日历 ID"})
		return
	}

	credentials, err := h.getCredentials(userID, platform)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先配置 " + provider.DisplayName()})
		return
	}

	// 收集有 due_date 的任务，构建日历事件
	calendarData := h.collectCalendarData(userID)

	result, err := provider.SyncToCalendar(credentials, req.CalendarID, calendarData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "同步日历失败: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "日历同步完成",
		"results": result.Results,
		"errors":  result.Errors,
	})
}

// ===== 内部工具方法 =====

func (h *Handler) isConfigured(userID uint, platform string) bool {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, platform).First(&config)
	return config.ID != 0
}

func (h *Handler) getCredentials(userID uint, platform string) (map[string]interface{}, error) {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, platform).First(&config)
	if config.ID == 0 {
		return nil, fmt.Errorf("未配置 %s", platform)
	}

	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(config.Value), &raw); err != nil {
		return nil, fmt.Errorf("%s 配置格式无效: %w", platform, err)
	}
	secret, _ := raw["app_secret"].(string)
	secret, err := secureconfig.Decrypt(secret)
	if err != nil {
		return nil, fmt.Errorf("读取 %s 凭据失败: %w", platform, err)
	}

	credentials := map[string]interface{}{
		"app_id":     raw["app_id"],
		"app_secret": secret,
		"table_url":  raw["table_url"],
	}
	return credentials, nil
}

func (h *Handler) getFullConfig(userID uint, platform string) (credentials map[string]interface{}, tableIDs map[string]string, err error) {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, platform).First(&config)
	if config.ID == 0 {
		return nil, nil, fmt.Errorf("未配置 %s", platform)
	}

	var raw map[string]interface{}
	if err := json.Unmarshal([]byte(config.Value), &raw); err != nil {
		return nil, nil, fmt.Errorf("%s 配置格式无效: %w", platform, err)
	}
	secret, _ := raw["app_secret"].(string)
	secret, err = secureconfig.Decrypt(secret)
	if err != nil {
		return nil, nil, fmt.Errorf("读取 %s 凭据失败: %w", platform, err)
	}

	credentials = map[string]interface{}{
		"app_id":     raw["app_id"],
		"app_secret": secret,
		"table_url":  raw["table_url"],
	}

	tableIDs = map[string]string{}
	if tables, ok := raw["tables"].(map[string]interface{}); ok {
		for k, v := range tables {
			if s, ok := v.(string); ok {
				tableIDs[k] = s
			}
		}
	}

	return credentials, tableIDs, nil
}

func (h *Handler) updateConfigField(userID uint, platform, key, value string) {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, platform).First(&config)
	if config.ID == 0 {
		return
	}

	var raw map[string]interface{}
	json.Unmarshal([]byte(config.Value), &raw)
	raw[key] = value

	configJSON, _ := json.Marshal(raw)
	config.Value = string(configJSON)
	h.DB.Save(&config)
}

func (h *Handler) saveTableIDs(userID uint, platform string, newTables map[string]string) {
	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, platform).First(&config)
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

// collectSyncData 从数据库收集所有同步数据
func (h *Handler) collectSyncData(userID uint) *SyncData {
	data := &SyncData{}

	// 任务
	var tasks []model.Task
	h.DB.Preload("List").Where("user_id = ?", userID).Find(&tasks)
	for _, task := range tasks {
		rec := TaskRecord{
			ID:          task.ID,
			Title:       task.Title,
			Description: task.Description,
			ListName:    task.List.Name,
			Priority:    task.Priority,
			IsCompleted: task.IsCompleted,
			CreatedAt:   task.CreatedAt.UnixMilli(),
		}
		if task.DueDate != nil {
			ms := task.DueDate.UnixMilli()
			rec.DueDate = &ms
		}
		if task.CompletedAt != nil {
			ms := task.CompletedAt.UnixMilli()
			rec.CompletedAt = &ms
		}
		data.Tasks = append(data.Tasks, rec)
	}

	// 清单
	var lists []model.List
	h.DB.Where("user_id = ?", userID).Find(&lists)
	for _, l := range lists {
		data.Lists = append(data.Lists, ListRecord{
			Name:  l.Name,
			Color: l.Color,
			Icon:  l.Icon,
		})
	}

	// 番茄钟
	var sessions []model.WorkSession
	h.DB.Where("user_id = ?", userID).Order("started_at ASC").Find(&sessions)
	for _, s := range sessions {
		rec := SessionRecord{
			Type:        s.SessionType,
			StartedAt:   s.StartedAt.UnixMilli(),
			DurationSec: s.DurationSec,
			Device:      s.Device,
		}
		if s.EndedAt != nil {
			ms := s.EndedAt.UnixMilli()
			rec.EndedAt = &ms
		}
		if s.TaskID != nil {
			rec.TaskID = s.TaskID
		}
		data.Sessions = append(data.Sessions, rec)
	}

	// 休息提醒
	var reminders []model.ReminderSession
	h.DB.Where("user_id = ? AND rest_ended_at IS NOT NULL", userID).Order("started_at ASC").Find(&reminders)
	for _, s := range reminders {
		rec := ReminderRecord{
			StartedAt:   s.StartedAt.UnixMilli(),
			WorkSeconds: s.WorkSeconds,
			RestSeconds: s.RestSeconds,
			SkippedRest: s.SkippedRest,
			Device:      s.Device,
		}
		if s.WorkEndedAt != nil {
			ms := s.WorkEndedAt.UnixMilli()
			rec.WorkEndedAt = &ms
		}
		if s.RestEndedAt != nil {
			ms := s.RestEndedAt.UnixMilli()
			rec.RestEndedAt = &ms
		}
		data.Reminders = append(data.Reminders, rec)
	}

	// 标签
	var tags []model.Tag
	h.DB.Where("user_id = ?", userID).Find(&tags)
	for _, t := range tags {
		var count int64
		h.DB.Table("task_tags").Joins("JOIN tasks ON tasks.id = task_tags.task_id").
			Where("task_tags.tag_id = ? AND tasks.user_id = ?", t.ID, userID).Count(&count)
		data.Tags = append(data.Tags, TagRecord{
			Name:      t.Name,
			Color:     t.Color,
			TaskCount: count,
		})
	}

	return data
}

// collectCalendarData 收集有 due_date 的任务，转换为日历事件
func (h *Handler) collectCalendarData(userID uint) *CalendarSyncData {
	var tasks []model.Task
	h.DB.Preload("List").Where("user_id = ? AND due_date IS NOT NULL AND is_completed = false", userID).Find(&tasks)

	data := &CalendarSyncData{}

	for _, task := range tasks {
		if task.DueDate == nil || !task.DueDate.Valid {
			continue
		}

		event := CalendarEvent{
			Summary:     task.Title,
			Description: task.Description,
		}

		// FlexibleTime.Time 是 UTC 时间，转为北京时间的 unix timestamp
		dueTime := task.DueDate.Time.In(model.BeijingLocation())

		if task.DueTime != nil && *task.DueTime != "" {
			// 有具体时间：解析 HH:MM，创建 1 小时时长的事件
			hour, min := 0, 0
			fmt.Sscanf(*task.DueTime, "%d:%d", &hour, &min)
			eventTime := time.Date(dueTime.Year(), dueTime.Month(), dueTime.Day(),
				hour, min, 0, 0, model.BeijingLocation())
			event.StartTime = eventTime.Unix()
			event.EndTime = eventTime.Unix() + 3600
			event.IsAllDay = false
		} else {
			// 无具体时间：全天事件
			dayStart := time.Date(dueTime.Year(), dueTime.Month(), dueTime.Day(),
				0, 0, 0, 0, model.BeijingLocation())
			event.StartTime = dayStart.Unix()
			event.EndTime = dayStart.Unix() + 86400
			event.IsAllDay = true
		}

		// 重复规则映射
		switch task.RepeatType {
		case "daily":
			event.RRule = "FREQ=DAILY"
		case "weekly":
			event.RRule = "FREQ=WEEKLY"
		case "monthly":
			event.RRule = "FREQ=MONTHLY"
		case "yearly":
			event.RRule = "FREQ=YEARLY"
		}

		data.Events = append(data.Events, event)
	}

	return data
}
