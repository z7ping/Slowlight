package caldav

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"slowlight/internal/model"
	"slowlight/internal/secureconfig"

	"github.com/emersion/go-ical"
	"github.com/emersion/go-webdav"
	"github.com/emersion/go-webdav/caldav"
	"gorm.io/gorm"
)

// ErrConfigIncomplete 表示用户 CalDAV 配置不完整（缺凭据/路径），
// 定时同步时应跳过该用户而不是作为失败处理。
var ErrConfigIncomplete = errors.New("CalDAV 配置不完整")

// SyncResult 同步结果
type SyncResult struct {
	ProjectsSynced int      `json:"projects_synced"`
	TasksCreated   int      `json:"tasks_created"`
	TasksUpdated   int      `json:"tasks_updated"`
	TasksSkipped   int      `json:"tasks_skipped"`
	Errors         []string `json:"errors,omitempty"`
}

// getDefaultClient 从配置创建 CalDAV 客户端
func getDefaultClient(baseURL, username, password string) (*caldav.Client, string, error) {
	if baseURL == "" || username == "" || password == "" {
		return nil, "", fmt.Errorf("%w: base_url, username, password 不能为空", ErrConfigIncomplete)
	}

	httpClient := &http.Client{Timeout: 30 * time.Second}
	authClient := webdav.HTTPClientWithBasicAuth(httpClient, username, password)
	client, err := caldav.NewClient(authClient, baseURL)
	if err != nil {
		return nil, "", fmt.Errorf("创建 CalDAV 客户端失败: %w", err)
	}

	return client, baseURL, nil
}

// SyncAll 执行全量同步
func SyncAll(db *gorm.DB, userID uint) (*SyncResult, error) {
	// 从 DB 读取用户配置
	var config model.UserConfig
	db.Where("user_id = ? AND key = ?", userID, "caldav").First(&config)
	if config.ID == 0 {
		return nil, fmt.Errorf("未配置 CalDAV，请先调用 POST /api/caldav/config 设置")
	}

	// 解析凭据
	var m map[string]interface{}
	if err := json.Unmarshal([]byte(config.Value), &m); err != nil {
		return nil, fmt.Errorf("解析 CalDAV 配置失败: %w", err)
	}

	baseURL, _ := m["base_url"].(string)
	username, _ := m["username"].(string)
	password, _ := m["password"].(string)
	password, err := secureconfig.Decrypt(password)
	if err != nil {
		return nil, fmt.Errorf("读取 CalDAV 凭据失败: %w", err)
	}

	client, _, err := getDefaultClient(baseURL, username, password)
	if err != nil {
		return nil, err
	}

	// 读取用户配置的项目路径列表
	projectPaths := getProjectPaths(db, userID)
	if len(projectPaths) == 0 {
		return nil, fmt.Errorf("%w: 未配置 CalDAV 项目路径，请先调用 POST /api/caldav/config 设置", ErrConfigIncomplete)
	}

	result := &SyncResult{}

	for _, path := range projectPaths {
		err := syncProject(db, client, userID, path, result)
		if err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("%s: %v", path, err))
			continue
		}
		result.ProjectsSynced++
	}

	log.Printf("[CalDAV] 同步完成: 项目=%d, 新增=%d, 更新=%d, 跳过=%d",
		result.ProjectsSynced, result.TasksCreated, result.TasksUpdated, result.TasksSkipped)

	return result, nil
}

// getProjectPaths 读取用户配置的 CalDAV 项目路径
func getProjectPaths(db *gorm.DB, userID uint) []string {
	var config model.UserConfig
	db.Where("user_id = ? AND key = ?", userID, "caldav").First(&config)
	if config.ID == 0 {
		return nil
	}

	// 格式: {"paths": ["/dav/projects/5", "/dav/projects/8"], ...}
	// 简单解析，避免引入 json 库的循环依赖
	value := config.Value
	paths := make([]string, 0)

	// 查找 "paths" 数组
	idx := strings.Index(value, `"paths"`)
	if idx == -1 {
		return nil
	}
	value = value[idx:]

	start := strings.Index(value, "[")
	end := strings.Index(value, "]")
	if start == -1 || end == -1 {
		return nil
	}

	raw := value[start+1 : end]
	for _, p := range strings.Split(raw, ",") {
		p = strings.TrimSpace(p)
		p = strings.Trim(p, `"`)
		if p != "" {
			paths = append(paths, p)
		}
	}

	return paths
}

// syncProject 同步单个 CalDAV 项目
func syncProject(db *gorm.DB, client *caldav.Client, userID uint, projectPath string, result *SyncResult) error {
	// 查找或创建对应的 List
	list := findOrCreateList(db, userID, projectPath)

	// 查询所有 VTODO
	query := &caldav.CalendarQuery{
		CompFilter: caldav.CompFilter{
			Name: "VTODO",
		},
	}

	objects, err := client.QueryCalendar(context.Background(), projectPath, query)
	if err != nil {
		return fmt.Errorf("查询日历失败: %w", err)
	}

	log.Printf("[CalDAV] 项目 %s: 获取 %d 个任务", projectPath, len(objects))

	// 建立远程 UID 集合（用于检测远程删除）
	remoteUIDs := make(map[string]bool)

	// 处理每个 VTODO
	for _, obj := range objects {
		remoteUIDs[obj.Path] = true

		vtodo := extractVTodo(&obj)
		if vtodo == nil {
			continue
		}

		uid := getProp(vtodo, ical.PropUID)
		if uid == "" {
			continue
		}

		etag := obj.ETag
		task := mapToTask(vtodo, list.ID, userID, uid, etag)

		// 查找本地是否已存在
		var existing model.Task
		err := db.Where("cal_d_a_v_uid = ? AND user_id = ?", uid, userID).First(&existing).Error

		if err == gorm.ErrRecordNotFound {
			// 新增
			if err := db.Create(task).Error; err != nil {
				result.Errors = append(result.Errors, fmt.Sprintf("创建任务失败 [%s]: %v", task.Title, err))
				continue
			}
			result.TasksCreated++
		} else if err == nil {
			// 已存在，检查 ETag 是否变化
			if existing.CalDAVTag == etag {
				result.TasksSkipped++
				continue
			}
			// 更新
			task.ID = existing.ID
			if err := db.Model(&existing).Updates(toUpdateMap(task)).Error; err != nil {
				result.Errors = append(result.Errors, fmt.Sprintf("更新任务失败 [%s]: %v", task.Title, err))
				continue
			}
			result.TasksUpdated++
		}
	}

	// 更新同步状态
	updateSyncState(db, userID, projectPath, len(objects))

	return nil
}

// extractVTodo 从 CalDAV 对象中提取 VTODO 组件
func extractVTodo(obj *caldav.CalendarObject) *ical.Component {
	if obj.Data == nil {
		return nil
	}
	for _, child := range obj.Data.Children {
		if child.Name == "VTODO" {
			return child
		}
	}
	return nil
}

// getProp 获取 iCalendar 属性值
func getProp(comp *ical.Component, name string) string {
	if prop := comp.Props.Get(name); prop != nil {
		return prop.Value
	}
	return ""
}

// mapToTask 将 VTODO 映射为 Slowlight Task
func mapToTask(vtodo *ical.Component, listID, userID uint, uid, etag string) *model.Task {
	task := &model.Task{
		UserID:      userID,
		ListID:      listID,
		Title:       getProp(vtodo, ical.PropSummary),
		Description: getProp(vtodo, ical.PropDescription),
		CalDAVUID:   uid,
		CalDAVTag:   etag,
	}

	if task.Title == "" {
		task.Title = "(无标题)"
	}

	// 解析优先级
	if p := getProp(vtodo, ical.PropPriority); p != "" {
		task.Priority = mapPriority(p)
	}

	// 解析截止日期
	if due := getProp(vtodo, ical.PropDue); due != "" {
		if t, err := parseICalTime(due); err == nil {
			task.DueDate = &model.FlexibleTime{Time: t}
		}
	}

	// 解析完成状态
	if status := getProp(vtodo, ical.PropStatus); status == "COMPLETED" {
		task.IsCompleted = true
		now := time.Now()
		task.CompletedAt = &now
	}

	// 解析分类（标签）
	if cats := vtodo.Props.Get(ical.PropCategories); cats != nil {
		// CATEGORIES 可能是逗号分隔的字符串
		// 标签处理在调用方根据需要扩展
	}

	return task
}

// mapPriority 将 iCalendar 优先级 (1-9) 映射为 Slowlight 优先级
func mapPriority(p string) string {
	n, err := strconv.Atoi(p)
	if err != nil {
		return "none"
	}
	switch {
	case n == 1:
		return "urgent"
	case n >= 2 && n <= 4:
		return "high"
	case n == 5:
		return "medium"
	case n >= 6 && n <= 7:
		return "low"
	default:
		return "none"
	}
}

// parseICalTime 解析 iCalendar 时间格式
func parseICalTime(s string) (time.Time, error) {
	// 支持格式: 20240115T090000Z (UTC) 或 20240115 (date only)
	s = strings.TrimSpace(s)
	if len(s) == 8 {
		// 仅日期: YYYYMMDD
		return time.Parse("20060102", s)
	}
	// 带时间: YYYYMMDDTHHMMSSZ 或带时区
	s = strings.TrimSuffix(s, "Z")
	return time.ParseInLocation("20060102T150405", s, time.UTC)
}

// findOrCreateList 查找或创建 CalDAV 对应的 List
func findOrCreateList(db *gorm.DB, userID uint, projectPath string) model.List {
	var list model.List
	err := db.Where("user_id = ? AND cal_d_a_v_url = ?", userID, projectPath).First(&list).Error
	if err == nil {
		return list
	}

	// 从路径提取项目名（如 /dav/projects/5 → "Vikunja #5"）
	parts := strings.Split(projectPath, "/")
	projectID := parts[len(parts)-1]
	name := fmt.Sprintf("Vikunja #%s", projectID)

	list = model.List{
		UserID:    userID,
		Name:      name,
		Icon:      "📥",
		Color:     "#7c3aed",
		CalDAVURL: projectPath,
	}
	db.Create(&list)

	return list
}

// toUpdateMap 将 Task 转换为更新 map（只更新 CalDAV 同步的字段）
func toUpdateMap(task *model.Task) map[string]interface{} {
	return map[string]interface{}{
		"title":         task.Title,
		"description":   task.Description,
		"priority":      task.Priority,
		"due_date":      task.DueDate,
		"is_completed":  task.IsCompleted,
		"completed_at":  task.CompletedAt,
		"cal_d_a_v_tag": task.CalDAVTag,
	}
}

// updateSyncState 更新同步状态
func updateSyncState(db *gorm.DB, userID uint, projectPath string, taskCount int) {
	var state model.CalDAVSyncState
	err := db.Where("user_id = ? AND project_path = ?", userID, projectPath).First(&state).Error
	if err == gorm.ErrRecordNotFound {
		state = model.CalDAVSyncState{
			UserID:      userID,
			ProjectPath: projectPath,
		}
	}
	state.LastSyncedAt = time.Now()
	state.SyncToken = fmt.Sprintf("full-%d-%d", taskCount, time.Now().Unix())

	db.Save(&state)
}
