package config

import (
	"bufio"
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

type dbPoolConfig struct {
	MaxOpenConnections    int
	MaxIdleConnections    int
	ConnectionMaxLifetime time.Duration
	ConnectionMaxIdleTime time.Duration
}

func defaultDBPoolConfig() dbPoolConfig {
	return dbPoolConfig{
		MaxOpenConnections:    20,
		MaxIdleConnections:    5,
		ConnectionMaxLifetime: 30 * time.Minute,
		ConnectionMaxIdleTime: 5 * time.Minute,
	}
}

func applyDBPoolConfig(db *sql.DB, config dbPoolConfig) {
	db.SetMaxOpenConns(config.MaxOpenConnections)
	db.SetMaxIdleConns(config.MaxIdleConnections)
	db.SetConnMaxLifetime(config.ConnectionMaxLifetime)
	db.SetConnMaxIdleTime(config.ConnectionMaxIdleTime)
}

func LoadEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])
		if len(value) >= 2 && (value[0] == '"' && value[len(value)-1] == '"' || value[0] == '\'' && value[len(value)-1] == '\'') {
			value = value[1 : len(value)-1]
		}
		if os.Getenv(key) == "" {
			os.Setenv(key, value)
		}
	}
}

func InitDB() (*gorm.DB, error) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		return nil, fmt.Errorf("DATABASE_URL environment variable is required")
	}

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		return nil, err
	}
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("获取数据库连接池失败: %w", err)
	}
	applyDBPoolConfig(sqlDB, defaultDBPoolConfig())

	pingContext, cancelPing := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelPing()
	if err := sqlDB.PingContext(pingContext); err != nil {
		_ = sqlDB.Close()
		return nil, fmt.Errorf("数据库连通性检查失败: %w", err)
	}

	if err := db.AutoMigrate(
		&model.User{},
		&model.List{},
		&model.Task{},
		&model.Subtask{},
		&model.Tag{},
		&model.TaskTag{},
		&model.Habit{},
		&model.HabitLog{},
		&model.UserConfig{},
		&model.Webhook{},
		&model.SystemTag{},
		&model.BehaviorEvent{},
		&model.Reflection{},
		&model.CalDAVSyncState{},
		&model.MigrationReport{},
	); err != nil {
		return nil, fmt.Errorf("数据库迁移失败: %w", err)
	}

	// 兼容旧版本：四个默认 SystemTag 保留，但映射到稳定 Dimension。
	for _, dimension := range model.Dimensions {
		if err := db.Model(&model.SystemTag{}).
			Where("name = ? AND (dimension_key = '' OR dimension_key IS NULL)", dimension.Name).
			Update("dimension_key", dimension.Key).Error; err != nil {
			return nil, fmt.Errorf("回填 dimension_key 失败: %w", err)
		}
	}

	return db, nil
}
