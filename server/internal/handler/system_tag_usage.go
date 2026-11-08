package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

// systemTagUsage is the scope of associations that deleting this managed tag
// would detach. Shared canonical labels survive as long as another alias exists.
type systemTagUsage struct {
	Tasks       int64 `json:"tasks"`
	Habits      int64 `json:"habits"`
	Sessions    int64 `json:"sessions"`
	Reflections int64 `json:"reflections"`
}

func (h *SystemTagHandler) usageForTag(userID, tagID uint) (systemTagUsage, error) {
	var alias model.LegacySystemTagAlias
	canonicalID := uint(0)
	err := h.DB.Where("user_id = ? AND system_tag_id = ?", userID, tagID).
		Take(&alias).Error
	switch {
	case err == nil:
		var others int64
		if err := h.DB.Model(&model.LegacySystemTagAlias{}).
			Where("user_id = ? AND tag_id = ? AND system_tag_id != ?", userID, alias.TagID, tagID).
			Count(&others).Error; err != nil {
			return systemTagUsage{}, err
		}
		if others == 0 {
			canonicalID = alias.TagID
		}
	case errors.Is(err, gorm.ErrRecordNotFound):
		// Legacy-only managed tags can still own task, habit, session links.
	default:
		return systemTagUsage{}, err
	}

	// All table and column names are internal constants, never request input.
	count := func(table, links, foreignKey string, legacy bool, softDelete bool) (int64, error) {
		var total int64
		live := ""
		if softDelete {
			live = " AND records.deleted_at IS NULL"
		}
		sql := "SELECT COUNT(*) FROM (SELECT records.id FROM " + table + " records " +
			"JOIN " + links + " link ON link." + foreignKey + " = records.id " +
			"WHERE records.user_id = ? AND link.tag_id = ?" + live
		args := []interface{}{userID, canonicalID}
		if legacy {
			sql += " UNION SELECT records.id FROM " + table + " records " +
				"WHERE records.user_id = ? AND records.system_tag_id = ?"
			if softDelete {
				sql += " AND records.deleted_at IS NULL"
			}
			args = append(args, userID, tagID)
		}
		sql += ") linked"
		return total, h.DB.Raw(sql, args...).Scan(&total).Error
	}

	tasks, err := count("tasks", "task_tags", "task_id", true, true)
	if err != nil { return systemTagUsage{}, err }
	habits, err := count("habits", "habit_tags", "habit_id", true, true)
	if err != nil { return systemTagUsage{}, err }
	sessions, err := count("work_sessions", "work_session_tags", "work_session_id", true, false)
	if err != nil { return systemTagUsage{}, err }
	reflections, err := count("reflections", "reflection_tags", "reflection_id", false, true)
	if err != nil { return systemTagUsage{}, err }
	return systemTagUsage{
		Tasks: tasks, Habits: habits, Sessions: sessions, Reflections: reflections,
	}, nil
}

// GET /system-tags/usage — one request for all managed labels. Counts are
// computed from owned, live records only, independently of the primary list.
func (h *SystemTagHandler) GetSystemTagUsage(c *gin.Context) {
	userID := c.GetUint("userID")
	var tags []model.SystemTag
	if err := h.DB.Where("user_id = ?", userID).
		Order("sort_order ASC, id ASC").Find(&tags).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "标签关联读取失败"})
		return
	}
	counts := make(map[string]systemTagUsage, len(tags))
	for _, tag := range tags {
		impact, err := h.usageForTag(userID, tag.ID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "标签关联读取失败"})
			return
		}
		counts[strconv.FormatUint(uint64(tag.ID), 10)] = impact
	}
	c.JSON(http.StatusOK, gin.H{"counts": counts})
}
