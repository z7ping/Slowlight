package handler

import (
	"net/http"

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

func (h *SystemTagHandler) GetSystemTags(c *gin.Context) {
	userID := c.GetUint("userID")
	var tags []model.SystemTag
	h.DB.Where("user_id = ?", userID).Order("sort_order ASC").Find(&tags)
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
	if err := h.DB.Create(&tag).Error; err != nil {
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

	if err := h.DB.Model(&tag).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新标签失败"})
		return
	}
	h.DB.First(&tag, tag.ID)
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

	h.DB.Model(&model.Habit{}).Where("system_tag_id = ?", tag.ID).Update("system_tag_id", nil)
	h.DB.Model(&model.Task{}).Where("system_tag_id = ?", tag.ID).Update("system_tag_id", nil)
	h.DB.Delete(&tag)
	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}
