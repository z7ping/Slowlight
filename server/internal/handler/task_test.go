package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

// setupTaskTest 创建 task 测试所需的 handler、DB（事务隔离）、用户、清单
func setupTaskTest(t *testing.T) (*gorm.DB, *TaskHandler, model.User, model.List) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewTaskHandler(tx)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "工作")
	return tx, handler, user, list
}

// newTaskRouter 创建带路由的 Gin 引擎，注入 userID
func newTaskRouter(h *TaskHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) {
		withUser(c, userID)
		c.Next()
	})
	r.POST("/tasks", h.CreateTask)
	r.GET("/tasks", h.GetTasks)
	r.GET("/tasks/:id", h.GetTask)
	r.PUT("/tasks/:id", h.UpdateTask)
	r.DELETE("/tasks/:id", h.DeleteTask)
	r.PATCH("/tasks/:id/complete", h.CompleteTask)
	r.GET("/tasks/search", h.SearchTasks)
	r.GET("/tasks/today", h.GetTodayTasks)
	r.GET("/tasks/completed", h.GetCompletedTasks)
	r.GET("/tasks/stats", h.GetStats)
	return r
}

func TestCreateTask(t *testing.T) {
	_, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	body := map[string]interface{}{
		"list_id":  list.ID,
		"title":    "写单元测试",
		"priority": "high",
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/tasks", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("CreateTask 返回 %d, 期望 201. Body: %s", w.Code, w.Body.String())
	}

	var task model.Task
	if err := json.Unmarshal(w.Body.Bytes(), &task); err != nil {
		t.Fatalf("解析响应失败: %v", err)
	}

	assertEqual(t, task.Title, "写单元测试", "Title")
	assertEqual(t, task.Priority, "high", "Priority")
	assertEqual(t, task.UserID, user.ID, "UserID")
	assertEqual(t, task.ListID, list.ID, "ListID")
}

func TestCreateTask_InvalidJSON(t *testing.T) {
	_, handler, user, _ := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/tasks", bytes.NewBufferString("invalid json"))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("返回 %d, 期望 400", w.Code)
	}
}

func TestCreateTask_MissingTitle(t *testing.T) {
	_, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	body := map[string]interface{}{"list_id": list.ID}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/tasks", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("空标题返回 %d, 期望 400. Body: %s", w.Code, w.Body.String())
	}
}

func TestCreateTask_RejectsForeignReferences(t *testing.T) {
	db, handler, user, _ := setupTaskTest(t)
	other := createTestUser(t, db)
	otherList := createTestList(t, db, other.ID, "其他用户清单")
	userList := createTestList(t, db, user.ID, "当前用户清单")
	otherTag := model.Tag{UserID: other.ID, Name: "其他用户标签", Color: "#000000"}
	db.Create(&otherTag)
	r := newTaskRouter(handler, user.ID)

	for name, body := range map[string]map[string]interface{}{
		"foreign list": {"list_id": otherList.ID, "title": "越权任务"},
		"foreign tag":  {"list_id": userList.ID, "title": "越权任务", "tag_ids": []uint{otherTag.ID}},
	} {
		t.Run(name, func(t *testing.T) {
			jsonBody, _ := json.Marshal(body)
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("POST", "/tasks", bytes.NewBuffer(jsonBody))
			req.Header.Set("Content-Type", "application/json")
			r.ServeHTTP(w, req)
			if w.Code != http.StatusBadRequest {
				t.Fatalf("返回 %d, 期望 400. Body: %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestGetTasks(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	for i := 1; i <= 3; i++ {
		createTestTask(t, db, user.ID, list.ID, "任务"+strconv.Itoa(i))
	}

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetTasks 返回 %d, 期望 200", w.Code)
	}

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)

	if len(tasks) != 3 {
		t.Errorf("返回 %d 个任务, 期望 3", len(tasks))
	}
}

func TestGetTasks_FilterByList(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	list2 := createTestList(t, db, user.ID, "生活")
	createTestTask(t, db, user.ID, list.ID, "工作任务")
	createTestTask(t, db, user.ID, list2.ID, "生活任务")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks?list_id="+itoa(list.ID), nil)
	r.ServeHTTP(w, req)

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)

	if len(tasks) != 1 {
		t.Errorf("按清单筛选返回 %d 个任务, 期望 1", len(tasks))
	}
	if len(tasks) > 0 && tasks[0].Title != "工作任务" {
		t.Errorf("Title = %q, 期望 %q", tasks[0].Title, "工作任务")
	}
}

func TestGetTasks_FilterByCompleted(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	t1 := createTestTask(t, db, user.ID, list.ID, "已完成")
	createTestTask(t, db, user.ID, list.ID, "未完成")
	db.Model(&t1).Update("is_completed", true)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks?is_completed=true", nil)
	r.ServeHTTP(w, req)

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)

	if len(tasks) != 1 {
		t.Errorf("筛选已完成任务返回 %d 个, 期望 1", len(tasks))
	}
}

func TestGetTask(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := createTestTask(t, db, user.ID, list.ID, "查看详情")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/"+itoa(task.ID), nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetTask 返回 %d, 期望 200", w.Code)
	}

	var result model.Task
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result.Title, "查看详情", "Title")
}

func TestGetTask_NotFound(t *testing.T) {
	_, handler, user, _ := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/99999", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestGetTask_OtherUser(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)

	user2 := createTestUser(t, db)
	task := createTestTask(t, db, user2.ID, list.ID, "别人的任务")

	r := newTaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/"+itoa(task.ID), nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("用户A不应看到用户B的任务, 返回 %d, 期望 404", w.Code)
	}
}

func TestUpdateTask(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := createTestTask(t, db, user.ID, list.ID, "原始标题")

	body := map[string]interface{}{"title": "更新后的标题", "priority": "low"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/tasks/"+itoa(task.ID), bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("UpdateTask 返回 %d, 期望 200. Body: %s", w.Code, w.Body.String())
	}

	var result model.Task
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result.Title, "更新后的标题", "Title")
	assertEqual(t, result.Priority, "low", "Priority")
}

func TestUpdateTask_NotFound(t *testing.T) {
	_, handler, user, _ := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	body := map[string]interface{}{"title": "测试"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/tasks/99999", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestUpdateTask_WithTags(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := createTestTask(t, db, user.ID, list.ID, "带标签")

	// 创建标签
	tag := model.Tag{UserID: user.ID, Name: "重要", Color: "#ff0000"}
	db.Create(&tag)

	body := map[string]interface{}{
		"title":   "更新标签",
		"tag_ids": []uint{tag.ID},
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/tasks/"+itoa(task.ID), bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d, 期望 200", w.Code)
	}

	var result model.Task
	json.Unmarshal(w.Body.Bytes(), &result)
	if len(result.Tags) != 1 {
		t.Errorf("期望 1 个标签, 实际 %d", len(result.Tags))
	}
}

func TestUpdateTask_CanClearZeroAndNullableFields(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	dueTime := "09:30"
	systemTag := model.SystemTag{UserID: user.ID, Name: "专注", Color: "#000000"}
	db.Create(&systemTag)
	task := createTestTask(t, db, user.ID, list.ID, "待清空字段")
	db.Model(&task).Updates(map[string]interface{}{
		"description": "原描述", "due_time": dueTime, "is_completed": true,
		"sort_order": 9, "mood_before": 5, "is_milestone": true,
		"system_tag_id": systemTag.ID,
	})

	body := []byte(`{"description":"","due_time":null,"is_completed":false,"sort_order":0,"mood_before":0,"is_milestone":false,"system_tag_id":null}`)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/tasks/"+itoa(task.ID), bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("返回 %d, 期望 200: %s", w.Code, w.Body.String())
	}

	var stored model.Task
	db.First(&stored, task.ID)
	if stored.Description != "" || stored.DueTime != nil || stored.IsCompleted || stored.SortOrder != 0 || stored.MoodBefore != 0 || stored.IsMilestone || stored.SystemTagID != nil {
		t.Fatalf("零值或空值未正确保存: %+v", stored)
	}
}

func TestDeleteTask(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := createTestTask(t, db, user.ID, list.ID, "待删除")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/tasks/"+itoa(task.ID), nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("DeleteTask 返回 %d, 期望 200", w.Code)
	}

	var count int64
	db.Model(&model.Task{}).Where("id = ?", task.ID).Count(&count)
	if count != 0 {
		t.Error("任务未被删除")
	}
}

func TestDeleteTask_NotFound(t *testing.T) {
	_, handler, user, _ := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/tasks/99999", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestCompleteTask(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := createTestTask(t, db, user.ID, list.ID, "待完成")

	// 完成
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d, 期望 200", w.Code)
	}

	var result model.Task
	json.Unmarshal(w.Body.Bytes(), &result)
	if !result.IsCompleted {
		t.Error("任务应标记为已完成")
	}
	if result.CompletedAt == nil {
		t.Error("CompletedAt 不应为 nil")
	}

	// 取消完成
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	json.Unmarshal(w.Body.Bytes(), &result)
	if result.IsCompleted {
		t.Error("任务应标记为未完成")
	}
	if result.CompletedAt != nil {
		t.Error("取消完成后 CompletedAt 应为 nil")
	}
}

func TestCompleteTask_NotFound(t *testing.T) {
	_, handler, user, _ := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/99999/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestCompleteTask_RepeatDaily(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "每日打卡",
		RepeatType:     "daily",
		RepeatInterval: 1,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var count int64
	db.Model(&model.Task{}).Where("title = ? AND user_id = ?", "每日打卡", user.ID).Count(&count)
	if count != 2 {
		t.Errorf("期望 2 个重复任务(原+新), 实际 %d", count)
	}
}

func TestSearchTasks(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	createTestTask(t, db, user.ID, list.ID, "学习Go语言")
	createTestTask(t, db, user.ID, list.ID, "写Python脚本")
	createTestTask(t, db, user.ID, list.ID, "Go项目重构")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/search?q=Go", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("SearchTasks 返回 %d, 期望 200", w.Code)
	}

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)

	if len(tasks) != 2 {
		t.Errorf("搜索 'Go' 返回 %d 个结果, 期望 2", len(tasks))
	}
}

func TestSearchTasks_EmptyQuery(t *testing.T) {
	_, handler, user, _ := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/search?q=", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("返回 %d, 期望 200", w.Code)
	}

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)
	if len(tasks) != 0 {
		t.Errorf("空搜索应返回空数组, 实际 %d 个", len(tasks))
	}
}

func TestGetTodayTasks(t *testing.T) {
	_, handler, user, _ := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	// GetTodayTasks 会查 due_date，空数据库直接返回空即可
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/today", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("返回 %d, 期望 200", w.Code)
	}
}

func TestGetCompletedTasks(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	t1 := createTestTask(t, db, user.ID, list.ID, "已完成任务")
	createTestTask(t, db, user.ID, list.ID, "未完成任务")

	db.Model(&t1).Update("is_completed", true)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/completed", nil)
	r.ServeHTTP(w, req)

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)

	if len(tasks) != 1 {
		t.Errorf("返回 %d 个已完成任务, 期望 1", len(tasks))
	}
	if len(tasks) > 0 && tasks[0].ID != t1.ID {
		t.Error("返回了错误的已完成任务")
	}
}

func TestGetStats(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	t1 := createTestTask(t, db, user.ID, list.ID, "任务1")
	createTestTask(t, db, user.ID, list.ID, "任务2")
	createTestTask(t, db, user.ID, list.ID, "任务3")

	db.Model(&t1).Update("is_completed", true)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/stats", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetStats 返回 %d, 期望 200", w.Code)
	}

	var stats map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &stats)

	if stats["total"].(float64) != 3 {
		t.Errorf("total = %v, 期望 3", stats["total"])
	}
	if stats["completed"].(float64) != 1 {
		t.Errorf("completed = %v, 期望 1", stats["completed"])
	}
}

// helper: assertEqual
func assertEqual[T comparable](t *testing.T, got, want T, label string) {
	t.Helper()
	if got != want {
		t.Errorf("%s = %v, 期望 %v", label, got, want)
	}
}

// itoa: uint → string
func itoa(n uint) string {
	return strconv.FormatUint(uint64(n), 10)
}

func TestCompleteTask_RepeatWeekly(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "每周例会",
		RepeatType:     "weekly",
		RepeatInterval: 1,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var count int64
	db.Model(&model.Task{}).Where("title = ? AND user_id = ?", "每周例会", user.ID).Count(&count)
	if count != 2 {
		t.Errorf("期望 2 个重复任务(原+新), 实际 %d", count)
	}
}

func TestCompleteTask_RepeatMonthly(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "月度汇报",
		RepeatType:     "monthly",
		RepeatInterval: 1,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var count int64
	db.Model(&model.Task{}).Where("title = ? AND user_id = ?", "月度汇报", user.ID).Count(&count)
	if count != 2 {
		t.Errorf("期望 2 个重复任务(原+新), 实际 %d", count)
	}
}

func TestCompleteTask_RepeatDaily_WithDueDate(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	dueDate := model.FlexibleTime{Time: time.Now().AddDate(0, 0, 1), Valid: true}
	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "每日有截止日",
		RepeatType:     "daily",
		RepeatInterval: 2,
		DueDate:        &dueDate,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var newTask model.Task
	db.Where("title = ? AND user_id = ? AND id != ?", "每日有截止日", user.ID, task.ID).First(&newTask)
	if newTask.ID == 0 {
		t.Fatal("未创建下一个重复任务")
	}
	// 下一个 due_date 应该是原 due_date + 2 天
	expectedDate := dueDate.Time.AddDate(0, 0, 2).Format("2006-01-02")
	actualDate := newTask.DueDate.Time.Format("2006-01-02")
	if actualDate != expectedDate {
		t.Errorf("新任务 due_date = %s, 期望 %s", actualDate, expectedDate)
	}
}

func TestGetTasksByList(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)

	// 创建测试路由并添加路由
	r := newTaskRouter(handler, user.ID)
	r.GET("/lists/:id/tasks", handler.GetTasksByList)

	// 创建另一个清单
	list2 := createTestList(t, db, user.ID, "清单2")

	createTestTask(t, db, user.ID, list.ID, "任务A")
	createTestTask(t, db, user.ID, list.ID, "任务B")
	createTestTask(t, db, user.ID, list2.ID, "任务C")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/lists/"+itoa(list.ID)+"/tasks", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetTasksByList 返回 %d, 期望 200. Body: %s", w.Code, w.Body.String())
	}

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)

	if len(tasks) != 2 {
		t.Errorf("返回 %d 个任务, 期望 2", len(tasks))
	}

	for _, task := range tasks {
		if task.ListID != list.ID {
			t.Errorf("任务 ListID = %d, 期望 %d", task.ListID, list.ID)
		}
	}
}

func TestGetTasksByList_EmptyList(t *testing.T) {
	_, handler, user, list := setupTaskTest(t)

	r := newTaskRouter(handler, user.ID)
	r.GET("/lists/:id/tasks", handler.GetTasksByList)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/lists/"+itoa(list.ID)+"/tasks", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetTasksByList 返回 %d, 期望 200", w.Code)
	}

	var tasks []model.Task
	json.Unmarshal(w.Body.Bytes(), &tasks)

	if len(tasks) != 0 {
		t.Errorf("空清单应返回 0 个任务, 实际 %d", len(tasks))
	}
}

// --- nextWeekday 纯函数测试 (task.go line 314) ---

func TestNextWeekday_Monday(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，找下一个周一(1)
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "1", 1)

	// 周四之后最近的周一是 2026-04-20
	expected := time.Date(2026, 4, 20, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '1') = %s, 期望 %s", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

func TestNextWeekday_Wednesday(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，找下一个周三(3)
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "3", 1)

	// 周四之后最近的周三是 2026-04-22
	expected := time.Date(2026, 4, 22, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '3') = %s, 期望 %s", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

func TestNextWeekday_Friday(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，找下一个周五(5)
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "5", 1)

	// 周四之后最近的周五是 2026-04-17（明天）
	expected := time.Date(2026, 4, 17, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '5') = %s, 期望 %s", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

func TestNextWeekday_Sunday(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，找下一个周日(7)
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "7", 1)

	// 周四之后最近的周日是 2026-04-19
	expected := time.Date(2026, 4, 19, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '7') = %s, 期望 %s", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

func TestNextWeekday_Saturday(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，找下一个周六(6)
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "6", 1)

	// 周四之后最近的周六是 2026-04-18
	expected := time.Date(2026, 4, 18, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '6') = %s, 期望 %s", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

func TestNextWeekday_MultipleDays(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，repeat_days="1,3,5" 表示周一/三/五
	// 最近的应该是周五(5) = 2026-04-17
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "1,3,5", 1)

	expected := time.Date(2026, 4, 17, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '1,3,5') = %s, 期望 %s", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

func TestNextWeekday_Interval2(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，找周一(1)，interval=2
	// 搜索范围：1..14天内
	// 第一个周一在 2026-04-20（+4天）
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "1", 2)

	expected := time.Date(2026, 4, 20, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '1', interval=2) = %s, 期望 %s", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

func TestNextWeekday_SameDaySkipped(t *testing.T) {
	_, handler, _, _ := setupTaskTest(t)

	// 2026-04-16 是周四(weekday=4)，找周四(4)
	// 应该跳过当天，返回下一个周四 = 2026-04-23
	from := time.Date(2026, 4, 16, 0, 0, 0, 0, time.UTC)
	result := handler.nextWeekday(from, "4", 1)

	expected := time.Date(2026, 4, 23, 0, 0, 0, 0, time.UTC)
	if !result.Equal(expected) {
		t.Errorf("nextWeekday(周四, '4') = %s, 期望 %s (应跳过当天)", result.Format("2006-01-02"), expected.Format("2006-01-02"))
	}
}

// --- createNextRepeatTask 更多分支测试 ---

func TestCompleteTask_RepeatWeekly_WithRepeatDays(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	// 创建每周一/三/五重复的任务
	dueDate := model.FlexibleTime{Time: time.Now(), Valid: true}
	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "每周多次",
		RepeatType:     "weekly",
		RepeatInterval: 1,
		RepeatDays:     "1,3,5",
		DueDate:        &dueDate,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var newTask model.Task
	db.Where("title = ? AND user_id = ? AND id != ?", "每周多次", user.ID, task.ID).First(&newTask)
	if newTask.ID == 0 {
		t.Fatal("未创建下一个重复任务")
	}
	if newTask.RepeatDays != "1,3,5" {
		t.Errorf("新任务 RepeatDays = %q, 期望 '1,3,5'", newTask.RepeatDays)
	}
	if newTask.DueDate == nil || !newTask.DueDate.Valid {
		t.Fatal("新任务 DueDate 不应为 nil")
	}
}

func TestCompleteTask_RepeatDaily_Interval3(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	dueDate := model.FlexibleTime{Time: time.Now().AddDate(0, 0, 5), Valid: true}
	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "每3天",
		RepeatType:     "daily",
		RepeatInterval: 3,
		DueDate:        &dueDate,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var newTask model.Task
	db.Where("title = ? AND user_id = ? AND id != ?", "每3天", user.ID, task.ID).First(&newTask)
	if newTask.ID == 0 {
		t.Fatal("未创建下一个重复任务")
	}
	// 新任务的 due_date = 原 due_date + 3 天
	expectedDate := dueDate.Time.AddDate(0, 0, 3).Format("2006-01-02")
	actualDate := newTask.DueDate.Time.Format("2006-01-02")
	if actualDate != expectedDate {
		t.Errorf("新任务 due_date = %s, 期望 %s", actualDate, expectedDate)
	}
}

func TestCompleteTask_RepeatWeekly_Interval2(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	dueDate := model.FlexibleTime{Time: time.Now().AddDate(0, 0, 2), Valid: true}
	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "每2周",
		RepeatType:     "weekly",
		RepeatInterval: 2,
		DueDate:        &dueDate,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var newTask model.Task
	db.Where("title = ? AND user_id = ? AND id != ?", "每2周", user.ID, task.ID).First(&newTask)
	if newTask.ID == 0 {
		t.Fatal("未创建下一个重复任务")
	}
	// 新任务的 due_date = 原 due_date + 14 天
	expectedDate := dueDate.Time.AddDate(0, 0, 14).Format("2006-01-02")
	actualDate := newTask.DueDate.Time.Format("2006-01-02")
	if actualDate != expectedDate {
		t.Errorf("新任务 due_date = %s, 期望 %s", actualDate, expectedDate)
	}
}

func TestCompleteTask_RepeatMonthly_Interval3(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	dueDate := model.FlexibleTime{Time: time.Now().AddDate(0, 1, 0), Valid: true}
	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "每3月",
		RepeatType:     "monthly",
		RepeatInterval: 3,
		DueDate:        &dueDate,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var newTask model.Task
	db.Where("title = ? AND user_id = ? AND id != ?", "每3月", user.ID, task.ID).First(&newTask)
	if newTask.ID == 0 {
		t.Fatal("未创建下一个重复任务")
	}
	// 新任务的 due_date = 原 due_date + 3 个月
	expectedDate := dueDate.Time.AddDate(0, 3, 0).Format("2006-01-02")
	actualDate := newTask.DueDate.Time.Format("2006-01-02")
	if actualDate != expectedDate {
		t.Errorf("新任务 due_date = %s, 期望 %s", actualDate, expectedDate)
	}
}

// --- yearly 重复任务测试 ---

func TestCompleteTask_RepeatYearly_WithDueDate(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	dueDate := model.FlexibleTime{Time: time.Now().AddDate(0, 6, 0), Valid: true}
	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "年会",
		RepeatType:     "yearly",
		RepeatInterval: 1,
		DueDate:        &dueDate,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var newTask model.Task
	db.Where("title = ? AND user_id = ? AND id != ?", "年会", user.ID, task.ID).First(&newTask)
	if newTask.ID == 0 {
		t.Fatal("未创建下一个重复任务（yearly with DueDate）")
	}
	// 新任务的 due_date = 原 due_date + 1 年
	expectedDate := dueDate.Time.AddDate(1, 0, 0).Format("2006-01-02")
	actualDate := newTask.DueDate.Time.Format("2006-01-02")
	if actualDate != expectedDate {
		t.Errorf("新任务 due_date = %s, 期望 %s", actualDate, expectedDate)
	}
}

func TestCompleteTask_RepeatYearly_NoDueDate(t *testing.T) {
	db, handler, user, list := setupTaskTest(t)
	r := newTaskRouter(handler, user.ID)

	// yearly 重复但无 DueDate → 使用 now + interval
	task := model.Task{
		UserID:         user.ID,
		ListID:         list.ID,
		Title:          "年度总结",
		RepeatType:     "yearly",
		RepeatInterval: 2,
	}
	db.Create(&task)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CompleteTask 返回 %d", w.Code)
	}

	var newTask model.Task
	db.Where("title = ? AND user_id = ? AND id != ?", "年度总结", user.ID, task.ID).First(&newTask)
	if newTask.ID == 0 {
		t.Fatal("未创建下一个重复任务（yearly no DueDate）")
	}
	if newTask.RepeatType != "yearly" {
		t.Errorf("新任务 RepeatType = %q, 期望 'yearly'", newTask.RepeatType)
	}
	if newTask.RepeatInterval != 2 {
		t.Errorf("新任务 RepeatInterval = %d, 期望 2", newTask.RepeatInterval)
	}
}
