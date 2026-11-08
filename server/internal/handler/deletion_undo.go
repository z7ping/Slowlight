package handler

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"

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
) (string, error) {
	raw, err := json.Marshal(payload)
	if err != nil { return "", err }
	var random [16]byte
	if _, err := rand.Read(random[:]); err != nil { return "", err }
	token := hex.EncodeToString(random[:])
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
	if len(token) != 32 {
		return nil, nil, errDeletionUndoUnavailable
	}
	if _, err := hex.DecodeString(token); err != nil {
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
