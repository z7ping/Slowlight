package caldav

import (
	"errors"
	"log"
	"time"

	"slowlight/internal/model"

	"gorm.io/gorm"
)

// StartCron 启动 CalDAV 定时同步 goroutine
func StartCron(db *gorm.DB, interval time.Duration) {
	if interval == 0 {
		interval = 5 * time.Minute
	}

	log.Printf("[CalDAV] 定时同步已启动，间隔 %v", interval)

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for range ticker.C {
			runSyncAll(db)
		}
	}()
}

// SyncOnStartup 启动时对所有配置了 CalDAV 的用户执行一次同步
func SyncOnStartup(db *gorm.DB) {
	go func() {
		log.Println("[CalDAV] 启动同步开始")
		runSyncAll(db)
		log.Println("[CalDAV] 启动同步完成")
	}()
}

// runSyncAll 遍历所有配置了 CalDAV 的用户，逐个同步
func runSyncAll(db *gorm.DB) {
	var configs []model.UserConfig
	result := db.Where("key = ?", "caldav").Find(&configs)
	if result.Error != nil {
		log.Printf("[CalDAV] 查询配置失败: %v", result.Error)
		return
	}

	if len(configs) == 0 {
		return
	}

	for _, config := range configs {
		userID := config.UserID

		result, err := SyncAll(db, userID)
		if err != nil {
			// 配置不完整（缺凭据/路径）：跳过该用户，不作为失败
			if errors.Is(err, ErrConfigIncomplete) {
				continue
			}
			log.Printf("[CalDAV] 用户 %d 同步失败: %v", userID, err)
			continue
		}

		if result.TasksCreated > 0 || result.TasksUpdated > 0 {
			log.Printf("[CalDAV] 用户 %d 同步: 项目=%d 新增=%d 更新=%d",
				userID, result.ProjectsSynced, result.TasksCreated, result.TasksUpdated)
		}
	}
}
