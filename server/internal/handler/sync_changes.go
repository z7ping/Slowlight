package handler

import (
	"net/http"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// SyncChangesHandler 为 Cloud Data 离线缓存提供安全的增量变更与删除 tombstone。
type SyncChangesHandler struct {
	DB *gorm.DB
}

func NewSyncChangesHandler(db *gorm.DB) *SyncChangesHandler {
	return &SyncChangesHandler{DB: db}
}

type SyncChangesResponse struct {
	ServerTime time.Time          `json:"server_time"`
	Lists      []model.List       `json:"lists"`
	Tags       []model.Tag        `json:"tags"`
	SystemTags []model.SystemTag  `json:"system_tags"`
	Habits     []model.Habit      `json:"habits"`
	Tasks      []model.Task       `json:"tasks"`
	HabitLogs  []model.HabitLog   `json:"habit_logs"`
	Deleted    map[string][]uint  `json:"deleted"`
}

// GetChanges 返回 (since, server_time] 时间窗中的变化。
//
// 删除必须通过 tombstone 显式返回，客户端不得用“本次列表中缺失”推断删除。
func (h *SyncChangesHandler) GetChanges(c *gin.Context) {
	userID := c.GetUint("userID")
	serverTime := time.Now().UTC()
	since := time.Time{}
	if raw := c.Query("since"); raw != "" {
		parsed, err := time.Parse(time.RFC3339Nano, raw)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid since, expected RFC3339"})
			return
		}
		since = parsed.UTC()
	}

	response := SyncChangesResponse{
		Lists:      []model.List{},
		Tags:       []model.Tag{},
		SystemTags: []model.SystemTag{},
		Habits:     []model.Habit{},
		Tasks:      []model.Task{},
		HabitLogs:  []model.HabitLog{},
		Deleted: map[string][]uint{
			"lists":       {},
			"tags":        {},
			"system_tags": {},
			"habits":      {},
			"tasks":       {},
			"habit_logs":  {},
		},
		ServerTime: serverTime,
	}

	window := func(db *gorm.DB) *gorm.DB {
		return db.Where("updated_at > ? AND updated_at <= ?", since, serverTime)
	}

	if err := window(h.DB.Where("user_id = ?", userID)).Find(&response.Lists).Error; err != nil {
		h.fail(c, err)
		return
	}
	if err := window(h.DB.Where("user_id = ?", userID)).Find(&response.Tags).Error; err != nil {
		h.fail(c, err)
		return
	}
	if err := window(h.DB.Where("user_id = ?", userID)).Find(&response.SystemTags).Error; err != nil {
		h.fail(c, err)
		return
	}
	if err := window(h.DB.Where("user_id = ?", userID)).Find(&response.Habits).Error; err != nil {
		h.fail(c, err)
		return
	}
	if err := window(h.DB.Where("user_id = ?", userID)).
		Preload("Tags").Preload("List").Find(&response.Tasks).Error; err != nil {
		h.fail(c, err)
		return
	}

	// HabitLog 没有 UpdatedAt，新增变化以 CreatedAt 为游标；删除走 DeletedAt tombstone。
	if err := h.DB.Where(
		"habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND created_at > ? AND created_at <= ?",
		userID, since, serverTime,
	).Find(&response.HabitLogs).Error; err != nil {
		h.fail(c, err)
		return
	}

	if err := h.deletedIDs(&model.List{}, userID, since, serverTime, &response.Deleted, "lists"); err != nil {
		h.fail(c, err)
		return
	}
	if err := h.deletedIDs(&model.Tag{}, userID, since, serverTime, &response.Deleted, "tags"); err != nil {
		h.fail(c, err)
		return
	}
	if err := h.deletedIDs(&model.SystemTag{}, userID, since, serverTime, &response.Deleted, "system_tags"); err != nil {
		h.fail(c, err)
		return
	}
	if err := h.deletedIDs(&model.Habit{}, userID, since, serverTime, &response.Deleted, "habits"); err != nil {
		h.fail(c, err)
		return
	}
	if err := h.deletedIDs(&model.Task{}, userID, since, serverTime, &response.Deleted, "tasks"); err != nil {
		h.fail(c, err)
		return
	}

	var deletedHabitLogs []uint
	if err := h.DB.Unscoped().Model(&model.HabitLog{}).
		Where("habit_id IN (SELECT id FROM habits WHERE user_id = ?) AND deleted_at > ? AND deleted_at <= ?", userID, since, serverTime).
		Pluck("id", &deletedHabitLogs).Error; err != nil {
		h.fail(c, err)
		return
	}
	response.Deleted["habit_logs"] = deletedHabitLogs

	c.JSON(http.StatusOK, response)
}

func (h *SyncChangesHandler) deletedIDs(
	modelValue interface{},
	userID uint,
	since time.Time,
	serverTime time.Time,
	deleted *map[string][]uint,
	key string,
) error {
	var ids []uint
	if err := h.DB.Unscoped().Model(modelValue).
		Where("user_id = ? AND deleted_at > ? AND deleted_at <= ?", userID, since, serverTime).
		Pluck("id", &ids).Error; err != nil {
		return err
	}
	(*deleted)[key] = ids
	return nil
}

func (h *SyncChangesHandler) fail(c *gin.Context, err error) {
	c.JSON(http.StatusInternalServerError, gin.H{"error": "读取同步变更失败"})
}
