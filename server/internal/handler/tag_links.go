package handler

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// TagLinksHandler unifies tag associations for existing records without
// adding competing "system tag" or "dimension" API concepts.
type TagLinksHandler struct{ DB *gorm.DB }

func NewTagLinksHandler(db *gorm.DB) *TagLinksHandler {
	return &TagLinksHandler{DB: db}
}

type tagLinkSpec struct {
	table string
	links string
	foreignKey string
	hasSoftDelete bool
}

func resolveTagLinkSpec(value string) (tagLinkSpec, bool) {
	switch value {
	case "task":
		return tagLinkSpec{"tasks", "task_tags", "task_id", true}, true
	case "habit":
		return tagLinkSpec{"habits", "habit_tags", "habit_id", true}, true
	case "session":
		return tagLinkSpec{"work_sessions", "work_session_tags", "work_session_id", false}, true
	case "observation", "reflection":
		return tagLinkSpec{"reflections", "reflection_tags", "reflection_id", true}, true
	default:
		return tagLinkSpec{}, false
	}
}

func (h *TagLinksHandler) resolve(c *gin.Context, tx *gorm.DB, lock bool) (tagLinkSpec, uint, bool) {
	spec, ok := resolveTagLinkSpec(c.Param("entity"))
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的记录类型"})
		return spec, 0, false
	}
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "记录 ID 无效"})
		return spec, 0, false
	}
	query := tx.Table(spec.table).Where("id = ? AND user_id = ?", id, c.GetUint("userID"))
	if spec.hasSoftDelete {
		query = query.Where("deleted_at IS NULL")
	}
	if lock {
		query = query.Clauses(clause.Locking{Strength: "UPDATE"})
	}
	var entity struct{ ID uint }
	if err := query.Select("id").Take(&entity).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "记录不存在"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "查询记录失败"})
		}
		return spec, 0, false
	}
	return spec, entity.ID, true
}

func (h *TagLinksHandler) list(tx *gorm.DB, spec tagLinkSpec, id uint, userID uint) ([]model.Tag, error) {
	var result []model.Tag
	err := tx.Table("tags").
		Joins("JOIN "+spec.links+" ON "+spec.links+".tag_id = tags.id").
		Where(spec.links+"."+spec.foreignKey+" = ? AND tags.user_id = ? AND tags.deleted_at IS NULL", id, userID).
		Order("tags.created_at ASC, tags.id ASC").
		Find(&result).Error
	return result, err
}

func tagLinksPayload(tags []model.Tag) gin.H {
	ids := make([]uint, 0, len(tags))
	for _, tag := range tags {
		ids = append(ids, tag.ID)
	}
	return gin.H{"tag_ids": ids, "tags": tags}
}

func (h *TagLinksHandler) Get(c *gin.Context) {
	spec, id, ok := h.resolve(c, h.DB, false)
	if !ok {
		return
	}
	tags, err := h.list(h.DB, spec, id, c.GetUint("userID"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "读取标签失败"})
		return
	}
	c.JSON(http.StatusOK, tagLinksPayload(tags))
}

// Put atomically replaces all labels. Empty [] explicitly clears links;
// omitting tag_ids, null or an invalid ID is rejected to prevent data loss.
func (h *TagLinksHandler) Put(c *gin.Context) {
	var request map[string]json.RawMessage
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求格式错误"})
		return
	}
	raw, ok := request["tag_ids"]
	if !ok || len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "必须传入 tag_ids 数组"})
		return
	}
	var ids []uint
	if err := json.Unmarshal(raw, &ids); err != nil || ids == nil || len(ids) > 64 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tag_ids 必须是最多 64 个标签 ID 的数组"})
		return
	}
	unique := make([]uint, 0, len(ids))
	seen := make(map[uint]struct{}, len(ids))
	for _, id := range ids {
		if id == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "标签 ID 无效"})
			return
		}
		if _, exists := seen[id]; !exists {
			unique = append(unique, id)
			seen[id] = struct{}{}
		}
	}
	userID := c.GetUint("userID")
	var response []model.Tag
	handled := false
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		spec, id, ok := h.resolve(c, tx, true)
		if !ok {
			handled = true
			return errors.New("invalid entity")
		}
		if len(unique) > 0 {
			var count int64
			if err := tx.Model(&model.Tag{}).Where("user_id = ? AND id IN ?", userID, unique).Count(&count).Error; err != nil {
				return err
			}
			if count != int64(len(unique)) {
				c.JSON(http.StatusBadRequest, gin.H{"error": "标签不存在或不属于当前用户"})
				handled = true
				return errors.New("invalid tag")
			}
		}
		if err := tx.Exec("DELETE FROM "+spec.links+" WHERE "+spec.foreignKey+" = ?", id).Error; err != nil {
			return err
		}
		for _, tagID := range unique {
			row := map[string]interface{}{spec.foreignKey: id, "tag_id": tagID}
			if err := tx.Table(spec.links).Create(row).Error; err != nil {
				return err
			}
		}
		var listErr error
		response, listErr = h.list(tx, spec, id, userID)
		return listErr
	})
	if err != nil {
		if !handled {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "保存标签失败"})
		}
		return
	}
	c.JSON(http.StatusOK, tagLinksPayload(response))
}
