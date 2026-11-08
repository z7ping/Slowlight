package handler

import (
    "errors"
    "fmt"
	"net/http"
	"strconv"
    "strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type SystemTagHandler struct {
	DB *gorm.DB
}

func NewSystemTagHandler(db *gorm.DB) *SystemTagHandler {
	return &SystemTagHandler{DB: db}
}

// syncSystemTagToCanonical preserves separate ID namespaces while making the
// labels managed on this page available to canonical task/habit tag pickers.
func syncSystemTagToCanonical(tx *gorm.DB, legacy model.SystemTag) error {
    name := strings.TrimSpace(legacy.Name)
    if name == "" { return errors.New("标签名称不能为空") }

    var alias model.LegacySystemTagAlias
    err := tx.Where("user_id = ? AND system_tag_id = ?", legacy.UserID, legacy.ID).Take(&alias).Error
    if errors.Is(err, gorm.ErrRecordNotFound) {
        var canonical model.Tag
        err = tx.Unscoped().Where("user_id = ? AND name = ?", legacy.UserID, name).Take(&canonical).Error
        if errors.Is(err, gorm.ErrRecordNotFound) {
            canonical = model.Tag{UserID: legacy.UserID, Name: name, Color: legacy.Color}
            if err := tx.Create(&canonical).Error; err != nil { return err }
        } else if err != nil { return err } else if canonical.DeletedAt.Valid {
            return fmt.Errorf("同名标签已被删除，不能自动恢复")
        }
        alias = model.LegacySystemTagAlias{UserID: legacy.UserID, SystemTagID: legacy.ID, TagID: canonical.ID}
        if err := tx.Create(&alias).Error; err != nil { return err }
    } else if err != nil { return err }

    var canonical model.Tag
    if err := tx.Where("id = ? AND user_id = ?", alias.TagID, legacy.UserID).First(&canonical).Error; err != nil {
        return fmt.Errorf("对应统一标签不可用: %w", err)
    }
    return tx.Model(&canonical).Updates(map[string]interface{}{
        "name": name, "color": legacy.Color,
    }).Error
}

func (h *SystemTagHandler) GetSystemTags(c *gin.Context) {
	userID := c.GetUint("userID")
	tags := make([]model.SystemTag, 0)
	if err := h.DB.Where("user_id = ?", userID).
		Order("sort_order ASC, id ASC").Find(&tags).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "读取观察标签失败"})
		return
	}
	c.JSON(http.StatusOK, tags)
}

func (h *SystemTagHandler) CreateSystemTag(c *gin.Context) {
	userID := c.GetUint("userID")
	var req struct {
		Name         string             `json:"name" binding:"required"`
		Icon         string             `json:"icon"`
		Color        string             `json:"color"`
		DimensionKey model.DimensionKey `json:"dimension_key"`
		SortOrder    int                `json:"sort_order"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}
	if !model.IsValidDimensionKey(req.DimensionKey) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的 dimension_key"})
		return
	}

	var existing int64
	h.DB.Model(&model.SystemTag{}).Where("user_id = ? AND name = ?", userID, req.Name).Count(&existing)
	if existing > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "标签名称已存在"})
		return
	}

	var maxOrder int
	h.DB.Model(&model.SystemTag{}).Where("user_id = ?", userID).Select("COALESCE(MAX(sort_order), 0)").Scan(&maxOrder)

	tag := model.SystemTag{
		UserID:       userID,
		Name:         req.Name,
		Icon:         req.Icon,
		Color:        req.Color,
		DimensionKey: req.DimensionKey,
		SortOrder:    maxOrder + 1,
		IsDefault:    false,
	}
	if tag.Icon == "" {
		tag.Icon = "🏷️"
	}
	if tag.Color == "" {
		tag.Color = "#1890ff"
	}
	if err := h.DB.Transaction(func(tx *gorm.DB) error {
        if err := tx.Create(&tag).Error; err != nil { return err }
        return syncSystemTagToCanonical(tx, tag)
    }); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建标签失败"})
		return
	}
	c.JSON(http.StatusCreated, tag)
}

func (h *SystemTagHandler) UpdateSystemTag(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var tag model.SystemTag
	if err := h.DB.Where("user_id = ? AND id = ?", userID, id).First(&tag).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "观察标签不存在"})
		return
	}

	var req struct {
		Name         *string             `json:"name"`
		Icon         *string             `json:"icon"`
		Color        *string             `json:"color"`
		DimensionKey *model.DimensionKey `json:"dimension_key"`
		SortOrder    *int                `json:"sort_order"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}

	updates := make(map[string]interface{})
	if req.Name != nil {
		var existing int64
		h.DB.Model(&model.SystemTag{}).Where("user_id = ? AND name = ? AND id != ?", userID, *req.Name, tag.ID).Count(&existing)
		if existing > 0 {
			c.JSON(http.StatusConflict, gin.H{"error": "标签名称已存在"})
			return
		}
		updates["name"] = *req.Name
	}
	if req.Icon != nil {
		updates["icon"] = *req.Icon
	}
	if req.Color != nil {
		updates["color"] = *req.Color
	}
	if req.DimensionKey != nil {
		if !model.IsValidDimensionKey(*req.DimensionKey) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "无效的 dimension_key"})
			return
		}
		updates["dimension_key"] = *req.DimensionKey
	}
	if req.SortOrder != nil {
		updates["sort_order"] = *req.SortOrder
	}
	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "至少需要提供一个字段"})
		return
	}

	if err := h.DB.Transaction(func(tx *gorm.DB) error {
        if err := tx.Model(&tag).Updates(updates).Error; err != nil { return err }
        if err := tx.First(&tag, tag.ID).Error; err != nil { return err }
        return syncSystemTagToCanonical(tx, tag)
    }); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "更新标签失败，请检查名称是否与已有标签冲突"})
		return
	}
	c.JSON(http.StatusOK, tag)
}

func (h *SystemTagHandler) DeleteSystemTag(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var tag model.SystemTag
	if err := h.DB.Where("user_id = ? AND id = ?", userID, id).First(&tag).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "观察标签不存在"})
		return
	}
	if tag.IsDefault {
		c.JSON(http.StatusForbidden, gin.H{"error": "默认观察标签不可删除，但可以重命名"})
		return
	}

	// Old callers without conditions remain compatible. The new X08 dialog
	// sends all four confirmed counts, never an unverified partial subset.
	fields := []string{"expected_tasks", "expected_habits", "expected_sessions", "expected_reflections"}
	var expected systemTagUsage
	provided := 0
	for i, key := range fields {
		raw, ok := c.GetQuery(key)
		if !ok { continue }
		provided++
		value, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || value < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "标签关联核对参数无效"})
			return
		}
		switch i {
		case 0: expected.Tasks = value
		case 1: expected.Habits = value
		case 2: expected.Sessions = value
		case 3: expected.Reflections = value
		}
	}
	if provided != 0 && provided != len(fields) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "标签关联核对参数不完整"})
		return
	}
	errImpactChanged := errors.New("tag association impact changed")
	undoable := c.Query("undoable") == "true"
	if undoable && provided != len(fields) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "可撤销删除需要完整的四类关联核对"})
		return
	}
	var undoToken string
	if err := h.DB.Transaction(func(tx *gorm.DB) error {
        if provided == len(fields) {
            current, err := h.usageForTagDB(tx, userID, tag.ID)
            if err != nil { return err }
            if current != expected { return errImpactChanged }
        }
        var undoSnap *systemTagDeletionSnapshot
        if undoable {
            var err error
            undoSnap, err = captureSystemTagUndo(tx, userID, tag)
            if err != nil { return err }
        }
        if err := tx.Model(&model.Habit{}).Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
            Update("system_tag_id", nil).Error; err != nil { return err }
        if err := tx.Model(&model.Task{}).Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
            Update("system_tag_id", nil).Error; err != nil { return err }
        if err := tx.Model(&model.WorkSession{}).Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).
            Update("system_tag_id", nil).Error; err != nil { return err }
        var alias model.LegacySystemTagAlias
        err := tx.Where("user_id = ? AND system_tag_id = ?", userID, tag.ID).Take(&alias).Error
        if err == nil {
            if err := tx.Delete(&alias).Error; err != nil { return err }
            var other int64
            if err := tx.Model(&model.LegacySystemTagAlias{}).
                Where("user_id = ? AND tag_id = ?", userID, alias.TagID).Count(&other).Error; err != nil { return err }
            if other == 0 {
                // Removing a managed label also removes its canonical associations.
                for _, link := range []interface{}{&model.TaskTag{}, &model.HabitTag{}, &model.WorkSessionTag{}, &model.ReflectionTag{}} {
                    if err := tx.Where("tag_id = ?", alias.TagID).Delete(link).Error; err != nil { return err }
                }
                if undoable {
                    result := tx.Model(&model.Tag{}).
                        Where("id = ? AND user_id = ?", alias.TagID, userID).
                        Update("deleted_at", undoSnap.DeletedAt)
                    if result.Error != nil { return result.Error }
                    if result.RowsAffected != 1 { return errDeletionUndoUnavailable }
                } else if err := tx.Where("id = ? AND user_id = ?", alias.TagID, userID).
                    Delete(&model.Tag{}).Error; err != nil { return err }
            }
        } else if !errors.Is(err, gorm.ErrRecordNotFound) { return err }
        if !undoable { return tx.Delete(&tag).Error }
        deleted := tx.Model(&model.SystemTag{}).
            Where("id = ? AND user_id = ?", tag.ID, userID).
            Update("deleted_at", undoSnap.DeletedAt)
        if deleted.Error != nil { return deleted.Error }
        if deleted.RowsAffected != 1 { return errDeletionUndoUnavailable }
        token, err := saveDeletionUndo(tx, userID, "system_tag", undoSnap)
        if err != nil { return err }
        undoToken = token
        return nil
    }); err != nil {
        if errors.Is(err, errImpactChanged) {
            c.JSON(http.StatusConflict, gin.H{"error": "标签关联已变化，请重新核对删除范围"})
            return
        }
        c.JSON(http.StatusInternalServerError, gin.H{"error": "删除标签失败"}); return
    }
	c.JSON(http.StatusOK, gin.H{
		"message": "删除成功",
		"undo_token": undoToken,
	})
}
