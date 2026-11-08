package handler

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"gorm.io/gorm"

	"slowlight/internal/model"
)

// The existing user_config table already has durable, user-scoped TEXT storage.
// A one-use undo receipt is committed in the SAME transaction as deletion,
// survives server restart and expires shortly after the UI action disappears.
const deletionUndoPrefix = "deletion_undo_"

var errDeletionUndoUnavailable = errors.New("删除撤销已失效，请刷新核对")

type deletionUndoEnvelope struct {
	Kind      string          `json:"kind"`
	ExpiresAt time.Time       `json:"expires_at"`
	Payload   json.RawMessage `json:"payload"`
}

func saveDeletionUndo(
	tx *gorm.DB, userID uint, kind string, payload interface{},
	requestedToken ...string,
) (string, error) {
	// Expired receipts are not recovery data; prune older user-scoped rows
	// opportunistically. substr avoids SQL LIKE underscore wildcards.
	cutoff := time.Now().UTC().Add(-10 * time.Minute)
	if err := tx.Unscoped().Where(
		"user_id = ? AND substr(key, 1, ?) = ? AND created_at < ?",
		userID, len(deletionUndoPrefix), deletionUndoPrefix, cutoff,
	).Delete(&model.UserConfig{}).Error; err != nil {
		return "", err
	}
	raw, err := json.Marshal(payload)
	if err != nil { return "", err }
	token := ""
	if len(requestedToken) > 0 {
		token = requestedToken[0]
		if !validDeletionUndoToken(token) {
			return "", errDeletionUndoUnavailable
		}
	} else {
		var random [16]byte
		if _, err := rand.Read(random[:]); err != nil { return "", err }
		token = hex.EncodeToString(random[:])
	}
	envelope, err := json.Marshal(deletionUndoEnvelope{
		Kind: kind,
		ExpiresAt: time.Now().UTC().Add(2 * time.Minute),
		Payload: raw,
	})
	if err != nil { return "", err }
	stored := model.UserConfig{
		UserID: userID,
		Key: deletionUndoPrefix + token,
		Value: string(envelope),
	}
	if err := tx.Create(&stored).Error; err != nil { return "", err }
	return token, nil
}

func loadDeletionUndo(
	tx *gorm.DB, userID uint, token, kind string,
) (json.RawMessage, *model.UserConfig, error) {
	if !validDeletionUndoToken(token) {
		return nil, nil, errDeletionUndoUnavailable
	}
	var stored model.UserConfig
	if err := tx.Where("user_id = ? AND key = ?",
		userID, deletionUndoPrefix+token).First(&stored).Error; err != nil {
		return nil, nil, errDeletionUndoUnavailable
	}
	var envelope deletionUndoEnvelope
	if err := json.Unmarshal([]byte(stored.Value), &envelope); err != nil ||
		envelope.Kind != kind || !time.Now().UTC().Before(envelope.ExpiresAt) {
		return nil, nil, errDeletionUndoUnavailable
	}
	return envelope.Payload, &stored, nil
}

func validDeletionUndoToken(token string) bool {
	if len(token) != 32 { return false }
	_, err := hex.DecodeString(token)
	return err == nil
}

// GET /undo-receipt?kind=list|system_tag&token=...
// A successful read proves the destructive write and its undo receipt
// committed in the same transaction, even if the DELETE response was lost.
// This endpoint is read-only, account scoped and does not consume the token.
func GetDeletionUndoReceipt(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		kind := c.Query("kind")
		if kind != "list" && kind != "system_tag" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "无效撤销类型"})
			return
		}
		if _, _, err := loadDeletionUndo(db, c.GetUint("userID"),
			c.Query("token"), kind); err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "未找到已提交的撤销凭据"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"confirmed": true})
	}
}
