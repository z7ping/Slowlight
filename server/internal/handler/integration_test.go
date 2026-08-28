package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// setupIntegrationServer 创建完整的 API 测试服务器
func setupIntegrationServer(t *testing.T) (*httptest.Server, *gorm.DB) {
	db := setupTestDB(t)
	tx := beginTx(t, db)

	gin.SetMode(gin.TestMode)
	r := gin.New()

	// CORS
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	// 公开路由
	authHandler := NewAuthHandler(tx)
	r.POST("/api/auth/register", authHandler.Register)
	r.POST("/api/auth/login", authHandler.Login)

	// 认证路由
	api := r.Group("/api")
	api.Use(AuthMiddleware())
	{
		api.GET("/auth/profile", authHandler.GetProfile)

		taskHandler := NewTaskHandler(tx)
		listHandler := NewListHandler(tx)
		subtaskHandler := NewSubtaskHandler(tx)
		sessionHandler := NewSessionHandler(tx)
		tagHandler := NewTagHandler(tx)
		habitHandler := NewHabitHandler(tx)
		reminderHandler := NewReminderHandler(tx)

		api.GET("/lists", listHandler.GetLists)
		api.POST("/lists", listHandler.CreateList)
		api.PUT("/lists/:id", listHandler.UpdateList)
		api.DELETE("/lists/:id", listHandler.DeleteList)

		api.GET("/tags", tagHandler.GetTags)
		api.POST("/tags", tagHandler.CreateTag)
		api.PUT("/tags/:id", tagHandler.UpdateTag)
		api.DELETE("/tags/:id", tagHandler.DeleteTag)

		api.GET("/tasks", taskHandler.GetTasks)
		api.GET("/tasks/search", taskHandler.SearchTasks)
		api.GET("/tasks/:id", taskHandler.GetTask)
		api.POST("/tasks", taskHandler.CreateTask)
		api.PUT("/tasks/:id", taskHandler.UpdateTask)
		api.DELETE("/tasks/:id", taskHandler.DeleteTask)
		api.PATCH("/tasks/:id/complete", taskHandler.CompleteTask)
		api.GET("/tasks/stats", taskHandler.GetStats)

		api.GET("/tasks/:id/subtasks", subtaskHandler.GetSubtasks)
		api.POST("/tasks/:id/subtasks", subtaskHandler.CreateSubtask)
		api.PATCH("/tasks/:id/subtasks/:subtaskId/toggle", subtaskHandler.ToggleSubtask)

		api.POST("/sessions/start", sessionHandler.StartSession)
		api.POST("/sessions/end", sessionHandler.EndSession)
		api.GET("/sessions/active", sessionHandler.GetActiveSession)

		api.POST("/habits", habitHandler.CreateHabit)
		api.POST("/habits/:id/checkin", habitHandler.CheckInHabit)
		api.GET("/habits/:id/streak", habitHandler.GetHabitStreak)

		api.GET("/reminder/config", reminderHandler.GetConfig)
		api.POST("/reminder/config", reminderHandler.SaveConfig)
		api.POST("/reminder/start-work", reminderHandler.StartWork)
		api.POST("/reminder/start-rest", reminderHandler.StartRest)
		api.POST("/reminder/end-rest", reminderHandler.EndRest)
	}

	return httptest.NewServer(r), tx
}

// apiRequest 发送 HTTP 请求并返回响应
func apiRequest(t *testing.T, method, url, token string, body interface{}) (int, []byte) {
	t.Helper()

	var bodyReader io.Reader
	if body != nil {
		jsonBody, _ := json.Marshal(body)
		bodyReader = bytes.NewBuffer(jsonBody)
	}

	req, err := http.NewRequest(method, url, bodyReader)
	if err != nil {
		t.Fatalf("创建请求失败: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, respBody
}

// registerAndLogin 注册用户并返回 token
func registerAndLogin(t *testing.T, baseURL, username string) string {
	t.Helper()

	// 注册
	regBody := map[string]interface{}{
		"username": username,
		"email":    username + "@test.com",
		"password": "123456",
	}
	status, body := apiRequest(t, "POST", baseURL+"/api/auth/register", "", regBody)
	if status != http.StatusCreated {
		t.Fatalf("注册失败: %d %s", status, string(body))
	}

	var regResp map[string]interface{}
	json.Unmarshal(body, &regResp)
	return regResp["token"].(string)
}

// ==========================================
// 集成测试 1: 完整用户生命周期
// ==========================================

func TestIntegration_UserLifecycle(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL

	// 1. 注册
	username := uniqueName("lifecycle")
	regBody := map[string]interface{}{
		"username": username,
		"email":    username + "@test.com",
		"password": "123456",
		"nickname": "生命周期测试",
	}
	status, body := apiRequest(t, "POST", baseURL+"/api/auth/register", "", regBody)
	if status != http.StatusCreated {
		t.Fatalf("注册失败: %d", status)
	}
	var regResp map[string]interface{}
	json.Unmarshal(body, &regResp)
	token := regResp["token"].(string)
	t.Log("✅ 注册成功")

	// 2. 登录
	loginBody := map[string]interface{}{
		"username": username,
		"password": "123456",
	}
	status, _ = apiRequest(t, "POST", baseURL+"/api/auth/login", "", loginBody)
	if status != http.StatusOK {
		t.Fatalf("登录失败: %d", status)
	}
	t.Log("✅ 登录成功")

	// 3. 获取用户信息
	status, body = apiRequest(t, "GET", baseURL+"/api/auth/profile", token, nil)
	if status != http.StatusOK {
		t.Fatalf("获取用户信息失败: %d", status)
	}
	var profile map[string]interface{}
	json.Unmarshal(body, &profile)
	if profile["username"] != username {
		t.Errorf("用户名不匹配: %v", profile["username"])
	}
	t.Log("✅ 获取用户信息成功")

	// 4. 注册时自动创建了默认清单
	status, body = apiRequest(t, "GET", baseURL+"/api/lists", token, nil)
	var lists []map[string]interface{}
	json.Unmarshal(body, &lists)
	if len(lists) != 3 {
		t.Errorf("默认清单数: %d, 期望 3", len(lists))
	}
	t.Logf("✅ 默认清单 %d 个", len(lists))
}

// ==========================================
// 集成测试 2: 任务完整工作流
// ==========================================

func TestIntegration_TaskWorkflow(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL
	token := registerAndLogin(t, baseURL, uniqueName("taskflow"))

	// 1. 获取默认清单
	status, body := apiRequest(t, "GET", baseURL+"/api/lists", token, nil)
	var lists []map[string]interface{}
	json.Unmarshal(body, &lists)
	listID := uint(lists[0]["id"].(float64))
	t.Logf("✅ 使用清单: %v (ID=%d)", lists[0]["name"], listID)

	// 2. 创建任务
	taskBody := map[string]interface{}{
		"list_id":  listID,
		"title":    "集成测试任务",
		"priority": "high",
	}
	status, body = apiRequest(t, "POST", baseURL+"/api/tasks", token, taskBody)
	if status != http.StatusCreated {
		t.Fatalf("创建任务失败: %d %s", status, string(body))
	}
	var task map[string]interface{}
	json.Unmarshal(body, &task)
	taskID := uint(task["id"].(float64))
	t.Logf("✅ 创建任务: %v (ID=%d)", task["title"], taskID)

	// 3. 添加子任务
	subBody := map[string]interface{}{"title": "子任务1"}
	status, body = apiRequest(t, "POST", fmt.Sprintf("%s/api/tasks/%d/subtasks", baseURL, taskID), token, subBody)
	if status != http.StatusCreated {
		t.Fatalf("创建子任务失败: %d", status)
	}
	var subtask map[string]interface{}
	json.Unmarshal(body, &subtask)
	subtaskID := uint(subtask["id"].(float64))
	t.Log("✅ 添加子任务成功")

	// 4. 完成子任务
	status, _ = apiRequest(t, "PATCH", fmt.Sprintf("%s/api/tasks/%d/subtasks/%d/toggle", baseURL, taskID, subtaskID), token, nil)
	if status != http.StatusOK {
		t.Fatalf("切换子任务失败: %d", status)
	}
	t.Log("✅ 完成子任务")

	// 5. 完成主任务
	status, body = apiRequest(t, "PATCH", fmt.Sprintf("%s/api/tasks/%d/complete", baseURL, taskID), token, nil)
	if status != http.StatusOK {
		t.Fatalf("完成任务失败: %d", status)
	}
	var completedTask map[string]interface{}
	json.Unmarshal(body, &completedTask)
	if completedTask["is_completed"] != true {
		t.Error("任务应标记为已完成")
	}
	t.Log("✅ 完成主任务")

	// 6. 查看统计
	status, body = apiRequest(t, "GET", baseURL+"/api/tasks/stats", token, nil)
	var stats map[string]interface{}
	json.Unmarshal(body, &stats)
	if stats["total"].(float64) != 1 {
		t.Errorf("total = %v, 期望 1", stats["total"])
	}
	if stats["completed"].(float64) != 1 {
		t.Errorf("completed = %v, 期望 1", stats["completed"])
	}
	t.Logf("✅ 统计: total=%v completed=%v rate=%v%%", stats["total"], stats["completed"], stats["rate"])
}

// ==========================================
// 集成测试 3: 任务 + 标签工作流
// ==========================================

func Integration_TaskWithTag(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL
	token := registerAndLogin(t, baseURL, uniqueName("tagflow"))

	// 1. 获取默认清单
	status, body := apiRequest(t, "GET", baseURL+"/api/lists", token, nil)
	var lists []map[string]interface{}
	json.Unmarshal(body, &lists)
	listID := uint(lists[0]["id"].(float64))

	// 2. 创建标签
	tagBody := map[string]interface{}{
		"name":  "紧急",
		"color": "#ff0000",
	}
	status, body = apiRequest(t, "POST", baseURL+"/api/tags", token, tagBody)
	if status != http.StatusCreated {
		t.Fatalf("创建标签失败: %d %s", status, string(body))
	}
	var tag map[string]interface{}
	json.Unmarshal(body, &tag)
	tagID := uint(tag["id"].(float64))
	t.Logf("✅ 创建标签: %v (ID=%d)", tag["name"], tagID)

	// 3. 创建任务并关联标签（通过 tag_ids）
	taskBody := map[string]interface{}{
		"list_id":  listID,
		"title":    "带标签的任务",
		"priority": "high",
		"tag_ids":  []uint{tagID},
	}
	status, body = apiRequest(t, "POST", baseURL+"/api/tasks", token, taskBody)
	if status != http.StatusCreated {
		t.Fatalf("创建任务失败: %d", status)
	}
	var task map[string]interface{}
	json.Unmarshal(body, &task)

	// 验证任务包含标签
	tags := task["tags"].([]interface{})
	if len(tags) != 1 {
		t.Errorf("标签数: %d, 期望 1", len(tags))
	}
	t.Log("✅ 任务关联标签成功")

	// 4. 查询标签下任务
	status, body = apiRequest(t, "GET", fmt.Sprintf("%s/api/tags/%d/tasks", baseURL, tagID), token, nil)
	if status != http.StatusOK {
		t.Fatalf("查询标签任务失败: %d", status)
	}
	t.Log("✅ 查询标签下任务成功")
}

// ==========================================
// 集成测试 4: 番茄钟完整流程
// ==========================================

func TestIntegration_PomodoroWorkflow(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL
	token := registerAndLogin(t, baseURL, uniqueName("pomodoro"))

	// 1. 开始工作会话
	sessionBody := map[string]interface{}{
		"session_type": "work",
		"device":       "web",
	}
	status, body := apiRequest(t, "POST", baseURL+"/api/sessions/start", token, sessionBody)
	if status != http.StatusOK {
		t.Fatalf("开始会话失败: %d", status)
	}
	t.Log("✅ 开始工作会话")

	// 2. 查询活跃会话
	status, body = apiRequest(t, "GET", baseURL+"/api/sessions/active", token, nil)
	var activeResp map[string]interface{}
	json.Unmarshal(body, &activeResp)
	if activeResp["active"] != true {
		t.Error("应有活跃会话")
	}
	t.Log("✅ 查询活跃会话成功")

	// 3. 结束会话
	status, body = apiRequest(t, "POST", baseURL+"/api/sessions/end", token, nil)
	if status != http.StatusOK {
		t.Fatalf("结束会话失败: %d", status)
	}
	var endResp map[string]interface{}
	json.Unmarshal(body, &endResp)
	if endResp["duration"].(float64) < 0 {
		t.Error("duration 不应为负数")
	}
	t.Logf("✅ 结束会话, duration=%v秒", endResp["duration"])

	// 4. 再次查询活跃会话（应无）
	status, body = apiRequest(t, "GET", baseURL+"/api/sessions/active", token, nil)
	json.Unmarshal(body, &activeResp)
	if activeResp["active"] != false {
		t.Error("不应有活跃会话")
	}
	t.Log("✅ 确认无活跃会话")
}

// ==========================================
// 集成测试 5: 习惯打卡完整流程
// ==========================================

func TestIntegration_HabitWorkflow(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL
	token := registerAndLogin(t, baseURL, uniqueName("habitflow"))

	// 1. 创建习惯
	habitBody := map[string]interface{}{
		"name":      "早起",
		"icon":      "🌅",
		"frequency": "daily",
	}
	status, body := apiRequest(t, "POST", baseURL+"/api/habits", token, habitBody)
	if status != http.StatusCreated {
		t.Fatalf("创建习惯失败: %d %s", status, string(body))
	}
	var habit map[string]interface{}
	json.Unmarshal(body, &habit)
	habitID := uint(habit["id"].(float64))
	t.Logf("✅ 创建习惯: %v (ID=%d)", habit["name"], habitID)

	// 2. 打卡
	checkinBody := map[string]interface{}{
		"note": "今天6点起床",
	}
	status, body = apiRequest(t, "POST", fmt.Sprintf("%s/api/habits/%d/checkin", baseURL, habitID), token, checkinBody)
	if status != http.StatusOK {
		t.Fatalf("打卡失败: %d %s", status, string(body))
	}
	var checkinResp map[string]interface{}
	json.Unmarshal(body, &checkinResp)
	if checkinResp["streak_count"].(float64) != 1 {
		t.Errorf("streak_count = %v, 期望 1", checkinResp["streak_count"])
	}
	t.Log("✅ 打卡成功, streak=1")

	// 3. 查看连续天数
	status, body = apiRequest(t, "GET", fmt.Sprintf("%s/api/habits/%d/streak", baseURL, habitID), token, nil)
	var streakResp map[string]interface{}
	json.Unmarshal(body, &streakResp)
	if streakResp["streak_count"].(float64) != 1 {
		t.Errorf("streak_count = %v, 期望 1", streakResp["streak_count"])
	}
	t.Log("✅ 连续天数查询成功")
}

// ==========================================
// 集成测试 6: 休息提醒完整流程
// ==========================================

func TestIntegration_ReminderWorkflow(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL
	token := registerAndLogin(t, baseURL, uniqueName("reminderflow"))

	// 1. 查看默认配置
	status, body := apiRequest(t, "GET", baseURL+"/api/reminder/config", token, nil)
	if status != http.StatusOK {
		t.Fatalf("获取配置失败: %d", status)
	}
	var config map[string]interface{}
	json.Unmarshal(body, &config)
	t.Logf("✅ 默认配置: work=%v rest=%v", config["work_minutes"], config["rest_minutes"])

	// 2. 修改配置
	saveBody := map[string]interface{}{
		"work_minutes": 25,
		"rest_minutes": 5,
		"enabled":      true,
	}
	status, _ = apiRequest(t, "POST", baseURL+"/api/reminder/config", token, saveBody)
	if status != http.StatusOK {
		t.Fatalf("保存配置失败: %d", status)
	}
	t.Log("✅ 配置已更新")

	// 3. 开始工作
	status, _ = apiRequest(t, "POST", baseURL+"/api/reminder/start-work", token, map[string]interface{}{"device": "web"})
	if status != http.StatusOK {
		t.Fatalf("开始工作失败: %d", status)
	}
	t.Log("✅ 开始工作阶段")

	// 4. 开始休息
	status, _ = apiRequest(t, "POST", baseURL+"/api/reminder/start-rest", token, nil)
	if status != http.StatusOK {
		t.Fatalf("开始休息失败: %d", status)
	}
	t.Log("✅ 开始休息阶段")

	// 5. 结束休息
	status, _ = apiRequest(t, "POST", baseURL+"/api/reminder/end-rest", token, nil)
	if status != http.StatusOK {
		t.Fatalf("结束休息失败: %d", status)
	}
	t.Log("✅ 结束休息阶段，完整工作流完成")
}

// ==========================================
// 集成测试 7: 用户隔离（多用户不互通）
// ==========================================

func TestIntegration_UserIsolation(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL

	tokenA := registerAndLogin(t, baseURL, uniqueName("userA"))
	tokenB := registerAndLogin(t, baseURL, uniqueName("userB"))

	// 用户 A 创建任务
	// 用户 A 获取默认清单
	_, listsABody := apiRequest(t, "GET", baseURL+"/api/lists", tokenA, nil)
	var lists []map[string]interface{}
	json.Unmarshal(listsABody, &lists)
	listID := uint(lists[0]["id"].(float64))

	taskBody := map[string]interface{}{
		"list_id": listID,
		"title":   "用户A的私密任务",
	}
	status, _ := apiRequest(t, "POST", baseURL+"/api/tasks", tokenA, taskBody)
	if status != http.StatusCreated {
		t.Fatalf("用户A创建任务失败: %d", status)
	}

	// 用户 B 查看任务列表（应为空）
	status, body := apiRequest(t, "GET", baseURL+"/api/tasks", tokenB, nil)
	var tasksB []map[string]interface{}
	json.Unmarshal(body, &tasksB)
	if len(tasksB) != 0 {
		t.Errorf("用户B不应看到用户A的任务, 实际 %d 个", len(tasksB))
	}
	t.Log("✅ 用户隔离: 用户B看不到用户A的任务")

	// 用户 A 查看（应有 1 个任务）
	status, body = apiRequest(t, "GET", baseURL+"/api/tasks", tokenA, nil)
	var tasksA []map[string]interface{}
	json.Unmarshal(body, &tasksA)
	if len(tasksA) != 1 {
		t.Errorf("用户A应有 1 个任务, 实际 %d 个", len(tasksA))
	}
	t.Log("✅ 用户A能看到自己的任务")
}

// ==========================================
// 集成测试 8: 无 Token 访问被拒绝
// ==========================================

func TestIntegration_AuthRequired(t *testing.T) {
	server, _ := setupIntegrationServer(t)
	defer server.Close()
	baseURL := server.URL

	endpoints := []struct {
		method string
		path   string
	}{
		{"GET", "/api/tasks"},
		{"POST", "/api/tasks"},
		{"GET", "/api/lists"},
		{"GET", "/api/auth/profile"},
		{"GET", "/api/tags"},
		{"GET", "/api/sessions/active"},
	}

	for _, ep := range endpoints {
		status, _ := apiRequest(t, ep.method, baseURL+ep.path, "", nil)
		if status != http.StatusUnauthorized {
			t.Errorf("%s %s: 无 token 应返回 401, 实际 %d", ep.method, ep.path, status)
		}
	}
	t.Logf("✅ %d 个端点均正确拒绝无 token 请求", len(endpoints))
}
