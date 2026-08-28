package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type SubtaskHandler struct {
	DB *gorm.DB
}

func NewSubtaskHandler(db *gorm.DB) *SubtaskHandler {
	return &SubtaskHandler{DB: db}
}

// verifyTaskOwnership 验证任务是否属于当前用户
func (h *SubtaskHandler) verifyTaskOwnership(c *gin.Context, taskID uint) bool {
	userID := c.GetUint("userID")
	var task model.Task
	if err := h.DB.Where("id = ? AND user_id = ?", taskID, userID).First(&task).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "任务不存在或无权访问"})
		return false
	}
	return true
}

// GetSubtasks 获取任务的子任务列表
func (h *SubtaskHandler) GetSubtasks(c *gin.Context) {
	taskID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的任务 ID"})
		return
	}

	if !h.verifyTaskOwnership(c, uint(taskID)) {
		return
	}

	var subtasks []model.Subtask
	h.DB.Where("task_id = ?", taskID).
		Order("sort_order ASC, created_at ASC").
		Find(&subtasks)

	c.JSON(http.StatusOK, subtasks)
}

// CreateSubtask 创建子任务
func (h *SubtaskHandler) CreateSubtask(c *gin.Context) {
	taskID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的任务 ID"})
		return
	}

	if !h.verifyTaskOwnership(c, uint(taskID)) {
		return
	}

	var subtask model.Subtask
	if err := c.ShouldBindJSON(&subtask); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	subtask.TaskID = uint(taskID)
	if err := h.DB.Create(&subtask).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, subtask)
}

// UpdateSubtask 更新子任务
func (h *SubtaskHandler) UpdateSubtask(c *gin.Context) {
	taskID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的任务 ID"})
		return
	}

	if !h.verifyTaskOwnership(c, uint(taskID)) {
		return
	}

	subtaskID := c.Param("subtaskId")
	var subtask model.Subtask
	if err := h.DB.Where("task_id = ? AND id = ?", taskID, subtaskID).First(&subtask).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "子任务不存在"})
		return
	}

	var updateData model.Subtask
	if err := c.ShouldBindJSON(&updateData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	h.DB.Model(&subtask).Updates(updateData)
	c.JSON(http.StatusOK, subtask)
}

// ToggleSubtask 切换子任务完成状态
func (h *SubtaskHandler) ToggleSubtask(c *gin.Context) {
	taskID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的任务 ID"})
		return
	}

	if !h.verifyTaskOwnership(c, uint(taskID)) {
		return
	}

	subtaskID := c.Param("subtaskId")
	var subtask model.Subtask
	if err := h.DB.Where("task_id = ? AND id = ?", taskID, subtaskID).First(&subtask).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "子任务不存在"})
		return
	}

	subtask.IsCompleted = !subtask.IsCompleted
	h.DB.Save(&subtask)

	c.JSON(http.StatusOK, subtask)
}

// DeleteSubtask 删除子任务
func (h *SubtaskHandler) DeleteSubtask(c *gin.Context) {
	taskID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的任务 ID"})
		return
	}

	if !h.verifyTaskOwnership(c, uint(taskID)) {
		return
	}

	subtaskID := c.Param("subtaskId")

	result := h.DB.Where("task_id = ? AND id = ?", taskID, subtaskID).Delete(&model.Subtask{})
	if result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "子任务不存在"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// GetSubtaskProgress 获取子任务进度
func (h *SubtaskHandler) GetSubtaskProgress(c *gin.Context) {
	taskIDStr := c.Param("id")
	taskID, err := strconv.ParseUint(taskIDStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的任务 ID"})
		return
	}
	if !h.verifyTaskOwnership(c, uint(taskID)) {
		return
	}

	var total, completed int64
	h.DB.Model(&model.Subtask{}).Where("task_id = ?", taskID).Count(&total)
	h.DB.Model(&model.Subtask{}).Where("task_id = ? AND is_completed = ?", taskID, true).Count(&completed)

	c.JSON(http.StatusOK, gin.H{
		"task_id":   taskID,
		"total":     total,
		"completed": completed,
	})
}
