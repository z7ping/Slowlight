package handler

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

// MigrationHandler 处理 dogfooding 阶段的本地数据合并预览。
// 预览端点只比较数据，绝不写入用户数据；执行端点将在同一契约下实现。
type MigrationHandler struct{ DB *gorm.DB }

func NewMigrationHandler(db *gorm.DB) *MigrationHandler { return &MigrationHandler{DB: db} }

type MigrationSnapshot struct {
	ConflictPolicy string             `json:"conflict_policy"`
	Lists          []MigrationList    `json:"lists"`
	Tags           []MigrationTag     `json:"tags"`
	SystemTags     []MigrationTag     `json:"system_tags"`
	Habits         []MigrationHabit   `json:"habits"`
	Tasks          []MigrationTask    `json:"tasks"`
	Subtasks       []MigrationSubtask `json:"subtasks"`
	HabitLogs      []MigrationLog     `json:"habit_logs"`
	Sessions       []MigrationSession `json:"sessions"`
}
type MigrationSubtask struct {
	LocalID     uint   `json:"id"`
	TaskID      uint   `json:"task_id"`
	Title       string `json:"title"`
	IsCompleted bool   `json:"is_completed"`
	SortOrder   int    `json:"sort_order"`
}

type MigrationList struct {
	LocalID uint   `json:"id"`
	Name    string `json:"name"`
	Icon    string `json:"icon"`
	Color   string `json:"color"`
	IsInbox bool   `json:"is_inbox"`
}
type MigrationTag struct {
	LocalID uint   `json:"id"`
	Name    string `json:"name"`
	Icon    string `json:"icon"`
	Color   string `json:"color"`
}
type MigrationHabit struct {
	LocalID           uint   `json:"id"`
	Name              string `json:"name"`
	Icon              string `json:"icon"`
	Color             string `json:"color"`
	Frequency         string `json:"frequency"`
	TargetDays        int    `json:"target_days"`
	PreferredPeriod   string `json:"preferred_period"`
	DurationMin       int    `json:"duration_min"`
	GenerateTask      bool   `json:"generate_task"`
	ShowCheckinDialog bool   `json:"show_checkin_dialog"`
	SpecificTime      string `json:"specific_time"`
	ReminderAt        string `json:"reminder_at"`
	SystemTagID       *uint  `json:"system_tag_id"`
}
type MigrationTask struct {
	LocalID         uint   `json:"id"`
	ListID          uint   `json:"list_id"`
	Title           string `json:"title"`
	Description     string `json:"description"`
	Priority        string `json:"priority"`
	IsCompleted     bool   `json:"is_completed"`
	SortOrder       int    `json:"sort_order"`
	RepeatType      string `json:"repeat_type"`
	RepeatInterval  int    `json:"repeat_interval"`
	RepeatDays      string `json:"repeat_days"`
	TaskType        string `json:"task_type"`
	MoodBefore      int    `json:"mood_before"`
	MoodAfter       int    `json:"mood_after"`
	IsMilestone     bool   `json:"is_milestone"`
	ObsidianLink    string `json:"obsidian_link"`
	OutputLevel     string `json:"output_level"`
	DueDate         string `json:"due_date"`
	DueTime         string `json:"due_time"`
	CompletedAt     string `json:"completed_at"`
	ReminderAt      string `json:"reminder_at"`
	ReminderAdvance int    `json:"reminder_advance_minutes"`
	SystemTagID     *uint  `json:"system_tag_id"`
	TagIDs          []uint `json:"tag_ids"`
}
type MigrationLog struct {
	LocalID     uint   `json:"id"`
	HabitID     uint   `json:"habit_id"`
	TaskID      *uint  `json:"task_id"`
	Date        string `json:"date"`
	Period      string `json:"period"`
	DurationMin int    `json:"duration_min"`
	Note        string `json:"note"`
}
type MigrationSession struct {
	LocalID     uint   `json:"id"`
	SessionType string `json:"session_type"`
	TaskID      *uint  `json:"task_id"`
	SystemTagID *uint  `json:"system_tag_id"`
	StartedAt   string `json:"started_at"`
	EndedAt     string `json:"ended_at"`
	DurationSec int    `json:"duration_sec"`
	Device      string `json:"device"`
}

type MigrationConflict struct {
	Entity  string `json:"entity"`
	LocalID uint   `json:"local_id"`
	Name    string `json:"name"`
	Reason  string `json:"reason"`
}

func (s MigrationSnapshot) Summary() map[string]int {
	return map[string]int{"lists": len(s.Lists), "tags": len(s.Tags), "system_tags": len(s.SystemTags), "habits": len(s.Habits), "tasks": len(s.Tasks), "subtasks": len(s.Subtasks), "habit_logs": len(s.HabitLogs), "sessions": len(s.Sessions)}
}

// PreviewMigration 仅返回同名基础实体冲突，供客户端在执行前要求用户确认。
func (h *MigrationHandler) PreviewMigration(c *gin.Context) {
	userID := c.GetUint("userID")
	var snapshot MigrationSnapshot
	if err := c.ShouldBindJSON(&snapshot); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "迁移数据格式无效"})
		return
	}
	conflicts := make([]MigrationConflict, 0)
	h.collectListConflicts(userID, snapshot.Lists, &conflicts)
	h.collectNamedConflicts(userID, "tag", snapshot.Tags, &conflicts)
	h.collectNamedConflicts(userID, "system_tag", snapshot.SystemTags, &conflicts)
	h.collectHabitConflicts(userID, snapshot.Habits, &conflicts)
	c.JSON(http.StatusOK, gin.H{"summary": snapshot.Summary(), "conflicts": conflicts, "can_execute": true})
}

// ExecuteMigration 在没有未决冲突时把核心实体写入云端。
// 它使用单个数据库事务，确保不会留下半份迁移结果。
func (h *MigrationHandler) ExecuteMigration(c *gin.Context) {
	userID := c.GetUint("userID")
	var snapshot MigrationSnapshot
	if err := c.ShouldBindJSON(&snapshot); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "迁移数据格式无效"})
		return
	}
	snapshotJSON, _ := json.Marshal(snapshot)
	fingerprint := fmt.Sprintf("%x", sha256.Sum256(snapshotJSON))
	var previous model.MigrationReport
	if h.DB.Where("user_id = ? AND fingerprint = ?", userID, fingerprint).First(&previous).Error == nil {
		var created map[string]int
		_ = json.Unmarshal([]byte(previous.Created), &created)
		c.JSON(http.StatusOK, gin.H{"message": "相同迁移已完成", "created": created, "report": previous, "id_map": gin.H{}})
		return
	}
	conflicts := make([]MigrationConflict, 0)
	h.collectListConflicts(userID, snapshot.Lists, &conflicts)
	h.collectNamedConflicts(userID, "tag", snapshot.Tags, &conflicts)
	h.collectNamedConflicts(userID, "system_tag", snapshot.SystemTags, &conflicts)
	h.collectHabitConflicts(userID, snapshot.Habits, &conflicts)
	if len(conflicts) > 0 && snapshot.ConflictPolicy != "both" && snapshot.ConflictPolicy != "cloud" && snapshot.ConflictPolicy != "local" {
		c.JSON(http.StatusConflict, gin.H{"error": "存在未处理冲突", "conflicts": conflicts})
		return
	}

	listIDs, tagIDs, systemTagIDs, habitIDs, taskIDs, subtaskIDs, logIDs, sessionIDs := map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}
	logCount, sessionCount := 0, 0
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		if snapshot.ConflictPolicy == "local" {
			for _, item := range snapshot.Lists {
				if err := h.backupMigrationName(tx, userID, "lists", item.Name); err != nil {
					return err
				}
			}
			for _, item := range snapshot.Tags {
				if err := h.backupMigrationName(tx, userID, "tags", item.Name); err != nil {
					return err
				}
			}
			for _, item := range snapshot.SystemTags {
				if err := h.backupMigrationName(tx, userID, "system_tags", item.Name); err != nil {
					return err
				}
			}
			for _, item := range snapshot.Habits {
				if err := h.backupMigrationName(tx, userID, "habits", item.Name); err != nil {
					return err
				}
			}
		}
		if snapshot.ConflictPolicy == "cloud" {
			for _, item := range snapshot.Lists {
				var row model.List
				if strings.TrimSpace(item.Name) != "" && tx.Where("user_id = ? AND name = ?", userID, item.Name).First(&row).Error == nil {
					listIDs[item.LocalID] = row.ID
				}
			}
			for _, item := range snapshot.Tags {
				var row model.Tag
				if strings.TrimSpace(item.Name) != "" && tx.Where("user_id = ? AND name = ?", userID, item.Name).First(&row).Error == nil {
					tagIDs[item.LocalID] = row.ID
				}
			}
			for _, item := range snapshot.SystemTags {
				var row model.SystemTag
				if strings.TrimSpace(item.Name) != "" && tx.Where("user_id = ? AND name = ?", userID, item.Name).First(&row).Error == nil {
					systemTagIDs[item.LocalID] = row.ID
				}
			}
			for _, item := range snapshot.Habits {
				var row model.Habit
				if strings.TrimSpace(item.Name) != "" && tx.Where("user_id = ? AND name = ?", userID, item.Name).First(&row).Error == nil {
					habitIDs[item.LocalID] = row.ID
				}
			}
		}
		for _, item := range snapshot.Lists {
			if listIDs[item.LocalID] != 0 {
				continue
			}
			if strings.TrimSpace(item.Name) == "" {
				continue
			}
			row := model.List{UserID: userID, Name: item.Name, Icon: item.Icon, Color: item.Color, IsInbox: item.IsInbox}
			if row.Icon == "" {
				row.Icon = "📋"
			}
			if row.Color == "" {
				row.Color = "#1890ff"
			}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			listIDs[item.LocalID] = row.ID
		}
		for _, item := range snapshot.Tags {
			if tagIDs[item.LocalID] != 0 {
				continue
			}
			if strings.TrimSpace(item.Name) == "" {
				continue
			}
			row := model.Tag{UserID: userID, Name: item.Name, Color: item.Color}
			if row.Color == "" {
				row.Color = "#0075de"
			}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			tagIDs[item.LocalID] = row.ID
		}
		for _, item := range snapshot.SystemTags {
			if systemTagIDs[item.LocalID] != 0 {
				continue
			}
			if strings.TrimSpace(item.Name) == "" {
				continue
			}
			row := model.SystemTag{UserID: userID, Name: item.Name, Icon: item.Icon, Color: item.Color}
			if row.Icon == "" {
				row.Icon = "🏷️"
			}
			if row.Color == "" {
				row.Color = "#1890ff"
			}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			systemTagIDs[item.LocalID] = row.ID
		}
		for _, item := range snapshot.Habits {
			if habitIDs[item.LocalID] != 0 {
				continue
			}
			if strings.TrimSpace(item.Name) == "" {
				continue
			}
			row := model.Habit{UserID: userID, Name: item.Name, Icon: item.Icon, Color: item.Color, Frequency: item.Frequency, TargetDays: item.TargetDays, PreferredPeriod: item.PreferredPeriod, DurationMin: item.DurationMin, GenerateTask: item.GenerateTask, ShowCheckinDialog: item.ShowCheckinDialog, SpecificTime: item.SpecificTime, ReminderAt: item.ReminderAt}
			if item.SystemTagID != nil && systemTagIDs[*item.SystemTagID] != 0 {
				mapped := systemTagIDs[*item.SystemTagID]
				row.SystemTagID = &mapped
			}
			if row.Icon == "" {
				row.Icon = "✅"
			}
			if row.Color == "" {
				row.Color = "#52c41a"
			}
			if row.Frequency == "" {
				row.Frequency = "daily"
			}
			if row.ReminderAt == "" {
				row.ReminderAt = "{}"
			}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			habitIDs[item.LocalID] = row.ID
		}
		for _, item := range snapshot.Tasks {
			listID := listIDs[item.ListID]
			if listID == 0 || strings.TrimSpace(item.Title) == "" {
				continue
			}
			row := model.Task{UserID: userID, ListID: listID, Title: item.Title, Description: item.Description, Priority: item.Priority, IsCompleted: item.IsCompleted, SortOrder: item.SortOrder, RepeatType: item.RepeatType, RepeatInterval: item.RepeatInterval, RepeatDays: item.RepeatDays, TaskType: item.TaskType, MoodBefore: item.MoodBefore, MoodAfter: item.MoodAfter, IsMilestone: item.IsMilestone, ObsidianLink: item.ObsidianLink, OutputLevel: item.OutputLevel}
			row.DueDate = migrationFlexibleTime(item.DueDate)
			row.ReminderAt = migrationFlexibleTime(item.ReminderAt)
			row.ReminderAdvanceMinutes = item.ReminderAdvance
			if item.DueTime != "" {
				dueTime := item.DueTime
				row.DueTime = &dueTime
			}
			if item.CompletedAt != "" {
				if completedAt, parseErr := time.Parse(time.RFC3339, item.CompletedAt); parseErr == nil {
					row.CompletedAt = &completedAt
				}
			}
			if item.SystemTagID != nil && systemTagIDs[*item.SystemTagID] != 0 {
				mapped := systemTagIDs[*item.SystemTagID]
				row.SystemTagID = &mapped
			}
			for _, localTagID := range item.TagIDs {
				if mapped := tagIDs[localTagID]; mapped != 0 {
					row.Tags = append(row.Tags, model.Tag{ID: mapped})
				}
			}
			if row.Priority == "" {
				row.Priority = "none"
			}
			if row.RepeatType == "" {
				row.RepeatType = "none"
			}
			if row.RepeatInterval == 0 {
				row.RepeatInterval = 1
			}
			if row.TaskType == "" {
				row.TaskType = "daily"
			}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			taskIDs[item.LocalID] = row.ID
		}
		for _, item := range snapshot.Subtasks {
			taskID := taskIDs[item.TaskID]
			if taskID == 0 || strings.TrimSpace(item.Title) == "" {
				continue
			}
			row := model.Subtask{TaskID: taskID, Title: item.Title, IsCompleted: item.IsCompleted, SortOrder: item.SortOrder}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			subtaskIDs[item.LocalID] = row.ID
		}
		for _, item := range snapshot.HabitLogs {
			habitID := habitIDs[item.HabitID]
			if habitID == 0 || item.Date == "" {
				continue
			}
			var taskID *uint
			if item.TaskID != nil {
				if mapped := taskIDs[*item.TaskID]; mapped != 0 {
					taskID = &mapped
				}
			}
			row := model.HabitLog{HabitID: habitID, TaskID: taskID, Date: item.Date, Period: item.Period, DurationMin: item.DurationMin, Note: item.Note}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			logIDs[item.LocalID] = row.ID
			logCount++
		}
		for _, item := range snapshot.Sessions {
			startedAt, err := time.Parse(time.RFC3339, item.StartedAt)
			if err != nil || item.SessionType == "" {
				continue
			}
			row := model.WorkSession{UserID: userID, SessionType: item.SessionType, StartedAt: startedAt, DurationSec: item.DurationSec, Device: item.Device}
			if item.EndedAt != "" {
				if endedAt, parseErr := time.Parse(time.RFC3339, item.EndedAt); parseErr == nil {
					row.EndedAt = &endedAt
				}
			}
			if item.TaskID != nil && taskIDs[*item.TaskID] != 0 {
				mapped := taskIDs[*item.TaskID]
				row.TaskID = &mapped
			}
			if item.SystemTagID != nil && systemTagIDs[*item.SystemTagID] != 0 {
				mapped := systemTagIDs[*item.SystemTagID]
				row.SystemTagID = &mapped
			}
			if err := tx.Create(&row).Error; err != nil {
				return err
			}
			sessionIDs[item.LocalID] = row.ID
			sessionCount++
		}
		return nil
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "迁移执行失败: " + err.Error()})
		return
	}
	created := map[string]int{"lists": len(listIDs), "tags": len(tagIDs), "system_tags": len(systemTagIDs), "habits": len(habitIDs), "tasks": len(taskIDs), "subtasks": len(subtaskIDs), "habit_logs": logCount, "sessions": sessionCount}
	createdJSON, _ := json.Marshal(created)
	report := model.MigrationReport{UserID: userID, ConflictPolicy: snapshot.ConflictPolicy, Status: "succeeded", Fingerprint: fingerprint, Created: string(createdJSON)}
	if err := h.DB.Create(&report).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "迁移报告保存失败"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "数据迁移完成", "created": created, "report": report, "id_map": gin.H{"lists": listIDs, "tags": tagIDs, "system_tags": systemTagIDs, "habits": habitIDs, "tasks": taskIDs, "subtasks": subtaskIDs, "habit_logs": logIDs, "sessions": sessionIDs}})
}

func (h *MigrationHandler) GetLatestReport(c *gin.Context) {
	var report model.MigrationReport
	if err := h.DB.Where("user_id = ?", c.GetUint("userID")).Order("created_at DESC").First(&report).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "暂无迁移报告"})
		return
	}
	c.JSON(http.StatusOK, report)
}

func (h *MigrationHandler) GetReports(c *gin.Context) {
	var reports []model.MigrationReport
	if err := h.DB.Where("user_id = ?", c.GetUint("userID")).Order("created_at DESC").Limit(20).Find(&reports).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取迁移报告失败"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"reports": reports})
}

func migrationFlexibleTime(value string) *model.FlexibleTime {
	if value == "" {
		return nil
	}
	data, _ := json.Marshal(value)
	var result model.FlexibleTime
	if result.UnmarshalJSON(data) != nil {
		return nil
	}
	return &result
}

func (h *MigrationHandler) backupMigrationName(tx *gorm.DB, userID uint, table, name string) error {
	if strings.TrimSpace(name) == "" {
		return nil
	}
	var count int64
	if err := tx.Table(table).Where("user_id = ? AND name = ?", userID, name).Count(&count).Error; err != nil || count == 0 {
		return err
	}
	backup := name + "（云端备份）"
	for index := 2; ; index++ {
		var exists int64
		if err := tx.Table(table).Where("user_id = ? AND name = ?", userID, backup).Count(&exists).Error; err != nil {
			return err
		}
		if exists == 0 {
			break
		}
		backup = name + "（云端备份 " + strconv.Itoa(index) + "）"
	}
	return tx.Table(table).Where("user_id = ? AND name = ?", userID, name).Update("name", backup).Error
}

func (h *MigrationHandler) collectListConflicts(userID uint, items []MigrationList, conflicts *[]MigrationConflict) {
	for _, item := range items {
		if strings.TrimSpace(item.Name) == "" {
			continue
		}
		var count int64
		h.DB.Model(&model.List{}).Where("user_id = ? AND name = ?", userID, item.Name).Count(&count)
		if count > 0 {
			*conflicts = append(*conflicts, MigrationConflict{Entity: "list", LocalID: item.LocalID, Name: item.Name, Reason: "云端存在同名记录"})
		}
	}
}

func (h *MigrationHandler) collectNamedConflicts(userID uint, entity string, items []MigrationTag, conflicts *[]MigrationConflict) {
	for _, item := range items {
		if strings.TrimSpace(item.Name) == "" {
			continue
		}
		var count int64
		switch entity {
		case "tag":
			h.DB.Model(&model.Tag{}).Where("user_id = ? AND name = ?", userID, item.Name).Count(&count)
		case "system_tag":
			h.DB.Model(&model.SystemTag{}).Where("user_id = ? AND name = ?", userID, item.Name).Count(&count)
		}
		if count > 0 {
			*conflicts = append(*conflicts, MigrationConflict{Entity: entity, LocalID: item.LocalID, Name: item.Name, Reason: "云端存在同名记录"})
		}
	}
}

func (h *MigrationHandler) collectHabitConflicts(userID uint, items []MigrationHabit, conflicts *[]MigrationConflict) {
	for _, item := range items {
		if strings.TrimSpace(item.Name) == "" {
			continue
		}
		var count int64
		h.DB.Model(&model.Habit{}).Where("user_id = ? AND name = ?", userID, item.Name).Count(&count)
		if count > 0 {
			*conflicts = append(*conflicts, MigrationConflict{Entity: "habit", LocalID: item.LocalID, Name: item.Name, Reason: "云端存在同名记录"})
		}
	}
}
