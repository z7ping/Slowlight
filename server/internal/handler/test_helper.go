package handler

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"slowlight/internal/model"
)

var (
	sharedTestDB     *gorm.DB
	sharedTestDBOnce sync.Once
	sharedTestDBErr  error
	transportMu      sync.Mutex
)

func getSharedTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	sharedTestDBOnce.Do(func() {
		dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
		if dsn == "" {
			sharedTestDBErr = fmt.Errorf("TEST_DATABASE_URL is not configured")
			return
		}
		sharedTestDB, sharedTestDBErr = gorm.Open(postgres.Open(dsn), &gorm.Config{
			Logger: logger.Default.LogMode(logger.Silent),
		})
		if sharedTestDBErr == nil {
			sqlDB, _ := sharedTestDB.DB()
			sqlDB.SetMaxOpenConns(5)
			sqlDB.SetMaxIdleConns(2)
		}
	})
	if sharedTestDBErr != nil {
		t.Skipf("跳过依赖数据库的测试: %v", sharedTestDBErr)
	}
	return sharedTestDB
}

func setupTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db := getSharedTestDB(t)
	db.AutoMigrate(
		&model.User{},
		&model.List{},
		&model.Task{},
		&model.Subtask{},
		&model.Tag{},
		&model.TaskTag{},
		&model.Habit{},
		&model.HabitLog{},
		&model.UserConfig{},
		&model.SystemTag{},
		&model.BehaviorEvent{},
		&model.Reflection{},
		&model.WorkSession{},
		&model.ReminderConfig{},
		&model.ReminderSession{},
		&model.CalDAVSyncState{},
		&model.Webhook{},
	)
	return db
}

func beginTx(t *testing.T, db *gorm.DB) *gorm.DB {
	t.Helper()
	tx := db.Begin()
	t.Cleanup(func() { tx.Rollback() })
	return tx
}

var testCounter int

func uniqueName(prefix string) string {
	testCounter++
	return prefix + "_" + strconv.Itoa(testCounter)
}

func newTestGin() *gin.Engine {
	gin.SetMode(gin.TestMode)
	return gin.New()
}

func withUser(c *gin.Context, userID uint) {
	c.Set("userID", userID)
}

func newTestContext(method, path string, userID uint) (*gin.Context, *httptest.ResponseRecorder) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request, _ = http.NewRequest(method, path, nil)
	withUser(c, userID)
	return c, w
}

func createTestUser(t *testing.T, db *gorm.DB) model.User {
	t.Helper()
	name := uniqueName("testuser")
	user := model.User{
		Username: name,
		Email:    name + "@example.com",
		Password: "$2a$10$fakehashedpassword",
		Nickname: "测试用户",
	}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("创建测试用户失败: %v", err)
	}
	return user
}

func createTestList(t *testing.T, db *gorm.DB, userID uint, name string) model.List {
	t.Helper()
	list := model.List{
		UserID: userID,
		Name:   name,
		Icon:   "📋",
		Color:  "#1890ff",
	}
	if err := db.Create(&list).Error; err != nil {
		t.Fatalf("创建测试清单失败: %v", err)
	}
	return list
}

func createTestTask(t *testing.T, db *gorm.DB, userID, listID uint, title string) model.Task {
	t.Helper()
	task := model.Task{
		UserID:   userID,
		ListID:   listID,
		Title:    title,
		Priority: "high",
	}
	if err := db.Create(&task).Error; err != nil {
		t.Fatalf("创建测试任务失败: %v", err)
	}
	return task
}

func createDefaultSystemTags(t *testing.T, db *gorm.DB, userID uint) []model.SystemTag {
	t.Helper()
	tags := []model.SystemTag{
		{UserID: userID, Name: "身体", Icon: "💪", Color: "#52c41a", DimensionKey: model.DimensionBody, SortOrder: 1, IsDefault: true},
		{UserID: userID, Name: "认知", Icon: "🧠", Color: "#1890ff", DimensionKey: model.DimensionCognition, SortOrder: 2, IsDefault: true},
		{UserID: userID, Name: "产出", Icon: "🎯", Color: "#722ed1", DimensionKey: model.DimensionOutput, SortOrder: 3, IsDefault: true},
		{UserID: userID, Name: "关系", Icon: "❤️", Color: "#eb2f96", DimensionKey: model.DimensionRelationship, SortOrder: 4, IsDefault: true},
	}
	if err := db.Create(&tags).Error; err != nil {
		t.Fatalf("创建默认系统标签失败: %v", err)
	}
	return tags
}
