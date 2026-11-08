package handler

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

// A deleted legacy label may own a canonical tag and four association tables.
// Every original row ID is captured before deletion; undo never creates a
// replacement label with new identity.
type systemTagDeletionSnapshot struct {
	TagID            uint                  `json:"tag_id"`
	DeletedAt        time.Time             `json:"deleted_at"`
	TaskIDs          []uint                `json:"task_ids"`
	HabitIDs         []uint                `json:"habit_ids"`
	SessionIDs       []uint                `json:"session_ids"`
	Alias            *model.LegacySystemTagAlias `json:"alias,omitempty"`
	CanonicalID      uint                  `json:"canonical_id"`
	CanonicalDeleted bool                  `json:"canonical_deleted"`
	TaskLinks        []model.TaskTag       `json:"task_links"`
	HabitLinks       []model.HabitTag      `json:"habit_links"`
	SessionLinks     []model.WorkSessionTag `json:"session_links"`
	ReflectionLinks  []model.ReflectionTag `json:"reflection_links"`
}

func captureSystemTagUndo(
	tx *gorm.DB, userID uint, tag model.SystemTag,
) (*systemTagDeletionSnapshot, error) {
	snap := &systemTagDeletionSnapshot{
		TagID: tag.ID,
		DeletedAt: time.Now().UTC().Truncate(time.Microsecond),
	}
	if err := tx.Unscoped().Model(&model.Task{}).
		Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
		Pluck("id", &snap.TaskIDs).Error; err != nil { return nil, err }
	if err := tx.Unscoped().Model(&model.Habit{}).
		Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
		Pluck("id", &snap.HabitIDs).Error; err != nil { return nil, err }
	if err := tx.Model(&model.WorkSession{}).
		Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
		Pluck("id", &snap.SessionIDs).Error; err != nil { return nil, err }

	var alias model.LegacySystemTagAlias
	err := tx.Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
		Take(&alias).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound { return snap, nil }
		return nil, err
	}
	snap.Alias = &alias
	snap.CanonicalID = alias.TagID
	var others int64
	if err := tx.Model(&model.LegacySystemTagAlias{}).
		Where("user_id = ? AND tag_id = ? AND system_tag_id != ?",
			userID, alias.TagID, tag.ID).Count(&others).Error; err != nil {
		return nil, err
	}
	if others != 0 { return snap, nil }
	snap.CanonicalDeleted = true
	var canonical model.Tag
	if err := tx.Where("user_id = ? AND id = ?", userID, alias.TagID).
		First(&canonical).Error; err != nil { return nil, err }
	if err := tx.Where("tag_id = ?", alias.TagID).
		Find(&snap.TaskLinks).Error; err != nil { return nil, err }
	if err := tx.Where("tag_id = ?", alias.TagID).
		Find(&snap.HabitLinks).Error; err != nil { return nil, err }
	if err := tx.Where("tag_id = ?", alias.TagID).
		Find(&snap.SessionLinks).Error; err != nil { return nil, err }
	if err := tx.Where("tag_id = ?", alias.TagID).
		Find(&snap.ReflectionLinks).Error; err != nil { return nil, err }
	return snap, nil
}

// POST /system-tags/undo — original tag ID, canonical ID and exact links
// are restored as one transaction or none of them are restored.
func (h *SystemTagHandler) UndoSystemTagDelete(c *gin.Context) {
	userID := c.GetUint("userID")
	var request struct {
		Token string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "撤销凭据不能为空"})
		return
	}
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		raw, stored, err := loadDeletionUndo(
			tx, userID, request.Token, "system_tag")
		if err != nil { return err }
		var snap systemTagDeletionSnapshot
		if err := json.Unmarshal(raw, &snap); err != nil {
			return errDeletionUndoUnavailable
		}
		if snap.CanonicalDeleted {
			restored := tx.Unscoped().Model(&model.Tag{}).
				Where("id = ? AND user_id = ? AND deleted_at = ?",
					snap.CanonicalID, userID, snap.DeletedAt).
				Update("deleted_at", nil)
			if restored.Error != nil { return restored.Error }
			if restored.RowsAffected != 1 { return errDeletionUndoUnavailable }
		}
		tag := tx.Unscoped().Model(&model.SystemTag{}).
			Where("id = ? AND user_id = ? AND deleted_at = ?",
				snap.TagID, userID, snap.DeletedAt).
			Update("deleted_at", nil)
		if tag.Error != nil { return tag.Error }
		if tag.RowsAffected != 1 { return errDeletionUndoUnavailable }

		if snap.Alias != nil {
			if !snap.CanonicalDeleted {
				var count int64
				if err := tx.Model(&model.Tag{}).
					Where("id = ? AND user_id = ?", snap.CanonicalID, userID).
					Count(&count).Error; err != nil { return err }
				if count != 1 { return errDeletionUndoUnavailable }
			}
			if err := tx.Create(snap.Alias).Error; err != nil { return err }
		}
		for _, link := range snap.TaskLinks {
			if err := tx.Create(&link).Error; err != nil { return err }
		}
		for _, link := range snap.HabitLinks {
			if err := tx.Create(&link).Error; err != nil { return err }
		}
		for _, link := range snap.SessionLinks {
			if err := tx.Create(&link).Error; err != nil { return err }
		}
		for _, link := range snap.ReflectionLinks {
			if err := tx.Create(&link).Error; err != nil { return err }
		}

		if len(snap.TaskIDs) > 0 {
			r := tx.Unscoped().Model(&model.Task{}).
				Where("user_id = ? AND id IN ? AND system_tag_id IS NULL",
					userID, snap.TaskIDs).Update("system_tag_id", snap.TagID)
			if r.Error != nil { return r.Error }
			if r.RowsAffected != int64(len(snap.TaskIDs)) {
				return errDeletionUndoUnavailable
			}
		}
		if len(snap.HabitIDs) > 0 {
			r := tx.Unscoped().Model(&model.Habit{}).
				Where("user_id = ? AND id IN ? AND system_tag_id IS NULL",
					userID, snap.HabitIDs).Update("system_tag_id", snap.TagID)
			if r.Error != nil { return r.Error }
			if r.RowsAffected != int64(len(snap.HabitIDs)) {
				return errDeletionUndoUnavailable
			}
		}
		if len(snap.SessionIDs) > 0 {
			r := tx.Model(&model.WorkSession{}).
				Where("user_id = ? AND id IN ? AND system_tag_id IS NULL",
					userID, snap.SessionIDs).Update("system_tag_id", snap.TagID)
			if r.Error != nil { return r.Error }
			if r.RowsAffected != int64(len(snap.SessionIDs)) {
				return errDeletionUndoUnavailable
			}
		}
		return tx.Delete(stored).Error
	})
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "标签撤销未执行：关联或凭据已变化"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "原标签及关联已恢复"})
}
