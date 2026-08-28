package caldav

import (
	"bytes"
	"database/sql"
	"log"
	"strings"
	"testing"

	_ "github.com/jackc/pgx/v5/stdlib"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func TestRunSyncAllLogsConfigQueryFailure(t *testing.T) {
	sqlDB, err := sql.Open("pgx", "postgres://invalid:invalid@127.0.0.1:1/invalid")
	if err != nil {
		t.Fatalf("open database handle: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close database handle: %v", err)
	}
	db, err := gorm.Open(
		postgres.New(postgres.Config{Conn: sqlDB}),
		&gorm.Config{DisableAutomaticPing: true},
	)
	if err != nil {
		t.Fatalf("open gorm handle: %v", err)
	}

	var output bytes.Buffer
	previousWriter := log.Writer()
	previousFlags := log.Flags()
	log.SetOutput(&output)
	log.SetFlags(0)
	t.Cleanup(func() {
		log.SetOutput(previousWriter)
		log.SetFlags(previousFlags)
	})

	runSyncAll(db)

	if !strings.Contains(output.String(), "[CalDAV] 查询配置失败") {
		t.Fatalf("expected query failure log, got %q", output.String())
	}
}
