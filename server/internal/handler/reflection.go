package handler

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ReflectionHandler struct {
	DB *gorm.DB
}

func NewReflectionHandler(db *gorm.DB) *ReflectionHandler {
	return &ReflectionHandler{DB: db}
}

type reflectionRequest struct {
	EntryType    string                 `json:"entry_type"`
	QuestionID   string                 `json:"question_id"`
	DimensionKey model.DimensionKey     `json:"dimension_key"`
	Content      string                 `json:"content" binding:"required"`
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
	contextBytes, _ := json.Marshal(req.Context)
	entry := model.Reflection{
		UserID:       userID,
		EntryType:    entryType,
		QuestionID:   strings.TrimSpace(req.QuestionID),
		DimensionKey: req.DimensionKey,
		Content:      content,
		Context:      string(contextBytes),
	}
	if entry.Context == "" || entry.Context == "null" {
		entry.Context = "{}"
	}
	if err := h.DB.Create(&entry).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存反思失败"})
		return
	}
	c.JSON(http.StatusCreated, reflectionToResponse(entry))
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
