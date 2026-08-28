package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type TagHandler struct {
	DB *gorm.DB
}

func NewTagHandler(db *gorm.DB) *TagHandler {
	return &TagHandler{DB: db}
}

// GetTags 获取用户所有标签
func (h *TagHandler) GetTags(c *gin.Context) {
	userID := c.GetUint("userID")
	var tags []model.Tag

	h.DB.Where("user_id = ?", userID).
		Order("name ASC").
		Find(&tags)

	c.JSON(http.StatusOK, tags)
}

// CreateTag 创建标签
func (h *TagHandler) CreateTag(c *gin.Context) {
	userID := c.GetUint("userID")
	var tag model.Tag

	if err := c.ShouldBindJSON(&tag); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tag.UserID = userID

	// 检查是否已存在同名标签
	var existing model.Tag
	if err := h.DB.Where("user_id = ? AND name = ?", userID, tag.Name).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "标签名称已存在"})
		return
	}

	if err := h.DB.Create(&tag).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, tag)
}

// UpdateTag 更新标签
func (h *TagHandler) UpdateTag(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var tag model.Tag

	if err := h.DB.Where("user_id = ? AND id = ?", userID, id).First(&tag).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "标签不存在"})
		return
	}

	var updateData model.Tag
	if err := c.ShouldBindJSON(&updateData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 检查是否与其他标签重名（排除当前标签）
	if updateData.Name != "" && updateData.Name != tag.Name {
		var existing model.Tag
		if err := h.DB.Where("user_id = ? AND name = ? AND id != ?", userID, updateData.Name, tag.ID).First(&existing).Error; err == nil {
			c.JSON(http.StatusConflict, gin.H{"error": "标签名称已存在"})
			return
		}
	}

	h.DB.Model(&tag).Updates(updateData)
	h.DB.First(&tag, tag.ID)

	c.JSON(http.StatusOK, tag)
}

// DeleteTag 删除标签
func (h *TagHandler) DeleteTag(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var tag model.Tag
	if err := h.DB.Where("user_id = ? AND id = ?", userID, id).First(&tag).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "标签不存在"})
		return
	}

	// 删除标签关联关系
	h.DB.Where("tag_id = ?", tag.ID).Delete(&model.TaskTag{})

	// 删除标签
	h.DB.Delete(&tag)

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// GetTasksByTag 获取指定标签下的任务
func (h *TagHandler) GetTasksByTag(c *gin.Context) {
	userID := c.GetUint("userID")
	tagID, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的标签ID"})
		return
	}

	// 验证标签是否属于该用户
	var tag model.Tag
	if err := h.DB.Where("user_id = ? AND id = ?", userID, tagID).First(&tag).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "标签不存在"})
		return
	}

	// 获取该标签关联的任务ID
	var taskIDs []uint
	h.DB.Model(&model.TaskTag{}).Where("tag_id = ?", tagID).Pluck("task_id", &taskIDs)

	if len(taskIDs) == 0 {
		c.JSON(http.StatusOK, []model.Task{})
		return
	}

	// 获取任务列表
	var tasks []model.Task
	h.DB.Preload("List").
		Preload("Tags").
		Where("id IN ? AND user_id = ?", taskIDs, userID).
		Order("sort_order ASC, created_at DESC").
		Find(&tasks)

	// 填充子任务进度
	taskHandler := &TaskHandler{DB: h.DB}
	taskHandler.FillSubtaskProgress(tasks)

	c.JSON(http.StatusOK, tasks)
}

// GetStats 标签使用频率统计
func (h *TagHandler) GetStats(c *gin.Context) {
	userID := c.GetUint("userID")

	var stats []struct {
		TagID   uint   `json:"tag_id"`
		Name    string `json:"name"`
		Color   string `json:"color"`
		TaskNum int64  `json:"task_num"`
	}

	h.DB.Raw(`
		SELECT t.id as tag_id, t.name, t.color,
			COUNT(tt.task_id) as task_num
		FROM tags t
		LEFT JOIN task_tags tt ON tt.tag_id = t.id
		WHERE t.user_id = ?
		GROUP BY t.id, t.name, t.color
		ORDER BY task_num DESC
	`, userID).Scan(&stats)

	c.JSON(http.StatusOK, stats)
}
