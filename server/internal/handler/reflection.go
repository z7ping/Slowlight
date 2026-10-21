package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type ReflectionHandler struct {
	DB *gorm.DB
}

func NewReflectionHandler(db *gorm.DB) *ReflectionHandler {
	return &ReflectionHandler{DB: db}
}

type reflectionRequest struct {
	ClientRequestID string `json:"client_request_id"`
	EntryType    string                 `json:"entry_type"`
	QuestionID   string                 `json:"question_id"`
	DimensionKey model.DimensionKey     `json:"dimension_key"`
	Content      string                 `json:"content" binding:"required"`
	TagIDs       []uint                 `json:"tag_ids"`
	Context      map[string]interface{} `json:"context"`
}

type reflectionResponse struct {
	ID           uint                   `json:"id"`
	EntryType    string                 `json:"entry_type"`
	QuestionID   string                 `json:"question_id,omitempty"`
	DimensionKey model.DimensionKey     `json:"dimension_key,omitempty"`
	Content      string                 `json:"content"`
	Context      map[string]interface{} `json:"context"`
	CreatedAt    time.Time              `json:"created_at"`
}

func (h *ReflectionHandler) Create(c *gin.Context) {
	userID := c.GetUint("userID")
	var req reflectionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}
    if len(req.ClientRequestID) > 100 {
        c.JSON(http.StatusBadRequest, gin.H{"error": "client_request_id 过长"})
        return
    }
	content := strings.TrimSpace(req.Content)
	if content == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "内容不能为空"})
		return
	}
	entryType := req.EntryType
	if entryType == "" {
		entryType = "reflection"
	}
	if entryType != "reflection" && entryType != "observation" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "entry_type 仅支持 reflection / observation"})
		return
	}
	if !model.IsValidDimensionKey(req.DimensionKey) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的 dimension_key"})
		return
	}
	if len(req.TagIDs) > 64 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "最多关联 64 个标签"})
		return
	}
	seen := make(map[uint]struct{}, len(req.TagIDs))
	unique := make([]uint, 0, len(req.TagIDs))
	for _, id := range req.TagIDs {
		if id == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "标签 ID 无效"})
			return
		}
		if _, ok := seen[id]; !ok {
			seen[id] = struct{}{}
			unique = append(unique, id)
		}
	}
	if len(unique) > 0 {
		var count int64
		if err := h.DB.Model(&model.Tag{}).
			Where("user_id = ? AND id IN ?", userID, unique).
			Count(&count).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "校验标签失败"})
			return
		}
		if count != int64(len(unique)) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "标签不存在或不属于当前用户"})
			return
		}
	}
	contextBytes, _ := json.Marshal(req.Context)
	entry := model.Reflection{
		UserID:       userID,
        ClientRequestID: func() *string {
            if req.ClientRequestID == "" { return nil }
            id := req.ClientRequestID
            return &id
        }(),
		EntryType:    entryType,
		QuestionID:   strings.TrimSpace(req.QuestionID),
		DimensionKey: req.DimensionKey,
		Content:      content,
		Context:      string(contextBytes),
	}
	if entry.Context == "" || entry.Context == "null" {
		entry.Context = "{}"
	}
    errRequestCollision := errors.New("相同提交标识对应不同的反思内容")
    replayed := false
    if err := h.DB.Transaction(func(tx *gorm.DB) error {
        var saved model.Reflection
        if req.ClientRequestID != "" {
            // The unique index is the atomic guard for a response lost after commit.
            result := tx.Clauses(clause.OnConflict{
                Columns: []clause.Column{{Name: "user_id"}, {Name: "client_request_id"}},
                DoNothing: true,
            }).Create(&entry)
            if result.Error != nil { return result.Error }
            if result.RowsAffected == 0 {
                if err := tx.Where("user_id = ? AND client_request_id = ?",
                    userID, req.ClientRequestID).First(&saved).Error; err != nil { return err }
                if saved.Content != content || saved.EntryType != entryType ||
                    saved.QuestionID != entry.QuestionID || saved.DimensionKey != entry.DimensionKey {
                    return errRequestCollision
                }
                entry = saved
                replayed = true
                return nil
            }
        } else if err := tx.Create(&entry).Error; err != nil {
            return err
        }
        for _, id := range unique {
            if err := tx.Create(&model.ReflectionTag{
                ReflectionID: entry.ID,
                TagID: id,
            }).Error; err != nil {
                return err
            }
        }
        return nil
    }).Error; err != nil {
        if errors.Is(err, errRequestCollision) {
            c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
            return
        }
        c.JSON(http.StatusInternalServerError, gin.H{"error": "保存反思及标签失败"})
        return
    }
    code := http.StatusCreated
    if replayed { code = http.StatusOK }
    c.JSON(code, reflectionToResponse(entry))
}

func (h *ReflectionHandler) List(c *gin.Context) {
	userID := c.GetUint("userID")
	limit := 20
	if raw := c.Query("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			if parsed > 100 {
				parsed = 100
			}
			limit = parsed
		}
	}
	var entries []model.Reflection
	query := h.DB.Where("user_id = ?", userID).Order("created_at DESC").Limit(limit)
	if key := model.DimensionKey(c.Query("dimension_key")); key != "" {
		if !model.IsValidDimensionKey(key) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "无效的 dimension_key"})
			return
		}
		query = query.Where("dimension_key = ?", key)
	}
	if err := query.Find(&entries).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取反思失败"})
		return
	}
	items := make([]reflectionResponse, 0, len(entries))
	for _, entry := range entries {
		items = append(items, reflectionToResponse(entry))
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func reflectionToResponse(entry model.Reflection) reflectionResponse {
	contextValue := map[string]interface{}{}
	_ = json.Unmarshal([]byte(entry.Context), &contextValue)
	return reflectionResponse{
		ID:           entry.ID,
		EntryType:    entry.EntryType,
		QuestionID:   entry.QuestionID,
		DimensionKey: entry.DimensionKey,
		Content:      entry.Content,
		Context:      contextValue,
		CreatedAt:    entry.CreatedAt,
	}
}
