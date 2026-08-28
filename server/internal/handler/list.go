package handler

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

// CreateListRequest 创建清单请求（只允许客户端传入安全字段）
type CreateListRequest struct {
	Name     string `json:"name"`
	Icon     string `json:"icon"`
	Color    string `json:"color"`
	IsInbox  *bool  `json:"is_inbox"`
}

// UpdateListRequest 更新清单请求
type UpdateListRequest struct {
	Name  *string `json:"name"`
	Icon  *string `json:"icon"`
	Color *string `json:"color"`
}

type ListHandler struct {
	DB *gorm.DB
}

func NewListHandler(db *gorm.DB) *ListHandler {
	return &ListHandler{DB: db}
}

// GetLists 获取当前用户的清单列表
func (h *ListHandler) GetLists(c *gin.Context) {
	userID := c.GetUint("userID")
	var lists []model.List
	h.DB.Where("user_id = ?", userID).Order("sort_order ASC").Find(&lists)
	c.JSON(http.StatusOK, lists)
}

// 最大清单数（不含收集箱），0=不限制
const MaxListCount = 6

// CreateList 创建清单
func (h *ListHandler) CreateList(c *gin.Context) {
	userID := c.GetUint("userID")

	var req CreateListRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 检查清单数量限制（不含收集箱）
	if MaxListCount > 0 {
		var count int64
		h.DB.Model(&model.List{}).Where("user_id = ? AND is_inbox = false", userID).Count(&count)
		if count >= int64(MaxListCount) {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("清单数量已达上限（%d个），请先删除不用的清单", MaxListCount)})
			return
		}
	}

	list := model.List{
		UserID:  userID,
		Name:    req.Name,
		Icon:    req.Icon,
		Color:   req.Color,
	}
	if req.IsInbox != nil {
		list.IsInbox = *req.IsInbox
	}
	if list.Icon == "" {
		list.Icon = "📋"
	}
	if list.Color == "" {
		list.Color = "#1890ff"
	}

	if err := h.DB.Create(&list).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, list)
}

// UpdateList 更新清单
func (h *ListHandler) UpdateList(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	var list model.List

	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&list).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "清单不存在"})
		return
	}

	var req UpdateListRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updates := map[string]interface{}{}
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.Icon != nil {
		updates["icon"] = *req.Icon
	}
	if req.Color != nil {
		updates["color"] = *req.Color
	}

	if len(updates) > 0 {
		h.DB.Model(&list).Updates(updates)
	}

	c.JSON(http.StatusOK, list)
}

// DeleteList 删除清单
func (h *ListHandler) DeleteList(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	// 检查清单是否属于当前用户
	var list model.List
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&list).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "清单不存在"})
		return
	}

	// 保护收集箱不被删除
	if list.IsInbox {
		c.JSON(http.StatusBadRequest, gin.H{"error": "收集箱不可删除"})
		return
	}

	// 检查是否有任务
	var count int64
	h.DB.Model(&model.Task{}).Where("list_id = ? AND user_id = ?", id, userID).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "清单下有任务，无法删除"})
		return
	}

	if err := h.DB.Delete(&model.List{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// GetStats 清单维度统计：每个清单的任务数和完成率
func (h *ListHandler) GetStats(c *gin.Context) {
	userID := c.GetUint("userID")

	var stats []struct {
		ListID    uint    `json:"list_id"`
		ListName  string  `json:"list_name"`
		Color     string  `json:"color"`
		Total     int64   `json:"total"`
		Completed int64   `json:"completed"`
		Rate      float64 `json:"rate"`
	}

	h.DB.Raw(`
		SELECT l.id as list_id, l.name as list_name, l.color,
			COUNT(t.id) as total,
			SUM(CASE WHEN t.is_completed THEN 1 ELSE 0 END) as completed,
			CASE WHEN COUNT(t.id) > 0
				THEN ROUND(SUM(CASE WHEN t.is_completed THEN 1 ELSE 0 END)::numeric / COUNT(t.id) * 100, 1)
				ELSE 0
			END as rate
		FROM lists l
		LEFT JOIN tasks t ON t.list_id = l.id
		WHERE l.user_id = ?
		GROUP BY l.id, l.name, l.name, l.color
		ORDER BY l.sort_order
	`, userID).Scan(&stats)

	c.JSON(http.StatusOK, stats)
}
