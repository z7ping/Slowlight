package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

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
	// 兼容未曾访问收集箱的旧账号；只补缺失项，不重置现有清单。
	if _, err := (&InboxHandler{DB: h.DB}).getOrCreateInbox(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取清单失败"})
		return
	}
	var lists []model.List
	if err := h.DB.Where("user_id = ?", userID).
		Order("sort_order ASC, created_at ASC, id ASC").Find(&lists).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取清单失败"})
		return
	}
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

// DeleteList 删除清单；仅显式 delete_tasks=true 时将所属任务一并软删除。
func (h *ListHandler) DeleteList(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var list model.List
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&list).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "清单不存在"})
		return
	}
	if list.IsInbox {
		c.JSON(http.StatusBadRequest, gin.H{"error": "收集箱不可删除"})
		return
	}

	// Older clients still use DELETE /lists/:id without an explicit cascade.
	// Never silently turn that request into destructive task deletion.
	deleteTasks := c.Query("delete_tasks") == "true"
	undoable := c.Query("undoable") == "true"
	if undoable && !deleteTasks {
		c.JSON(http.StatusBadRequest, gin.H{"error": "可撤销的清单删除必须明确确认子任务范围"})
		return
	}
	expectedRaw, expectedProvided := c.GetQuery("expected_tasks")
	if undoable && !expectedProvided {
		c.JSON(http.StatusBadRequest, gin.H{"error": "可撤销删除需要已核对的任务数量"})
		return
	}
	var expectedCount int64
	if expectedProvided {
		var err error
		expectedCount, err = strconv.ParseInt(expectedRaw, 10, 64)
		if err != nil || expectedCount < 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "关联任务核对参数无效"})
			return
		}
	}
	errImpactChanged := errors.New("list task membership changed")
	var taskCount int64
	if err := h.DB.Model(&model.Task{}).
		Where("list_id = ? AND user_id = ?", list.ID, userID).
		Count(&taskCount).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法核对关联任务"})
		return
	}
	if taskCount > 0 && !deleteTasks {
		c.JSON(http.StatusBadRequest, gin.H{"error": "清单下有任务，删除任务须明确确认"})
		return
	}

	// 任务、清单与撤销证据同一事务提交；没有可恢复证据不删除。
	var undoToken string
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		var taskIDs []uint
		var stamp time.Time
		if undoable {
			if err := tx.Model(&model.Task{}).
				Where("list_id = ? AND user_id = ?", list.ID, userID).
				Pluck("id", &taskIDs).Error; err != nil { return err }
			if int64(len(taskIDs)) != expectedCount {
				return errImpactChanged
			}
			stamp = time.Now().UTC().Truncate(time.Microsecond)
		}
		if expectedProvided {
			var current int64
			if err := tx.Model(&model.Task{}).
				Where("list_id = ? AND user_id = ?", list.ID, userID).
				Count(&current).Error; err != nil {
				return err
			}
			if current != expectedCount {
				return errImpactChanged
			}
		}
		if deleteTasks {
			var deleted *gorm.DB
			if undoable {
				deleted = tx.Model(&model.Task{}).
					Where("list_id = ? AND user_id = ?", list.ID, userID).
					Update("deleted_at", stamp)
			} else {
				deleted = tx.Where("list_id = ? AND user_id = ?", list.ID, userID).
					Delete(&model.Task{})
			}
			if deleted.Error != nil { return deleted.Error }
			if expectedProvided && deleted.RowsAffected != expectedCount {
				return errImpactChanged
			}
		}
		var result *gorm.DB
		if undoable {
			result = tx.Model(&model.List{}).
				Where("id = ? AND user_id = ? AND is_inbox = false", list.ID, userID).
				Update("deleted_at", stamp)
		} else {
			result = tx.Where("id = ? AND user_id = ? AND is_inbox = false", list.ID, userID).
				Delete(&model.List{})
		}
		if result.Error != nil { return result.Error }
		if result.RowsAffected != 1 { return gorm.ErrRecordNotFound }
		if undoable {
			token, err := saveDeletionUndo(tx, userID, "list", listDeletionSnapshot{
				ListID: list.ID, TaskIDs: taskIDs, DeletedAt: stamp,
			})
			if err != nil { return err }
			undoToken = token
		}
		return nil
	})
	if err != nil {
		if errors.Is(err, errImpactChanged) {
			c.JSON(http.StatusConflict, gin.H{"error": "清单关联任务已变化，请重新核对删除范围"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除清单及关联任务失败"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message": "删除成功",
		"undo_token": undoToken,
	})
}

type listDeletionSnapshot struct {
	ListID    uint      `json:"list_id"`
	TaskIDs   []uint    `json:"task_ids"`
	DeletedAt time.Time `json:"deleted_at"`
}

// POST /lists/undo — the original IDs and exact tombstone are restored
// atomically. The one-use receipt is persisted in the existing user_config.
func (h *ListHandler) UndoListDelete(c *gin.Context) {
	userID := c.GetUint("userID")
	var request struct {
		Token string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "撤销凭据不能为空"})
		return
	}
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		raw, stored, err := loadDeletionUndo(tx, userID, request.Token, "list")
		if err != nil { return err }
		var snap listDeletionSnapshot
		if err := json.Unmarshal(raw, &snap); err != nil {
			return errDeletionUndoUnavailable
		}
		restored := tx.Unscoped().Model(&model.List{}).
			Where("id = ? AND user_id = ? AND deleted_at = ?",
				snap.ListID, userID, snap.DeletedAt).
			Update("deleted_at", nil)
		if restored.Error != nil { return restored.Error }
		if restored.RowsAffected != 1 { return errDeletionUndoUnavailable }
		if len(snap.TaskIDs) > 0 {
			children := tx.Unscoped().Model(&model.Task{}).
				Where("user_id = ? AND list_id = ? AND id IN ? AND deleted_at = ?",
					userID, snap.ListID, snap.TaskIDs, snap.DeletedAt).
				Update("deleted_at", nil)
			if children.Error != nil { return children.Error }
			if children.RowsAffected != int64(len(snap.TaskIDs)) {
				return errDeletionUndoUnavailable
			}
		}
		return tx.Delete(stored).Error
	})
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "撤销未执行：原记录已变化或凭据失效"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "原清单及任务已恢复"})
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
		LEFT JOIN tasks t ON t.list_id = l.id AND t.user_id = l.user_id AND t.deleted_at IS NULL
		WHERE l.user_id = ? AND l.deleted_at IS NULL
		GROUP BY l.id, l.name, l.name, l.color
		ORDER BY l.sort_order
	`, userID).Scan(&stats)

	c.JSON(http.StatusOK, stats)
}
