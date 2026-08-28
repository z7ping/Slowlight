package caldav

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"slowlight/internal/model"
	"slowlight/internal/secureconfig"

	"github.com/emersion/go-webdav"
	"github.com/emersion/go-webdav/caldav"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// Handler CalDAV API Handler
type Handler struct {
	DB *gorm.DB
}

func NewHandler(db *gorm.DB) *Handler {
	return &Handler{DB: db}
}

// ===== 配置 CalDAV 连接 =====

type ConfigRequest struct {
	BaseURL  string   `json:"base_url"` // Vikunja 地址
	Username string   `json:"username"` // 用户名
	Password string   `json:"password"` // API Token
	Paths    []string `json:"paths"`    // 项目路径列表，如 ["/dav/projects/5"]
}

// GetConfig 获取 CalDAV 配置
func (h *Handler) GetConfig(c *gin.Context) {
	userID := c.GetUint("userID")

	var config model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "caldav").First(&config)

	if config.ID == 0 {
		c.JSON(http.StatusOK, gin.H{
			"configured": false,
		})
		return
	}

	var value struct {
		BaseURL  string   `json:"base_url"`
		Username string   `json:"username"`
		Password string   `json:"password"`
		Paths    []string `json:"paths"`
	}
	if err := json.Unmarshal([]byte(config.Value), &value); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "CalDAV 配置格式无效"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"configured": true,
		"value": gin.H{
			"base_url":     value.BaseURL,
			"username":     value.Username,
			"paths":        value.Paths,
			"has_password": value.Password != "",
		},
	})
}

// SaveConfig 保存 CalDAV 配置
func (h *Handler) SaveConfig(c *gin.Context) {
	userID := c.GetUint("userID")

	var req ConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.BaseURL == "" || req.Username == "" || req.Password == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "base_url, username, password 不能为空"})
		return
	}

	// 验证连接
	_, _, err := newCalDAVClient(req.BaseURL, req.Username, req.Password)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "连接失败: " + err.Error()})
		return
	}

	configValue, err := buildConfigValue(req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "无法安全保存凭据: " + err.Error()})
		return
	}
	config := model.UserConfig{
		UserID: userID,
		Key:    "caldav",
		Value:  configValue,
	}

	var existing model.UserConfig
	h.DB.Where("user_id = ? AND key = ?", userID, "caldav").First(&existing)
	if existing.ID != 0 {
		config.ID = existing.ID
	}

	h.DB.Save(&config)

	c.JSON(http.StatusOK, gin.H{"message": "配置保存成功"})
}

// ===== 手动触发同步 =====

// Sync 手动触发 CalDAV 同步
func (h *Handler) Sync(c *gin.Context) {
	userID := c.GetUint("userID")

	log.Printf("[CalDAV] 用户 %d 手动触发同步", userID)

	result, err := SyncAll(h.DB, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

// ===== 获取同步状态 =====

// GetStatus 获取 CalDAV 同步状态
func (h *Handler) GetStatus(c *gin.Context) {
	userID := c.GetUint("userID")

	var states []model.CalDAVSyncState
	h.DB.Where("user_id = ?", userID).Find(&states)

	var taskCount int64
	h.DB.Model(&model.Task{}).Where("user_id = ? AND cal_d_a_v_uid != ''", userID).Count(&taskCount)

	c.JSON(http.StatusOK, gin.H{
		"states":     states,
		"task_count": taskCount,
	})
}

// ===== 测试连接 =====

// Test 测试 CalDAV 连接
func (h *Handler) Test(c *gin.Context) {
	var req ConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	client, _, err := newCalDAVClient(req.BaseURL, req.Username, req.Password)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"connected": false, "error": err.Error()})
		return
	}

	// 尝试查询第一个项目
	if len(req.Paths) > 0 {
		query := &caldav.CalendarQuery{
			CompFilter: caldav.CompFilter{Name: "VTODO"},
		}
		objects, err := client.QueryCalendar(context.Background(), req.Paths[0], query)
		if err != nil {
			c.JSON(http.StatusOK, gin.H{
				"connected": true,
				"query_ok":  false,
				"error":     err.Error(),
			})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"connected":  true,
			"query_ok":   true,
			"task_count": len(objects),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"connected": true,
		"query_ok":  false,
		"error":     "未配置项目路径",
	})
}

// ===== 内部工具 =====

// newCalDAVClient 从参数创建客户端
func newCalDAVClient(baseURL, username, password string) (*caldav.Client, string, error) {
	httpClient := &http.Client{Timeout: 30 * time.Second}
	authClient := webdav.HTTPClientWithBasicAuth(httpClient, username, password)
	client, err := caldav.NewClient(authClient, baseURL)
	if err != nil {
		return nil, "", fmt.Errorf("创建 CalDAV 客户端失败: %w", err)
	}
	return client, baseURL, nil
}

// buildConfigValue 构建配置 JSON，密码以服务端密钥加密后持久化。
func buildConfigValue(req ConfigRequest) (string, error) {
	encryptedPassword, err := secureconfig.Encrypt(req.Password)
	if err != nil {
		return "", err
	}
	m := map[string]interface{}{
		"base_url": req.BaseURL,
		"username": req.Username,
		"password": encryptedPassword,
		"paths":    req.Paths,
	}
	b, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
