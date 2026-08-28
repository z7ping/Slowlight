package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type InboxHandler struct {
	DB *gorm.DB
}

func NewInboxHandler(db *gorm.DB) *InboxHandler {
	return &InboxHandler{DB: db}
}

// getOrCreateInbox 获取或创建用户的收集箱列表
func (h *InboxHandler) getOrCreateInbox(userID uint) (*model.List, error) {
	var list model.List
	err := h.DB.Where("user_id = ? AND is_inbox = ?", userID, true).First(&list).Error
	if err == nil {
		return &list, nil
	}

	// 不存在则创建
	list = model.List{
		UserID:    userID,
		Name:      "收集箱",
		Icon:      "📥",
		Color:     "#909399",
		SortOrder: -1, // 排在最前面
		IsInbox:   true,
	}
	if err := h.DB.Create(&list).Error; err != nil {
		return nil, err
	}
	return &list, nil
}

// GetInbox 获取收集箱任务列表
func (h *InboxHandler) GetInbox(c *gin.Context) {
	userID := c.GetUint("userID")

	inbox, err := h.getOrCreateInbox(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取收集箱失败"})
		return
	}

	var tasks []model.Task
	h.DB.Preload("List").
		Preload("Tags").
		Where("user_id = ? AND list_id = ? AND is_completed = ?", userID, inbox.ID, false).
		Order("created_at DESC").
		Find(&tasks)

	// 填充子任务进度
	taskHandler := &TaskHandler{DB: h.DB}
	taskHandler.FillSubtaskProgress(tasks)

	c.JSON(http.StatusOK, gin.H{
		"inbox": inbox,
		"tasks": tasks,
	})
}

// QuickAdd 快速添加到收集箱（只需标题）
func (h *InboxHandler) QuickAdd(c *gin.Context) {
	userID := c.GetUint("userID")

	var req struct {
		Title       string `json:"title" binding:"required"`
		SystemTagID *uint  `json:"system_tag_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "标题不能为空"})
		return
	}

	inbox, err := h.getOrCreateInbox(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取收集箱失败"})
		return
	}

	task := model.Task{
		UserID:      userID,
		ListID:      inbox.ID,
		Title:       req.Title,
		Priority:    "none",
		SystemTagID: req.SystemTagID,
	}
	if err := h.DB.Create(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	task.List = *inbox
	c.JSON(http.StatusCreated, task)
}

// MoveTo 将收集箱中的任务移动到其他清单
func (h *InboxHandler) MoveTo(c *gin.Context) {
	userID := c.GetUint("userID")
	taskID := c.Param("id")

	var req struct {
		ListID uint `json:"list_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "目标清单 ID 不能为空"})
		return
	}

	// 验证任务属于当前用户的收集箱
	inbox, err := h.getOrCreateInbox(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取收集箱失败"})
		return
	}

	var task model.Task
	if err := h.DB.Where("id = ? AND user_id = ? AND list_id = ?", taskID, userID, inbox.ID).First(&task).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "任务不存在或不在收集箱中"})
		return
	}

	// 验证目标清单属于当前用户
	var targetList model.List
	if err := h.DB.Where("id = ? AND user_id = ?", req.ListID, userID).First(&targetList).Error; err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "目标清单不存在"})
		return
	}

	task.ListID = req.ListID
	if err := h.DB.Save(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	task.List = targetList
	c.JSON(http.StatusOK, task)
}

// GetCount 获取收集箱任务数量（用于角标显示）
func (h *InboxHandler) GetCount(c *gin.Context) {
	userID := c.GetUint("userID")

	var count int64
	h.DB.Raw(`
		SELECT COUNT(*) FROM tasks
		WHERE user_id = ? AND is_completed = false
		AND list_id = (SELECT id FROM lists WHERE user_id = ? AND is_inbox = true AND deleted_at IS NULL LIMIT 1)
		AND deleted_at IS NULL
	`, userID, userID).Scan(&count)

	c.JSON(http.StatusOK, gin.H{"count": count})
}
