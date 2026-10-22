package handler

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
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
	SourceID       string             `json:"source_id"`
	ConflictPolicy string             `json:"conflict_policy"`
	ConflictChoices []MigrationConflictChoice `json:"conflict_choices"`
	PreviewVersion string `json:"preview_version"`
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

type MigrationConflictChoice struct {
	Entity string `json:"entity"`
	LocalID uint `json:"local_id"`
	Policy string `json:"policy"`
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

// migrationPreviewVersion binds a snapshot and the observed target conflicts.
// Recompute within the execution transaction to reject changes since preview.
func migrationPreviewVersion(snapshot MigrationSnapshot, conflicts []MigrationConflict) string {
	snapshot.ConflictPolicy = ""
	snapshot.ConflictChoices = nil
	snapshot.PreviewVersion = ""
	payload, _ := json.Marshal(struct {
		Snapshot MigrationSnapshot `json:"snapshot"`
		Conflicts []MigrationConflict `json:"conflicts"`
	}{snapshot, conflicts})
	return fmt.Sprintf("%x", sha256.Sum256(payload))
}

func migrationConflictKey(entity string, id uint) string {
	return fmt.Sprintf("%s:%d", entity, id)
}

// The new client requires an explicit choice for every observed conflict.
// Old clients retain their legacy global conflict_policy contract.
func migrationPolicies(snapshot MigrationSnapshot, conflicts []MigrationConflict) (map[string]string, error) {
	allowed := map[string]bool{"cloud": true, "local": true, "both": true}
	choices := make(map[string]string, len(conflicts))
	if snapshot.PreviewVersion != "" {
		for _, choice := range snapshot.ConflictChoices {
			key := migrationConflictKey(choice.Entity, choice.LocalID)
			if !allowed[choice.Policy] {
				return nil, errors.New("不支持的迁移冲突策略")
			}
			if _, exists := choices[key]; exists {
				return nil, errors.New("迁移冲突选择重复")
			}
			choices[key] = choice.Policy
		}
		if len(choices) != len(conflicts) {
			return nil, errors.New("尚有迁移冲突未处理")
		}
		for _, conflict := range conflicts {
			if !allowed[choices[migrationConflictKey(conflict.Entity, conflict.LocalID)]] {
				return nil, errors.New("迁移冲突选择已过期")
			}
		}
		return choices, nil
	}
	if len(conflicts) > 0 && !allowed[snapshot.ConflictPolicy] {
		return nil, errors.New("存在未处理冲突")
	}
	for _, conflict := range conflicts {
		choices[migrationConflictKey(conflict.Entity, conflict.LocalID)] = snapshot.ConflictPolicy
	}
	return choices, nil
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
    // A new preview must not offer execution if this source has already uploaded
    // a different snapshot. The exact fingerprint is checked during execute.
    payload, _ := json.Marshal(snapshot)
    fingerprint := fmt.Sprintf("%x", sha256.Sum256(payload))
    var existing model.MigrationReport
    if err := h.DB.Where("user_id = ? AND (source_id = ? OR source_id = '') AND fingerprint <> ?",
        userID, snapshot.SourceID, fingerprint).First(&existing).Error; err == nil {
        c.JSON(http.StatusConflict, gin.H{"error": "该本地数据源已有迁移记录，请先核对云端数据再重新迁移", "can_execute": false})
        return
    }
	c.JSON(http.StatusOK, gin.H{"summary": snapshot.Summary(), "conflicts": conflicts, "preview_version": migrationPreviewVersion(snapshot, conflicts), "can_execute": true})
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
	snapshotJSON, err := json.Marshal(snapshot)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "迁移数据格式无效"})
		return
	}
	fingerprint := fmt.Sprintf("%x", sha256.Sum256(snapshotJSON))
	if len(snapshot.SourceID) > 64 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "迁移来源标识过长"})
		return
	}
	var report model.MigrationReport
	var created map[string]int
	var idMap interface{}
	var replayed bool
	var conflicts []MigrationConflict
	errUnresolvedConflict := errors.New("存在未处理冲突")
	errStalePreview := errors.New("迁移预览已过期，请重新扫描和确认")
	errMissingIDMap := errors.New("历史迁移报告缺少 ID 映射，已阻止重复导入，请先备份并核对云端数据")
	errChangedSnapshot := errors.New("同一本地数据源已有不同快照的迁移报告；请先核对云端差异，避免重复导入")

	listIDs, tagIDs, systemTagIDs, habitIDs, taskIDs, subtaskIDs, logIDs, sessionIDs := map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}, map[uint]uint{}
	logCount, sessionCount := 0, 0
	err = h.DB.Transaction(func(tx *gorm.DB) error {
		// Lock the account across the lookup and commit so concurrent retries cannot duplicate data.
		if tx.Dialector.Name() == "postgres" {
			if err := tx.Exec("SELECT pg_advisory_xact_lock(?)", int64(userID)).Error; err != nil {
				return err
			}
		}
		var previous model.MigrationReport
		if err := tx.Where("user_id = ? AND fingerprint = ?", userID, fingerprint).First(&previous).Error; err == nil {
			var priorCreated map[string]int
			var priorIDMap map[string]map[string]uint
			if previous.IDMap == "" || json.Unmarshal([]byte(previous.IDMap), &priorIDMap) != nil ||
				json.Unmarshal([]byte(previous.Created), &priorCreated) != nil || priorIDMap == nil {
				return errMissingIDMap
			}
			report, created, idMap, replayed = previous, priorCreated, priorIDMap, true
			return nil
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
        // A changed snapshot from the same local database must not import old rows twice.
        // Legacy reports have no source identifier; block automatic follow-up until reconciled.
        var previousSource model.MigrationReport
        check := tx.Where("user_id = ? AND (source_id = ? OR source_id = '')",
            userID, snapshot.SourceID).First(&previousSource)
        if check.Error == nil {
            return errChangedSnapshot
        }
        if !errors.Is(check.Error, gorm.ErrRecordNotFound) {
            return check.Error
        }
		conflicts = make([]MigrationConflict, 0)
		locked := MigrationHandler{DB: tx}
		locked.collectListConflicts(userID, snapshot.Lists, &conflicts)
		locked.collectNamedConflicts(userID, "tag", snapshot.Tags, &conflicts)
		locked.collectNamedConflicts(userID, "system_tag", snapshot.SystemTags, &conflicts)
		locked.collectHabitConflicts(userID, snapshot.Habits, &conflicts)
		if snapshot.PreviewVersion != "" && migrationPreviewVersion(snapshot, conflicts) != snapshot.PreviewVersion {
			return errStalePreview
		}
		policies, policyErr := migrationPolicies(snapshot, conflicts)
		if policyErr != nil {
			return errUnresolvedConflict
		}
		policyFor := func(entity string, id uint) string {
			return policies[migrationConflictKey(entity, id)]
		}
		// The explicit per-item policy is always resolved against current conflicts.
		_ = policyFor
		if len(conflicts) > 0 {
			for _, item := range snapshot.Lists {
				if policyFor("list", item.LocalID) != "local" { continue }
				if err := h.backupMigrationName(tx, userID, "lists", item.Name); err != nil {
					return err
				}
			}
			for _, item := range snapshot.Tags {
				if policyFor("tag", item.LocalID) != "local" { continue }
				if err := h.backupMigrationName(tx, userID, "tags", item.Name); err != nil {
					return err
				}
			}
			for _, item := range snapshot.SystemTags {
				if policyFor("system_tag", item.LocalID) != "local" { continue }
				if err := h.backupMigrationName(tx, userID, "system_tags", item.Name); err != nil {
					return err
				}
			}
			for _, item := range snapshot.Habits {
				if policyFor("habit", item.LocalID) != "local" { continue }
				if err := h.backupMigrationName(tx, userID, "habits", item.Name); err != nil {
					return err
				}
			}
		}
		if len(conflicts) > 0 {
			for _, item := range snapshot.Lists {
				if policyFor("list", item.LocalID) != "cloud" { continue }
				var row model.List
				if strings.TrimSpace(item.Name) != "" && tx.Where("user_id = ? AND name = ?", userID, item.Name).First(&row).Error == nil {
					listIDs[item.LocalID] = row.ID
				}
			}
			for _, item := range snapshot.Tags {
				if policyFor("tag", item.LocalID) != "cloud" { continue }
				var row model.Tag
				if strings.TrimSpace(item.Name) != "" && tx.Where("user_id = ? AND name = ?", userID, item.Name).First(&row).Error == nil {
					tagIDs[item.LocalID] = row.ID
				}
			}
			for _, item := range snapshot.SystemTags {
				if policyFor("system_tag", item.LocalID) != "cloud" { continue }
				var row model.SystemTag
				if strings.TrimSpace(item.Name) != "" && tx.Where("user_id = ? AND name = ?", userID, item.Name).First(&row).Error == nil {
					systemTagIDs[item.LocalID] = row.ID
				}
			}
			for _, item := range snapshot.Habits {
				if policyFor("habit", item.LocalID) != "cloud" { continue }
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
			name := item.Name
			if policyFor("list", item.LocalID) == "both" {
				var nameErr error
				name, nameErr = h.migrationCopyName(tx, userID, "lists", item.Name)
				if nameErr != nil { return nameErr }
			}
			row := model.List{UserID: userID, Name: name, Icon: item.Icon, Color: item.Color, IsInbox: item.IsInbox}
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
			name := item.Name
			if policyFor("tag", item.LocalID) == "both" {
				var nameErr error
				name, nameErr = h.migrationCopyName(tx, userID, "tags", item.Name)
				if nameErr != nil { return nameErr }
			}
			row := model.Tag{UserID: userID, Name: name, Color: item.Color}
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
			name := item.Name
			if policyFor("system_tag", item.LocalID) == "both" {
				var nameErr error
				name, nameErr = h.migrationCopyName(tx, userID, "system_tags", item.Name)
				if nameErr != nil { return nameErr }
			}
			row := model.SystemTag{UserID: userID, Name: name, Icon: item.Icon, Color: item.Color}
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
			name := item.Name
			if policyFor("habit", item.LocalID) == "both" {
				var nameErr error
				name, nameErr = h.migrationCopyName(tx, userID, "habits", item.Name)
				if nameErr != nil { return nameErr }
			}
			row := model.Habit{UserID: userID, Name: name, Icon: item.Icon, Color: item.Color, Frequency: item.Frequency, TargetDays: item.TargetDays, PreferredPeriod: item.PreferredPeriod, DurationMin: item.DurationMin, GenerateTask: item.GenerateTask, ShowCheckinDialog: item.ShowCheckinDialog, SpecificTime: item.SpecificTime, ReminderAt: item.ReminderAt}
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
		created = map[string]int{"lists": len(listIDs), "tags": len(tagIDs), "system_tags": len(systemTagIDs), "habits": len(habitIDs), "tasks": len(taskIDs), "subtasks": len(subtaskIDs), "habit_logs": logCount, "sessions": sessionCount}
		createdJSON, err := json.Marshal(created)
		if err != nil {
			return err
		}
		idMap = gin.H{"lists": listIDs, "tags": tagIDs, "system_tags": systemTagIDs, "habits": habitIDs, "tasks": taskIDs, "subtasks": subtaskIDs, "habit_logs": logIDs, "sessions": sessionIDs}
		idMapJSON, err := json.Marshal(idMap)
		if err != nil {
			return err
		}
		// Commit business entities and replay receipt in the same transaction.
		report = model.MigrationReport{UserID: userID, ConflictPolicy: snapshot.ConflictPolicy, Status: "succeeded", Fingerprint: fingerprint, Created: string(createdJSON), IDMap: string(idMapJSON), SourceID: snapshot.SourceID}
		return tx.Create(&report).Error
	})
	if err != nil {
		if errors.Is(err, errUnresolvedConflict) || errors.Is(err, errStalePreview) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "conflicts": conflicts})
			return
		}
		if errors.Is(err, errMissingIDMap) || errors.Is(err, errChangedSnapshot) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "迁移执行失败: " + err.Error()})
		return
	}
	message := "数据迁移完成"
	if replayed {
		message = "相同迁移已完成"
	}
	c.JSON(http.StatusOK, gin.H{"message": message, "created": created, "report": report, "id_map": idMap})
}

// RecoverMigration only fetches a committed receipt; it never writes/imports entities.
func (h *MigrationHandler) RecoverMigration(c *gin.Context) {
	var snapshot MigrationSnapshot
	if err := c.ShouldBindJSON(&snapshot); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "迁移恢复快照格式无效"})
		return
	}
	payload, err := json.Marshal(snapshot)
	if err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "迁移恢复快照格式无效"}); return }
	fingerprint := fmt.Sprintf("%x", sha256.Sum256(payload))
	var report model.MigrationReport
	if err := h.DB.Where("user_id = ? AND fingerprint = ? AND status = ?",
		c.GetUint("userID"), fingerprint, "succeeded").First(&report).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "未查到这次迁移的已提交回执，当前结果仍未确认；不会自动重新导入"})
		return
	}
	var idMap map[string]map[string]uint
	var created map[string]int
	if report.IDMap == "" || json.Unmarshal([]byte(report.IDMap), &idMap) != nil || idMap == nil ||
		json.Unmarshal([]byte(report.Created), &created) != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "迁移回执缺少完整映射，已停止自动恢复"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id_map": idMap, "created": created, "report": report})
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

// migrationCopyName reserves a non-conflicting name for the extra local copy.
func (h *MigrationHandler) migrationCopyName(tx *gorm.DB, userID uint, table, name string) (string, error) {
	base := name + "（本地副本）"
	for index := 1; index <= 10000; index++ {
		candidate := base
		if index > 1 { candidate = fmt.Sprintf("%s（本地副本 %d）", name, index) }
		var count int64
		if err := tx.Table(table).Where("user_id = ? AND name = ?", userID, candidate).Count(&count).Error; err != nil { return "", err }
		if count == 0 { return candidate, nil }
	}
	return "", errors.New("无法为同名记录生成可用的副本名称")
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
