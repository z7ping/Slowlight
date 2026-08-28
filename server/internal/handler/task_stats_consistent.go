package handler

import (
	"net/http"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
)

// GetStatsConsistent 与 Local Analytics 使用同一基础统计语义：
// - GORM/Raw 查询都排除 soft-deleted Task/List；
// - 最近 7 天每日完成数按 completed_at，而不是任意 updated_at。
func (h *TaskHandler) GetStatsConsistent(c *gin.Context) {
	userID := c.GetUint("userID")

	var total, completed int64
	h.DB.Model(&model.Task{}).Where("user_id = ?", userID).Count(&total)
	h.DB.Model(&model.Task{}).
		Where("user_id = ? AND is_completed = true", userID).
		Count(&completed)

	var priorityStats []struct {
		Priority string `json:"priority"`
		Count    int64  `json:"count"`
	}
	h.DB.Model(&model.Task{}).
		Select("priority, count(*) as count").
		Where("user_id = ? AND is_completed = false", userID).
		Group("priority").
		Scan(&priorityStats)

	var listStats []struct {
		ListID    uint   `json:"list_id"`
		ListName  string `json:"list_name"`
		Total     int64  `json:"total"`
		Completed int64  `json:"completed"`
	}
	h.DB.Raw(`
		SELECT t.list_id, l.name AS list_name,
			COUNT(*) AS total,
			SUM(CASE WHEN t.is_completed THEN 1 ELSE 0 END) AS completed
		FROM tasks t
		JOIN lists l ON t.list_id = l.id
		WHERE t.user_id = ?
			AND t.deleted_at IS NULL
			AND l.deleted_at IS NULL
		GROUP BY t.list_id, l.name
	`, userID).Scan(&listStats)

	var dailyStats []struct {
		Date  string `json:"date"`
		Count int64  `json:"count"`
	}
	h.DB.Raw(`
		SELECT DATE(completed_at) AS date, COUNT(*) AS count
		FROM tasks
		WHERE user_id = ?
			AND deleted_at IS NULL
			AND is_completed = true
			AND completed_at IS NOT NULL
			AND completed_at >= CURRENT_DATE - INTERVAL '7 days'
		GROUP BY DATE(completed_at)
		ORDER BY date
	`, userID).Scan(&dailyStats)

	c.JSON(http.StatusOK, gin.H{
		"total":     total,
		"completed": completed,
		"rate":      safeRate(completed, total),
		"priority":  priorityStats,
		"by_list":   listStats,
		"daily":     dailyStats,
	})
}
