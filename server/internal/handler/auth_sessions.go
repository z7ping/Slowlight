package handler

import (
    "crypto/rand"
    "crypto/sha256"
    "encoding/base64"
    "encoding/hex"
    "errors"
    "net/http"
    "time"

    "github.com/gin-gonic/gin"
    "gorm.io/gorm"
    "gorm.io/gorm/clause"

    "slowlight/internal/model"
)

const authRefreshLifetime = 30 * 24 * time.Hour

var errRefreshRejected = errors.New("invalid refresh token")

type refreshRequest struct {
    RefreshToken string `json:"refresh_token" binding:"required"`
}

func refreshHash(token string) string {
    hash := sha256.Sum256([]byte(token))
    return hex.EncodeToString(hash[:])
}

func newRefreshSecret() (string, error) {
    bytes := make([]byte, 32)
    if _, err := rand.Read(bytes); err != nil {
        return "", err
    }
    return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func issueAuthSession(db *gorm.DB, userID uint, method string) (string, string, error) {
    access, err := generateTokenWithMethod(userID, method)
    if err != nil { return "", "", err }
    refresh, err := newRefreshSecret()
    if err != nil { return "", "", err }
    session := model.AuthRefreshSession{
        TokenHash: refreshHash(refresh), UserID: userID, Method: method,
        ExpiresAt: time.Now().UTC().Add(authRefreshLifetime),
    }
    if err := db.Create(&session).Error; err != nil { return "", "", err }
    return access, refresh, nil
}

// Refresh 使用单次有效的旋转令牌；旧令牌重放不能生成新的会话。
// 事务中的 FOR UPDATE 保证并发请求只有一个能够完成轮换。
func (h *AuthHandler) Refresh(c *gin.Context) {
    var req refreshRequest
    if err := c.ShouldBindJSON(&req); err != nil || len(req.RefreshToken) > 512 {
        c.JSON(http.StatusBadRequest, gin.H{"error": "刷新凭据无效"})
        return
    }
    hash := refreshHash(req.RefreshToken)
    var access, refresh string
    err := h.DB.Transaction(func(tx *gorm.DB) error {
        var current model.AuthRefreshSession
        if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
            Where("token_hash = ?", hash).First(&current).Error; err != nil {
            if errors.Is(err, gorm.ErrRecordNotFound) { return errRefreshRejected }
            return err
        }
        now := time.Now().UTC()
        if current.RevokedAt != nil || !current.ExpiresAt.After(now) {
            return errRefreshRejected
        }
        var count int64
        if err := tx.Model(&model.User{}).Where("id = ?", current.UserID).
            Count(&count).Error; err != nil { return err }
        if count != 1 { return errRefreshRejected }
        nextAccess, err := generateTokenWithMethod(current.UserID, current.Method)
        if err != nil { return err }
        nextRefresh, err := newRefreshSecret()
        if err != nil { return err }
        if err := tx.Model(&current).Update("revoked_at", now).Error; err != nil { return err }
        next := model.AuthRefreshSession{
            TokenHash: refreshHash(nextRefresh), UserID: current.UserID,
            Method: current.Method, ExpiresAt: now.Add(authRefreshLifetime),
        }
        if err := tx.Create(&next).Error; err != nil { return err }
        access, refresh = nextAccess, nextRefresh
        return nil
    })
    if err != nil {
        if errors.Is(err, errRefreshRejected) {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "会话已失效，请重新登录"})
        } else {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "续期失败"})
        }
        return
    }
    c.Header("Cache-Control", "no-store")
    c.JSON(http.StatusOK, gin.H{"token": access, "refresh_token": refresh})
}

// Logout 撤销当前设备的 Refresh Token；过期 Access JWT 无需参与注销。
func (h *AuthHandler) Logout(c *gin.Context) {
    var req refreshRequest
    if err := c.ShouldBindJSON(&req); err != nil || len(req.RefreshToken) > 512 {
        c.JSON(http.StatusBadRequest, gin.H{"error": "退出凭据无效"})
        return
    }
    now := time.Now().UTC()
    if err := h.DB.Model(&model.AuthRefreshSession{}).
        Where("token_hash = ? AND revoked_at IS NULL", refreshHash(req.RefreshToken)).
        Update("revoked_at", now).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "注销失败"})
        return
    }
    c.Status(http.StatusNoContent)
}
