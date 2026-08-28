package handler

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type WebhookHandler struct {
	DB *gorm.DB
}

func NewWebhookHandler(db *gorm.DB) *WebhookHandler {
	return &WebhookHandler{DB: db}
}

// ===== CRUD =====

func (h *WebhookHandler) List(c *gin.Context) {
	userID := c.GetUint("userID")
	var webhooks []model.Webhook
	h.DB.Where("user_id = ?", userID).Order("created_at DESC").Find(&webhooks)
	c.JSON(http.StatusOK, gin.H{"webhooks": webhooks})
}

func (h *WebhookHandler) Create(c *gin.Context) {
	userID := c.GetUint("userID")
	var req struct {
		URL   string `json:"url"`
		Event string `json:"event"`
		Name  string `json:"name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 验证事件类型
	if !isValidEvent(req.Event) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的事件类型，可选: task.created, task.completed, task.deleted, task.updated, habit.checked, session.ended"})
		return
	}

	if err := validateWebhookURL(req.URL); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 生成安全随机 secret
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "生成 secret 失败"})
		return
	}
	secret := hex.EncodeToString(b)
	webhook := model.Webhook{
		UserID:   userID,
		URL:      req.URL,
		Event:    req.Event,
		Name:     req.Name,
		Secret:   secret,
		IsActive: true,
	}
	h.DB.Create(&webhook)

	// 返回时包含 secret（仅此一次）
	resp := map[string]interface{}{
		"id":        webhook.ID,
		"url":       webhook.URL,
		"event":     webhook.Event,
		"name":      webhook.Name,
		"secret":    secret,
		"is_active": true,
		"message":   "Webhook 创建成功，请妥善保管 secret",
	}
	c.JSON(http.StatusCreated, resp)
}

func (h *WebhookHandler) Update(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var webhook model.Webhook
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&webhook).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Webhook 不存在"})
		return
	}

	var req struct {
		URL      *string `json:"url"`
		Event    *string `json:"event"`
		Name     *string `json:"name"`
		IsActive *bool   `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.URL != nil {
		if err := validateWebhookURL(*req.URL); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		webhook.URL = *req.URL
	}
	if req.Event != nil {
		if !isValidEvent(*req.Event) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "不支持的事件类型"})
			return
		}
		webhook.Event = *req.Event
	}
	if req.Name != nil {
		webhook.Name = *req.Name
	}
	if req.IsActive != nil {
		webhook.IsActive = *req.IsActive
	}

	h.DB.Save(&webhook)
	c.JSON(http.StatusOK, webhook)
}

func (h *WebhookHandler) Delete(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")
	h.DB.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Webhook{})
	c.JSON(http.StatusOK, gin.H{"message": "已删除"})
}

// ===== 测试触发 =====

func (h *WebhookHandler) Test(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var webhook model.Webhook
	if err := h.DB.Where("id = ? AND user_id = ?", id, userID).First(&webhook).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Webhook 不存在"})
		return
	}

	payload := map[string]interface{}{
		"event":     webhook.Event,
		"test":      true,
		"message":   "这是一条测试消息",
		"timestamp": time.Now().Unix(),
	}

	err := sendWebhook(webhook.URL, webhook.Secret, payload)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "测试成功"})
}

// ===== 事件触发器（供其他 Handler 调用） =====

// TriggerWebhooks 异步触发匹配的 Webhooks
func (h *WebhookHandler) TriggerWebhooks(userID uint, event string, data map[string]interface{}) {
	go func() {
		var webhooks []model.Webhook
		h.DB.Where("user_id = ? AND event = ? AND is_active = ?", userID, event, true).Find(&webhooks)

		if len(webhooks) == 0 {
			return
		}

		payload := map[string]interface{}{
			"event":     event,
			"data":      data,
			"timestamp": time.Now().Unix(),
		}

		for _, wh := range webhooks {
			if err := sendWebhook(wh.URL, wh.Secret, payload); err != nil {
				log.Printf("[Webhook] 发送失败 url=%s event=%s err=%v", wh.URL, event, err)
			}
		}
	}()
}

// TriggerAllUserWebhooks 触发用户所有事件类型的 Webhook（用于未知事件类型）
func (h *WebhookHandler) TriggerAllForEvent(userID uint, event string, data map[string]interface{}) {
	h.TriggerWebhooks(userID, event, data)
}

// ===== 内部方法 =====

func sendWebhook(url, secret string, payload map[string]interface{}) error {
	if err := validateWebhookURL(url); err != nil {
		return err
	}
	body, _ := json.Marshal(payload)

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("创建 Webhook 请求失败: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "Slowlight-Webhook/1.0")

	// HMAC-SHA256 签名
	if secret != "" {
		mac := hmac.New(sha256.New, []byte(secret))
		mac.Write(body)
		sig := hex.EncodeToString(mac.Sum(nil))
		req.Header.Set("X-Slowlight-Signature", "sha256="+sig)
	}

	client := webhookHTTPClient()
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return nil
}

func validateWebhookURL(raw string) error {
	parsed, err := url.ParseRequestURI(strings.TrimSpace(raw))
	if err != nil || parsed.Hostname() == "" {
		return fmt.Errorf("请提供有效的 Webhook URL")
	}
	if parsed.Scheme != "https" && parsed.Scheme != "http" {
		return fmt.Errorf("Webhook URL 只支持 HTTP 或 HTTPS")
	}
	if parsed.User != nil {
		return fmt.Errorf("Webhook URL 不允许包含用户凭据")
	}
	host := strings.ToLower(parsed.Hostname())
	if host == "localhost" || strings.HasSuffix(host, ".localhost") {
		return fmt.Errorf("Webhook URL 不允许指向本机或私有网络")
	}
	if ip := net.ParseIP(host); ip != nil && !isPublicWebhookIP(ip) {
		return fmt.Errorf("Webhook URL 不允许指向本机或私有网络")
	}
	return nil
}

func isPublicWebhookIP(ip net.IP) bool {
	return ip.IsGlobalUnicast() &&
		!ip.IsPrivate() &&
		!ip.IsLoopback() &&
		!ip.IsUnspecified() &&
		!ip.IsLinkLocalUnicast() &&
		!ip.IsLinkLocalMulticast()
}

func webhookHTTPClient() *http.Client {
	dialer := &net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(address)
			if err != nil {
				return nil, fmt.Errorf("Webhook 地址无效: %w", err)
			}
			ips, err := net.DefaultResolver.LookupIP(ctx, "ip", host)
			if err != nil {
				return nil, fmt.Errorf("解析 Webhook 主机失败: %w", err)
			}
			for _, ip := range ips {
				if !isPublicWebhookIP(ip) {
					return nil, fmt.Errorf("Webhook URL 不允许指向本机或私有网络")
				}
			}
			if len(ips) == 0 {
				return nil, fmt.Errorf("Webhook 主机没有可用地址")
			}
			return dialer.DialContext(ctx, network, net.JoinHostPort(ips[0].String(), port))
		},
	}
	return &http.Client{
		Timeout:   10 * time.Second,
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return fmt.Errorf("Webhook 重定向次数过多")
			}
			return validateWebhookURL(req.URL.String())
		},
	}
}

func isValidEvent(event string) bool {
	switch event {
	case model.EventTaskCreated, model.EventTaskCompleted,
		model.EventTaskDeleted, model.EventTaskUpdated,
		model.EventHabitChecked, model.EventSessionEnded:
		return true
	}
	return false
}
