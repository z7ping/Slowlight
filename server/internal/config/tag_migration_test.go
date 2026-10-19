package config

import (
	"fmt"
	"os"
	"testing"
	"time"

	"slowlight/internal/model"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func TestLegacyTagID(t *testing.T) {
	for _, tc := range []struct {
		in interface{}
		want uint
	}{
		{float64(2), 2}, {"42", 42}, {"0", 0}, {float64(-1), 0},
		{"bad", 0}, {float64(2.5), 0}, {nil, 0},
	} {
		if got := legacyTagID(tc.in); got != tc.want {
			t.Errorf("legacyTagID(%v) = %d; want %d", tc.in, got, tc.want)
		}
	}
}

func TestBackfillLegacyTagLinksReusesCanonicalAndIsIdempotent(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("requires TEST_DATABASE_URL")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(
		&model.User{}, &model.List{}, &model.Tag{}, &model.SystemTag{},
		&model.Task{}, &model.TaskTag{}, &model.Habit{}, &model.WorkSession{},
		&model.Reflection{}, &model.LegacySystemTagAlias{}, &model.HabitTag{},
		&model.WorkSessionTag{}, &model.ReflectionTag{},
	); err != nil {
		t.Fatal(err)
	}
	tx := db.Begin()
	if tx.Error != nil {
		t.Fatal(tx.Error)
	}
	t.Cleanup(func() { tx.Rollback() })

	suffix := fmt.Sprintf("tag_migration_%d", time.Now().UnixNano())
	user := model.User{Username: suffix, Email: suffix + "@test.invalid", Password: "hash"}
	if err := tx.Create(&user).Error; err != nil {
		t.Fatal(err)
	}
	otherUser := model.User{Username: suffix + "_other", Email: suffix + "_other@test.invalid", Password: "hash"}
	if err := tx.Create(&otherUser).Error; err != nil {
		t.Fatal(err)
	}
	existing := model.Tag{UserID: user.ID, Name: "学习", Color: "#abcdef"}
	if err := tx.Create(&existing).Error; err != nil {
		t.Fatal(err)
	}
	legacy := model.SystemTag{UserID: user.ID, Name: "学习", Icon: "📚", Color: "#123456"}
	if err := tx.Create(&legacy).Error; err != nil {
		t.Fatal(err)
	}
	other := model.SystemTag{UserID: otherUser.ID, Name: "学习", Icon: "📚", Color: "#123456"}
	if err := tx.Create(&other).Error; err != nil {
		t.Fatal(err)
	}
	unused := model.SystemTag{UserID: user.ID, Name: "身体", IsDefault: true, Icon: "💪"}
	if err := tx.Create(&unused).Error; err != nil {
		t.Fatal(err)
	}
	list := model.List{UserID: user.ID, Name: "工作"}
	if err := tx.Create(&list).Error; err != nil {
		t.Fatal(err)
	}
	task := model.Task{UserID: user.ID, ListID: list.ID, Title: "读书", SystemTagID: &legacy.ID}
	if err := tx.Create(&task).Error; err != nil {
		t.Fatal(err)
	}
	habit := model.Habit{UserID: user.ID, Name: "早读", SystemTagID: &legacy.ID}
	if err := tx.Create(&habit).Error; err != nil {
		t.Fatal(err)
	}
	session := model.WorkSession{
		UserID: user.ID, SessionType: "work", StartedAt: time.Now(),
		SystemTagID: &legacy.ID,
	}
	if err := tx.Create(&session).Error; err != nil {
		t.Fatal(err)
	}
	reflection := model.Reflection{
		UserID: user.ID, EntryType: "observation", Content: "在阅读",
		Context: fmt.Sprintf(`{"observation_tag_id": %d}`, legacy.ID),
	}
	if err := tx.Create(&reflection).Error; err != nil {
		t.Fatal(err)
	}

	if err := backfillLegacyTagLinks(tx); err != nil {
		t.Fatal(err)
	}
	var alias model.LegacySystemTagAlias
	if err := tx.Where("user_id = ? AND system_tag_id = ?", user.ID, legacy.ID).Take(&alias).Error; err != nil {
		t.Fatal(err)
	}
	if alias.TagID != existing.ID {
		t.Fatalf("expected reuse of canonical tag %d, got %d", existing.ID, alias.TagID)
	}
	check := func(table string, field string, id uint, want int64) {
		t.Helper()
		var n int64
		if err := tx.Table(table).Where(field+" = ? AND tag_id = ?", id, existing.ID).Count(&n).Error; err != nil {
			t.Fatal(err)
		}
		if n != want {
			t.Errorf("%s references: got %d want %d", table, n, want)
		}
	}
	check("task_tags", "task_id", task.ID, 1)
	check("habit_tags", "habit_id", habit.ID, 1)
	check("work_session_tags", "work_session_id", session.ID, 1)
	check("reflection_tags", "reflection_id", reflection.ID, 1)

	var skipped int64
	if err := tx.Model(&model.LegacySystemTagAlias{}).
		Where("user_id = ? AND system_tag_id = ?", user.ID, unused.ID).Count(&skipped).Error; err != nil {
		t.Fatal(err)
	}
	if skipped != 0 {
		t.Fatal("unused default dimension must not become a user label")
	}

	var otherAlias model.LegacySystemTagAlias
	if err := tx.Where("user_id = ? AND system_tag_id = ?", otherUser.ID, other.ID).Take(&otherAlias).Error; err != nil {
		t.Fatal(err)
	}
	if otherAlias.TagID == existing.ID {
		t.Fatal("cross-user tag mapping")
	}

	// Rerun must not silently restore deliberately removed link.
	if err := tx.Where("habit_id = ? AND tag_id = ?", habit.ID, existing.ID).
		Delete(&model.HabitTag{}).Error; err != nil {
		t.Fatal(err)
	}
	if err := backfillLegacyTagLinks(tx); err != nil {
		t.Fatal(err)
	}
	check("habit_tags", "habit_id", habit.ID, 0)
	check("task_tags", "task_id", task.ID, 1)
}
