package config

import (
	"database/sql"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestDefaultDBPoolConfig(t *testing.T) {
	settings := defaultDBPoolConfig()

	if settings.MaxOpenConnections != 20 || settings.MaxIdleConnections != 5 {
		t.Fatalf("unexpected connection limits: %+v", settings)
	}
	if settings.ConnectionMaxLifetime != 30*time.Minute || settings.ConnectionMaxIdleTime != 5*time.Minute {
		t.Fatalf("unexpected connection lifetimes: %+v", settings)
	}
}

func TestApplyDBPoolConfigSetsObservableLimit(t *testing.T) {
	db, err := sql.Open("pgx", "postgres://invalid:invalid@127.0.0.1:1/invalid")
	if err != nil {
		t.Fatalf("open test database handle: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })

	applyDBPoolConfig(db, defaultDBPoolConfig())

	if got := db.Stats().MaxOpenConnections; got != 20 {
		t.Fatalf("MaxOpenConnections = %d, want 20", got)
	}
}
