package main

import (
	"log"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"slowlight/internal/caldav"
	"slowlight/internal/config"
	"slowlight/internal/handler"
	"slowlight/internal/integration"
)

func main() {
	config.LoadEnv(".env")
	db, err := config.InitDB()
	if err != nil {
		log.Fatal("数据库连接失败:", err)
	}

	r := gin.Default()
	corsOrigins := getCorsOrigins()
	r.Use(func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")
		if origin != "" && isOriginAllowed(origin, corsOrigins) {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Credentials", "true")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	authHandler := handler.NewAuthHandler(db)
	r.POST("/api/auth/register", authHandler.Register)
	r.POST("/api/auth/login", authHandler.Login)

	api := r.Group("/api")
	api.Use(handler.AuthMiddleware())
	{
		api.GET("/auth/profile", authHandler.GetProfile)

		taskHandler := handler.NewTaskHandler(db)
		listHandler := handler.NewListHandler(db)
		subtaskHandler := handler.NewSubtaskHandler(db)
		sessionHandler := handler.NewSessionHandler(db)
		tagHandler := handler.NewTagHandler(db)

		api.GET("/lists", listHandler.GetLists)
		api.GET("/lists/stats", listHandler.GetStats)
		api.GET("/lists/:id/tasks", taskHandler.GetTasksByList)
		api.POST("/lists", listHandler.CreateList)
		api.PUT("/lists/:id", listHandler.UpdateList)
		api.DELETE("/lists/:id", listHandler.DeleteList)

		api.GET("/tags", tagHandler.GetTags)
		api.GET("/tags/stats", tagHandler.GetStats)
		api.GET("/tags/:id/tasks", tagHandler.GetTasksByTag)
		api.POST("/tags", tagHandler.CreateTag)
		api.PUT("/tags/:id", tagHandler.UpdateTag)
		api.DELETE("/tags/:id", tagHandler.DeleteTag)

		api.GET("/tasks", taskHandler.GetTasks)
		api.GET("/tasks/search", taskHandler.SearchTasks)
		api.GET("/tasks/:id", taskHandler.GetTask)
		api.GET("/tasks/today", taskHandler.GetTodayTasks)
		api.GET("/tasks/completed", taskHandler.GetCompletedTasks)
		api.POST("/tasks", taskHandler.CreateTask)
		api.PUT("/tasks/:id", taskHandler.UpdateTask)
		api.DELETE("/tasks/:id", taskHandler.DeleteTask)
		api.PATCH("/tasks/:id/complete", taskHandler.CompleteTask)
		api.PATCH("/tasks/:id/postpone", taskHandler.PostponeTask)
		api.GET("/tasks/stats", taskHandler.GetStatsConsistent)

		api.GET("/tasks/:id/subtasks", subtaskHandler.GetSubtasks)
		api.GET("/tasks/:id/subtasks/progress", subtaskHandler.GetSubtaskProgress)
		api.POST("/tasks/:id/subtasks", subtaskHandler.CreateSubtask)
		api.PUT("/tasks/:id/subtasks/:subtaskId", subtaskHandler.UpdateSubtask)
		api.PATCH("/tasks/:id/subtasks/:subtaskId/toggle", subtaskHandler.ToggleSubtask)
		api.DELETE("/tasks/:id/subtasks/:subtaskId", subtaskHandler.DeleteSubtask)

		api.POST("/sessions/start", sessionHandler.StartSession)
		api.POST("/sessions/end", sessionHandler.EndSession)
		api.GET("/sessions/active", sessionHandler.GetActiveSession)
		api.GET("/sessions/stats", sessionHandler.GetStats)
		api.GET("/sessions/today", sessionHandler.GetTodayStats)

		reminderHandler := handler.NewReminderHandler(db)
		api.GET("/reminder/config", reminderHandler.GetConfig)
		api.PUT("/reminder/config", reminderHandler.SaveConfig)
		api.POST("/reminder/start-work", reminderHandler.StartWork)
		api.POST("/reminder/start-rest", reminderHandler.StartRest)
		api.POST("/reminder/end-rest", reminderHandler.EndRest)
		api.POST("/reminder/skip-rest", reminderHandler.SkipRest)
		api.GET("/reminder/stats", reminderHandler.GetStats)
		api.GET("/reminder/today", reminderHandler.GetTodayStats)

		habitHandler := handler.NewHabitHandler(db)
		api.GET("/habits", habitHandler.GetHabits)
		api.POST("/habits", habitHandler.CreateHabit)
		api.PUT("/habits/:id", habitHandler.UpdateHabit)
		api.DELETE("/habits/:id", habitHandler.DeleteHabit)
		api.POST("/habits/:id/checkin", habitHandler.CheckInHabit)
		api.DELETE("/habits/:id/checkin", habitHandler.UncheckInHabit)
		api.GET("/habits/:id/logs", habitHandler.GetHabitLogs)
		api.PUT("/habits/:id/logs/:logId", habitHandler.UpdateHabitLog)
		api.GET("/habits/:id/streak", habitHandler.GetHabitStreak)

		systemTagHandler := handler.NewSystemTagHandler(db)
		api.GET("/system-tags", systemTagHandler.GetSystemTags)
		api.POST("/system-tags", systemTagHandler.CreateSystemTag)
		api.PUT("/system-tags/:id", systemTagHandler.UpdateSystemTag)
		api.DELETE("/system-tags/:id", systemTagHandler.DeleteSystemTag)

		syncChangesHandler := handler.NewSyncChangesHandler(db)
		api.GET("/sync/changes", syncChangesHandler.GetChanges)

		migrationHandler := handler.NewMigrationHandler(db)
		api.POST("/migration/preview", migrationHandler.PreviewMigration)
		api.POST("/migration/execute", migrationHandler.ExecuteMigration)
		api.GET("/migration/reports/latest", migrationHandler.GetLatestReport)
		api.GET("/migration/reports", migrationHandler.GetReports)

		reviewHandler := handler.NewReviewHandler(db)
		api.GET("/review/today", reviewHandler.GetTodayReview)
		api.GET("/review/tasks", reviewHandler.GetTasksReview)

		// 用户自己的 Observation / Reflection，是 Review 闭环的一部分。
		reflectionHandler := handler.NewReflectionHandler(db)
		api.GET("/reflections", reflectionHandler.List)
		api.POST("/reflections", reflectionHandler.Create)

		analyticsHandler := handler.NewAnalyticsHandler(db)
		api.GET("/analytics/output", analyticsHandler.GetOutputStats)
		api.GET("/analytics/time-distribution", analyticsHandler.GetTimeDistribution)
		api.GET("/analytics/weekly-review", analyticsHandler.GetWeeklyReview)
		api.GET("/analytics/daily-trend", analyticsHandler.GetDailyTrendConsistent)
		api.GET("/analytics/dimension-summary", analyticsHandler.GetDimensionSummaryConsistent)

		integrationHandler := integration.NewHandler(db)
		api.GET("/integration/platforms", integrationHandler.ListPlatforms)
		api.GET("/integration/:platform/config", integrationHandler.GetConfig)
		api.POST("/integration/:platform/config", integrationHandler.SaveConfig)
		api.POST("/integration/:platform/create-template", integrationHandler.CreateTemplate)
		api.POST("/integration/:platform/connect-existing", integrationHandler.ConnectExisting)
		api.POST("/integration/:platform/sync-all", integrationHandler.SyncAll)
		api.POST("/integration/:platform/sync-tasks", integrationHandler.SyncTasks)
		api.POST("/integration/:platform/sync-sessions", integrationHandler.SyncSessions)
		api.POST("/integration/:platform/sync-reminders", integrationHandler.SyncReminders)
		api.POST("/integration/:platform/sync-tags", integrationHandler.SyncTags)
		api.POST("/integration/:platform/import", integrationHandler.Import)
		api.GET("/integration/:platform/calendars", integrationHandler.ListCalendars)
		api.POST("/integration/:platform/sync-calendar", integrationHandler.SyncToCalendar)

		webhookHandler := handler.NewWebhookHandler(db)
		api.GET("/webhooks", webhookHandler.List)
		api.POST("/webhooks", webhookHandler.Create)
		api.PUT("/webhooks/:id", webhookHandler.Update)
		api.DELETE("/webhooks/:id", webhookHandler.Delete)
		api.POST("/webhooks/:id/test", webhookHandler.Test)

		inboxHandler := handler.NewInboxHandler(db)
		api.GET("/inbox", inboxHandler.GetInbox)
		api.POST("/inbox", inboxHandler.QuickAdd)
		api.POST("/inbox/:id/move", inboxHandler.MoveTo)
		api.GET("/inbox/count", inboxHandler.GetCount)

		caldavHandler := caldav.NewHandler(db)
		api.GET("/caldav/config", caldavHandler.GetConfig)
		api.POST("/caldav/config", caldavHandler.SaveConfig)
		api.POST("/caldav/sync", caldavHandler.Sync)
		api.GET("/caldav/status", caldavHandler.GetStatus)
		api.POST("/caldav/test", caldavHandler.Test)

		api.GET("/feishu/config", func(c *gin.Context) {
			c.Request.URL.Path = "/api/integration/feishu/config"
			r.HandleContext(c)
		})
	}

	caldav.StartCron(db, 5*time.Minute)
	caldav.SyncOnStartup(db)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("服务启动在端口 %s", port)
	r.Run(":" + port)
}

func getCorsOrigins() []string {
	env := os.Getenv("CORS_ALLOW_ORIGINS")
	if env == "" {
		return []string{
			"http://localhost:3000",
			"http://localhost:8080",
			"http://localhost:8088",
			"http://127.0.0.1:3000",
			"http://127.0.0.1:8080",
			"http://127.0.0.1:8088",
		}
	}
	origins := strings.Split(env, ",")
	for i := range origins {
		origins[i] = strings.TrimSpace(origins[i])
	}
	return origins
}

func isOriginAllowed(origin string, allowed []string) bool {
	for _, a := range allowed {
		if strings.EqualFold(a, origin) {
			return true
		}
	}
	return false
}
