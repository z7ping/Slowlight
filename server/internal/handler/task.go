package handler

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type TaskHandler struct {
	DB *gorm.DB
}

func NewTaskHandler(db *gorm.DB) *TaskHandler {
	return &TaskHandler{DB: db}
}

// fillSubtaskProgress 为任务列表填充子任务进度
func (h *TaskHandler) fillSubtaskProgress(tasks []model.Task) {
	if len(tasks) == 0 {
		return
	}
	taskIDs := make([]uint, len(tasks))
	for i, t := range tasks {
		taskIDs[i] = t.ID
	}

	type progress struct {
		TaskID    uint
		Total     int
		Completed int
	}
	var results []progress
	h.DB.Raw(`
		SELECT task_id,
			COUNT(*) as total,
			COUNT(*) FILTER (WHERE is_completed) as completed
		FROM subtasks WHERE task_id IN ?
		GROUP BY task_id
	`, taskIDs).Scan(&results)

	m := make(map[uint]progress)
	for _, r := range results {
		m[r.TaskID] = r
	}
	for i := range tasks {
		if p, ok := m[tasks[i].ID]; ok {
			tasks[i].SubtaskCount = p.Total
			tasks[i].CompletedSubtask = p.Completed
		}
	}
}

// FillSubtaskProgress 公开方法，供其他 handler 使用
func (h *TaskHandler) FillSubtaskProgress(tasks []model.Task) {
	h.fillSubtaskProgress(tasks)
}

// updateTaskTags 更新任务的标签关联
func (h *TaskHandler) updateTaskTags(taskID uint, tagIDs []uint) {
	// 先删除所有旧的标签关联
	h.DB.Where("task_id = ?", taskID).Delete(&model.TaskTag{})

	// 添加新的标签关联
	for _, tagID := range tagIDs {
		taskTag := model.TaskTag{TaskID: taskID, TagID: tagID}
		h.DB.Create(&taskTag)
	}
}

func (h *TaskHandler) validateTaskReferences(c *gin.Context, userID uint, task *model.Task) bool {
	if task.ListID != 0 {
		var count int64
		h.DB.Model(&model.List{}).
			Where("id = ? AND user_id = ?", task.ListID, userID).
			Count(&count)
		if count == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "清单不存在"})
			return false
		}
	}

	if task.SystemTagID != nil {
		var count int64
		h.DB.Model(&model.SystemTag{}).
			Where("id = ? AND user_id = ?", *task.SystemTagID, userID).
			Count(&count)
		if count == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "观察标签不存在"})
			return false
		}
	}

	if task.RelatedQuestID != nil {
		var count int64
		h.DB.Model(&model.Task{}).
			Where("id = ? AND user_id = ?", *task.RelatedQuestID, userID).
			Count(&count)
		if count == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "关联任务不存在"})
			return false
		}
	}

	if len(task.TagIDs) > 0 {
		unique := make(map[uint]struct{}, len(task.TagIDs))
		for _, tagID := range task.TagIDs {
			unique[tagID] = struct{}{}
		}
		ids := make([]uint, 0, len(unique))
		for tagID := range unique {
			ids = append(ids, tagID)
		}
		var count int64
		h.DB.Model(&model.Tag{}).
			Where("user_id = ? AND id IN ?", userID, ids).
			Count(&count)
		if count != int64(len(ids)) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "标签不存在"})
			return false
		}
	}

	return true
}

// CreateTask 创建任务
func (h *TaskHandler) CreateTask(c *gin.Context) {
	userID := c.GetUint("userID")
	var task model.Task
	if err := c.ShouldBindJSON(&task); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if strings.TrimSpace(task.Title) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "任务标题不能为空"})
		return
	}
	if !h.validateTaskReferences(c, userID, &task) {
		return
	}

	task.UserID = userID

	// 保存 tag_ids（用于后续设置标签）
	tagIDs := task.TagIDs

	if err := h.DB.Create(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 设置标签关联
	if len(tagIDs) > 0 {
		h.updateTaskTags(task.ID, tagIDs)
	}

	h.DB.Preload("List").Preload("Tags").First(&task, task.ID)

	// 触发 Webhook
	triggerWebhooks(h.DB, userID, model.EventTaskCreated, map[string]interface{}{
		"id": task.ID, "title": task.Title, "list_id": task.ListID, "priority": task.Priority,
	})

	c.JSON(http.StatusCreated, task)
}

// GetTasks 获取任务列表
func (h *TaskHandler) GetTasks(c *gin.Context) {
	userID := c.GetUint("userID")
	var tasks []model.Task
	query := h.DB.Preload("List").Preload("Tags").Where("user_id = ?", userID)

	// 按清单筛选
	if listID := c.Query("list_id"); listID != "" {
		query = query.Where("list_id = ?", listID)
	}

	// 按完成状态筛选
	if isCompleted := c.Query("is_completed"); isCompleted != "" {
		query = query.Where("is_completed = ?", isCompleted == "true")
	}

	query.Order("sort_order ASC, created_at DESC").Find(&tasks)
	h.fillSubtaskProgress(tasks)
	c.JSON(http.StatusOK, tasks)
}

// GetTask 获取单个任务
func (h *TaskHandler) GetTask(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var task model.Task

	if err := h.DB.Preload("List").Preload("Tags").Where("user_id = ?", userID).First(&task, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "任务不存在"})
		return
	}
	// 填充子任务列表
	h.DB.Where("task_id = ?", task.ID).Order("sort_order ASC, created_at ASC").Find(&task.Subtasks)
	h.fillSubtaskProgress([]model.Task{task})
	c.JSON(http.StatusOK, task)
}

// UpdateTask 更新任务
func (h *TaskHandler) UpdateTask(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var task model.Task

	if err := h.DB.Where("user_id = ?", userID).First(&task, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "任务不存在"})
		return
	}

	var raw map[string]json.RawMessage
	if err := c.ShouldBindJSON(&raw); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	payload, err := json.Marshal(raw)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "任务更新数据无效"})
		return
	}
	var updateData model.Task
	if err := json.Unmarshal(payload, &updateData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if _, ok := raw["title"]; ok && strings.TrimSpace(updateData.Title) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "任务标题不能为空"})
		return
	}
	if _, ok := raw["list_id"]; ok && updateData.ListID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "清单不能为空"})
		return
	}
	if !h.validateTaskReferences(c, userID, &updateData) {
		return
	}

	updates := map[string]interface{}{}
	mutableFields := map[string]interface{}{
		"list_id": updateData.ListID, "title": updateData.Title,
		"description": updateData.Description, "due_date": updateData.DueDate,
		"due_time": updateData.DueTime, "is_completed": updateData.IsCompleted,
		"completed_at": updateData.CompletedAt, "priority": updateData.Priority,
		"sort_order": updateData.SortOrder, "repeat_type": updateData.RepeatType,
		"repeat_interval": updateData.RepeatInterval, "repeat_days": updateData.RepeatDays,
		"reminder_at":              updateData.ReminderAt,
		"reminder_advance_minutes": updateData.ReminderAdvanceMinutes,
		"system_tag_id":            updateData.SystemTagID, "task_type": updateData.TaskType,
		"mood_before": updateData.MoodBefore, "mood_after": updateData.MoodAfter,
		"is_milestone": updateData.IsMilestone, "related_quest_id": updateData.RelatedQuestID,
		"obsidian_link": updateData.ObsidianLink, "output_level": updateData.OutputLevel,
	}
	for field, value := range mutableFields {
		if _, provided := raw[field]; provided {
			updates[field] = value
		}
	}
	if len(updates) > 0 {
		if err := h.DB.Model(&task).Updates(updates).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	// 更新标签关联（如果提供了 tag_ids）
	if _, provided := raw["tag_ids"]; provided {
		h.updateTaskTags(task.ID, updateData.TagIDs)
	}

	h.DB.Preload("List").Preload("Tags").First(&task, id)

	// 触发 Webhook
	triggerWebhooks(h.DB, userID, model.EventTaskUpdated, map[string]interface{}{
		"id": task.ID, "title": task.Title, "list_id": task.ListID, "is_completed": task.IsCompleted,
	})

	c.JSON(http.StatusOK, task)
}

// DeleteTask 删除任务
func (h *TaskHandler) DeleteTask(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	result := h.DB.Where("user_id = ?", userID).Delete(&model.Task{}, id)
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "任务不存在"})
		return
	}

	// 触发 Webhook
	triggerWebhooks(h.DB, userID, model.EventTaskDeleted, map[string]interface{}{
		"id": id,
	})

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// GetTasksByList 获取指定清单的任务
func (h *TaskHandler) GetTasksByList(c *gin.Context) {
	userID := c.GetUint("userID")
	listID := c.Param("id")
	var tasks []model.Task

	h.DB.Preload("List").Preload("Tags").
		Where("list_id = ? AND user_id = ?", listID, userID).
		Order("sort_order ASC, created_at DESC").
		Find(&tasks)
	h.fillSubtaskProgress(tasks)
	c.JSON(http.StatusOK, tasks)
}

// GetTodayTasks 获取今日任务（含已完成，未完成在前）
func (h *TaskHandler) GetTodayTasks(c *gin.Context) {
	userID := c.GetUint("userID")
	var tasks []model.Task

	// 用用户时区算"今日"
	var user model.User
	h.DB.Select("timezone").First(&user, userID)
	loc := model.UserLocation(user.Timezone)
	today := time.Now().In(loc).Format("2006-01-02")

	// 返回今日任务 + 无日期任务 + 延期未完成任务
	// 排序：今日已完成 → 今日未完成 → 无日期/延期未完成
	h.DB.Preload("List").Preload("Tags").
		Where("user_id = ? AND (due_date = ? OR due_date IS NULL OR (due_date < ? AND is_completed = false))",
			userID, today, today).
		Order(gorm.Expr(
			"CASE WHEN due_date IS NULL THEN 1 "+
				"WHEN due_date = ? AND is_completed THEN 0 "+
				"WHEN due_date = ? AND NOT is_completed THEN 1 "+
				"ELSE 2 END, priority DESC, created_at DESC",
			today, today)).
		Find(&tasks)
	h.fillSubtaskProgress(tasks)
	c.JSON(http.StatusOK, tasks)
}

// PostponeTask 顺延任务到今天
func (h *TaskHandler) PostponeTask(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var task model.Task

	if err := h.DB.Where("user_id = ?", userID).First(&task, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "任务不存在"})
		return
	}

	// 用用户时区算"今日"
	var user model.User
	h.DB.Select("timezone").First(&user, userID)
	loc := model.UserLocation(user.Timezone)
	today := time.Now().In(loc).Format("2006-01-02")

	h.DB.Model(&task).Updates(map[string]interface{}{
		"due_date": today,
	})
	h.DB.Preload("List").Preload("Tags").First(&task, task.ID)
	h.fillSubtaskProgress([]model.Task{task})
	c.JSON(http.StatusOK, task)
}

// GetCompletedTasks 获取已完成任务
func (h *TaskHandler) GetCompletedTasks(c *gin.Context) {
	userID := c.GetUint("userID")
	var tasks []model.Task

	h.DB.Preload("List").Preload("Tags").
		Where("user_id = ? AND is_completed = ?", userID, true).
		Order("completed_at DESC").
		Find(&tasks)
	h.fillSubtaskProgress(tasks)
	c.JSON(http.StatusOK, tasks)
}

// CompleteTask 标记任务完成
func (h *TaskHandler) CompleteTask(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var task model.Task

	if err := h.DB.Where("user_id = ?", userID).First(&task, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "任务不存在"})
		return
	}

	now := time.Now()
	task.IsCompleted = !task.IsCompleted
	if task.IsCompleted {
		task.CompletedAt = &now

		// 重复任务：完成后自动创建下一个
		if task.RepeatType != "none" {
			h.createNextRepeatTask(task)
		}
	} else {
		task.CompletedAt = nil
	}

	h.DB.Save(&task)
	h.DB.Preload("List").Preload("Tags").First(&task, id)

	// 触发 Webhook + 写入行为事件
	if task.IsCompleted {
		triggerWebhooks(h.DB, userID, model.EventTaskCompleted, map[string]interface{}{
			"id": task.ID, "title": task.Title, "list_id": task.ListID,
		})

		// 写入 behavior_events
		metadata, _ := json.Marshal(map[string]interface{}{
			"title":        task.Title,
			"list_name":    task.List.Name,
			"task_type":    task.TaskType,
			"output_level": task.OutputLevel,
			"mood_before":  task.MoodBefore,
			"mood_after":   task.MoodAfter,
			"milestone":    task.IsMilestone,
		})
		event := model.BehaviorEvent{
			UserID:      userID,
			EventType:   "task_completed",
			EntityType:  "task",
			EntityID:    task.ID,
			SystemTagID: task.SystemTagID,
			OccurredAt:  now,
			Metadata:    string(metadata),
		}
		h.DB.Create(&event)
	}

	c.JSON(http.StatusOK, task)
}

// createNextRepeatTask 创建下一个重复任务
func (h *TaskHandler) createNextRepeatTask(task model.Task) {
	var nextDueDate time.Time
	now := time.Now()

	switch task.RepeatType {
	case "daily":
		if task.DueDate != nil {
			nextDueDate = task.DueDate.AddDate(0, 0, task.RepeatInterval)
		} else {
			nextDueDate = now.AddDate(0, 0, task.RepeatInterval)
		}
	case "weekly":
		if task.RepeatDays != "" {
			nextDueDate = h.nextWeekday(now, task.RepeatDays, task.RepeatInterval)
		} else if task.DueDate != nil {
			nextDueDate = task.DueDate.AddDate(0, 0, 7*task.RepeatInterval)
		} else {
			nextDueDate = now.AddDate(0, 0, 7*task.RepeatInterval)
		}
	case "monthly":
		if task.DueDate != nil {
			nextDueDate = task.DueDate.AddDate(0, task.RepeatInterval, 0)
		} else {
			nextDueDate = now.AddDate(0, task.RepeatInterval, 0)
		}
	case "yearly":
		if task.DueDate != nil {
			nextDueDate = task.DueDate.AddDate(task.RepeatInterval, 0, 0)
		} else {
			nextDueDate = now.AddDate(task.RepeatInterval, 0, 0)
		}
	default:
		return
	}

	nextTask := model.Task{
		UserID:         task.UserID,
		ListID:         task.ListID,
		Title:          task.Title,
		Description:    task.Description,
		DueDate:        &model.FlexibleTime{Time: nextDueDate, Valid: true},
		DueTime:        task.DueTime,
		Priority:       task.Priority,
		RepeatType:     task.RepeatType,
		RepeatInterval: task.RepeatInterval,
		RepeatDays:     task.RepeatDays,
		ReminderAt:     task.ReminderAt,
	}
	h.DB.Create(&nextTask)
}

// nextWeekday 计算下一个指定星期几的日期
func (h *TaskHandler) nextWeekday(from time.Time, repeatDays string, interval int) time.Time {
	for i := 1; i <= 7*interval; i++ {
		candidate := from.AddDate(0, 0, i)
		weekday := int(candidate.Weekday())
		if weekday == 0 {
			weekday = 7
		}
		for _, d := range strings.Split(repeatDays, ",") {
			if d == strconv.Itoa(weekday) {
				return candidate
			}
		}
	}
	return from.AddDate(0, 0, 7*interval)
}

// SearchTasks 全局搜索任务（按标题和描述模糊匹配）
func (h *TaskHandler) SearchTasks(c *gin.Context) {
	userID := c.GetUint("userID")
	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		c.JSON(http.StatusOK, []model.Task{})
		return
	}

	var tasks []model.Task
	searchPattern := "%" + q + "%"

	h.DB.Preload("List").Preload("Tags").
		Where("user_id = ? AND (title ILIKE ? OR description ILIKE ?)", userID, searchPattern, searchPattern).
		Order("created_at DESC").
		Find(&tasks)

	h.fillSubtaskProgress(tasks)
	c.JSON(http.StatusOK, tasks)
}

// GetStats 任务统计：完成率、优先级分布、清单分布
func (h *TaskHandler) GetStats(c *gin.Context) {
	userID := c.GetUint("userID")

	var total, completed int64
	h.DB.Model(&model.Task{}).Where("user_id = ?", userID).Count(&total)
	h.DB.Model(&model.Task{}).Where("user_id = ? AND is_completed = true", userID).Count(&completed)

	// 按优先级统计
	var priorityStats []struct {
		Priority string `json:"priority"`
		Count    int64  `json:"count"`
	}
	h.DB.Model(&model.Task{}).
		Select("priority, count(*) as count").
		Where("user_id = ? AND is_completed = false", userID).
		Group("priority").
		Scan(&priorityStats)

	// 按清单统计
	var listStats []struct {
		ListID    uint   `json:"list_id"`
		ListName  string `json:"list_name"`
		Total     int64  `json:"total"`
		Completed int64  `json:"completed"`
	}
	h.DB.Raw(`
		SELECT t.list_id, l.name as list_name,
			COUNT(*) as total,
			SUM(CASE WHEN t.is_completed THEN 1 ELSE 0 END) as completed
		FROM tasks t
		JOIN lists l ON t.list_id = l.id
		WHERE t.user_id = ?
		GROUP BY t.list_id, l.name
	`, userID).Scan(&listStats)

	// 最近 7 天每日完成数
	var dailyStats []struct {
		Date  string `json:"date"`
		Count int64  `json:"count"`
	}
	h.DB.Raw(`
		SELECT DATE(updated_at) as date, COUNT(*) as count
		FROM tasks
		WHERE user_id = ? AND is_completed = true
			AND updated_at >= CURRENT_DATE - INTERVAL '7 days'
		GROUP BY DATE(updated_at)
		ORDER BY date
	`, userID).Scan(&dailyStats)

	c.JSON(http.StatusOK, gin.H{
		"total":     total,
		"completed": completed,
		"rate":      safeRate(completed, total),
		"priority":  priorityStats,
		"by_list":   listStats,
		"daily":     dailyStats,
	})
}

func safeRate(part, total int64) float64 {
	if total == 0 {
		return 0
	}
	return float64(part) / float64(total) * 100
}

// triggerWebhooks 同步读取配置，异步发送 Webhook
func triggerWebhooks(db *gorm.DB, userID uint, event string, data map[string]interface{}) {
	var webhooks []model.Webhook
	if err := db.Where("user_id = ? AND event = ? AND is_active = ?", userID, event, true).Find(&webhooks).Error; err != nil || len(webhooks) == 0 {
		return
	}

	payload := map[string]interface{}{
		"event":     event,
		"data":      data,
		"timestamp": time.Now().Unix(),
	}
	body, _ := json.Marshal(payload)

	go func(webhooks []model.Webhook, body []byte) {
		for _, wh := range webhooks {
			req, _ := http.NewRequest("POST", wh.URL, bytes.NewBuffer(body))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("User-Agent", "Slowlight-Webhook/1.0")
			if wh.Secret != "" {
				mac := hmac.New(sha256.New, []byte(wh.Secret))
				mac.Write(body)
				req.Header.Set("X-Slowlight-Signature", "sha256="+hex.EncodeToString(mac.Sum(nil)))
			}
			client := &http.Client{Timeout: 10 * time.Second}
			if resp, err := client.Do(req); err != nil {
				log.Printf("[Webhook] 失败 url=%s event=%s err=%v", wh.URL, event, err)
			} else {
				resp.Body.Close()
			}
		}
	}(webhooks, body)
}
