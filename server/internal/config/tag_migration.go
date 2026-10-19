package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strconv"
	"strings"

	"slowlight/internal/model"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type legacyTagKey struct {
	userID uint
	systemTagID uint
}

// backfillLegacyTagLinks is additive and safe to rerun. A persisted alias is a
// completed migration marker for its old tag: subsequent starts must not
// re-attach a tag that a user intentionally removed from a record.
func backfillLegacyTagLinks(db *gorm.DB) error {
	return db.Transaction(func(tx *gorm.DB) error {
		var reflections []model.Reflection
		if err := tx.Where("entry_type = ? AND deleted_at IS NULL", "observation").Find(&reflections).Error; err != nil {
			return err
		}
		refByTag := make(map[legacyTagKey][]uint)
		for _, reflection := range reflections {
			var ctx map[string]interface{}
			if json.Unmarshal([]byte(reflection.Context), &ctx) != nil {
				continue
			}
			id := legacyTagID(ctx["observation_tag_id"])
			if id > 0 {
				key := legacyTagKey{reflection.UserID, id}
				refByTag[key] = append(refByTag[key], reflection.ID)
			}
		}

		var legacy []model.SystemTag
		if err := tx.Order("id ASC").Find(&legacy).Error; err != nil {
			return err
		}
		for _, old := range legacy {
			key := legacyTagKey{old.UserID, old.ID}
			var alias model.LegacySystemTagAlias
			err := tx.Where("user_id = ? AND system_tag_id = ?", old.UserID, old.ID).Take(&alias).Error
			if err == nil {
				continue
			}
			if !errors.Is(err, gorm.ErrRecordNotFound) {
				return err
			}

			// Default dimension placeholders are not real user labels until used.
			if old.IsDefault {
				var count int64
				for _, entity := range []struct{ table string }{{"tasks"}, {"habits"}, {"work_sessions"}} {
					var n int64
					if err := tx.Table(entity.table).Where("user_id = ? AND system_tag_id = ?", old.UserID, old.ID).Count(&n).Error; err != nil {
						return err
					}
					count += n
				}
				if count == 0 && len(refByTag[key]) == 0 {
					continue
				}
			}

			name := strings.TrimSpace(old.Name)
			if name == "" {
				log.Printf("[tags] skip unnamed legacy tag %d (user %d)", old.ID, old.UserID)
				continue
			}
			var tag model.Tag
			err = tx.Unscoped().Where("user_id = ? AND name = ?", old.UserID, name).Take(&tag).Error
			if errors.Is(err, gorm.ErrRecordNotFound) {
				tag = model.Tag{UserID: old.UserID, Name: name, Color: old.Color}
				if err := tx.Create(&tag).Error; err != nil {
					return fmt.Errorf("create canonical tag for legacy %d: %w", old.ID, err)
				}
			} else if err != nil {
				return err
			} else if tag.DeletedAt.Valid {
				// Never resurrect user-deleted tags or prevent startup because of a
				// single legacy collision. Keep old links for a later safe resolution.
				log.Printf("[tags] skip legacy tag %d: canonical %d is deleted (user %d)", old.ID, tag.ID, old.UserID)
				continue
			}

			alias = model.LegacySystemTagAlias{UserID: old.UserID, SystemTagID: old.ID, TagID: tag.ID}
			if err := tx.Create(&alias).Error; err != nil {
				return err
			}
			if err := tx.Exec(`INSERT INTO task_tags (task_id, tag_id)
				SELECT id, ? FROM tasks WHERE user_id = ? AND system_tag_id = ?
				ON CONFLICT DO NOTHING`, tag.ID, old.UserID, old.ID).Error; err != nil {
				return err
			}
			if err := tx.Exec(`INSERT INTO habit_tags (habit_id, tag_id)
				SELECT id, ? FROM habits WHERE user_id = ? AND system_tag_id = ?
				ON CONFLICT DO NOTHING`, tag.ID, old.UserID, old.ID).Error; err != nil {
				return err
			}
			if err := tx.Exec(`INSERT INTO work_session_tags (work_session_id, tag_id)
				SELECT id, ? FROM work_sessions WHERE user_id = ? AND system_tag_id = ?
				ON CONFLICT DO NOTHING`, tag.ID, old.UserID, old.ID).Error; err != nil {
				return err
			}
			for _, reflectionID := range refByTag[key] {
				link := model.ReflectionTag{ReflectionID: reflectionID, TagID: tag.ID}
				if err := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&link).Error; err != nil {
					return err
				}
			}
		}
		return nil
	})
}

func legacyTagID(value interface{}) uint {
	switch v := value.(type) {
	case float64:
		if v <= 0 || v != float64(uint64(v)) {
			return 0
		}
		return uint(v)
	case string:
		parsed, err := strconv.ParseUint(strings.TrimSpace(v), 10, 64)
		if err == nil {
			return uint(parsed)
		}
	}
	return 0
}
