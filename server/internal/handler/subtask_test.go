package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"slowlight/internal/model"
)

func setupSubtaskTest(t *testing.T) (*gorm.DB, *SubtaskHandler, model.User, model.Task) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewSubtaskHandler(tx)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "测试清单")
	task := createTestTask(t, tx, user.ID, list.ID, "父任务")
	return tx, handler, user, task
}

func newSubtaskRouter(h *SubtaskHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.POST("/tasks/:id/subtasks", h.CreateSubtask)
	r.GET("/tasks/:id/subtasks", h.GetSubtasks)
	r.PUT("/tasks/:id/subtasks/:subtaskId", h.UpdateSubtask)
	r.DELETE("/tasks/:id/subtasks/:subtaskId", h.DeleteSubtask)
	r.PATCH("/tasks/:id/subtasks/:subtaskId/complete", h.ToggleSubtask)
	r.GET("/tasks/:id/subtasks/progress", h.GetSubtaskProgress)
	return r
}

func TestGetSubtaskProgress_RejectsForeignTask(t *testing.T) {
	db, handler, user, _ := setupSubtaskTest(t)
	other := createTestUser(t, db)
	list := createTestList(t, db, other.ID, "其他用户清单")
	task := createTestTask(t, db, other.ID, list.ID, "其他用户任务")
	r := newSubtaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/"+itoa(task.ID)+"/subtasks/progress", nil)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("返回 %d, 期望 404. Body: %s", w.Code, w.Body.String())
	}
}

func TestCreateSubtask(t *testing.T) {
	_, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	body := map[string]interface{}{"title": "子任务1"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/tasks/"+itoa(task.ID)+"/subtasks", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("CreateSubtask 返回 %d, 期望 201. Body: %s", w.Code, w.Body.String())
	}

	var subtask model.Subtask
	json.Unmarshal(w.Body.Bytes(), &subtask)

	assertEqual(t, subtask.Title, "子任务1", "Title")
	assertEqual(t, subtask.TaskID, task.ID, "TaskID")
}

func TestGetSubtasks(t *testing.T) {
	db, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	db.Create(&model.Subtask{TaskID: task.ID, Title: "子1"})
	db.Create(&model.Subtask{TaskID: task.ID, Title: "子2"})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/"+itoa(task.ID)+"/subtasks", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetSubtasks 返回 %d", w.Code)
	}

	var subs []model.Subtask
	json.Unmarshal(w.Body.Bytes(), &subs)

	if len(subs) != 2 {
		t.Errorf("返回 %d 个子任务, 期望 2", len(subs))
	}
}

func TestToggleSubtask(t *testing.T) {
	db, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	sub := model.Subtask{TaskID: task.ID, Title: "待切换"}
	db.Create(&sub)

	// 完成
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/subtasks/"+itoa(sub.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("ToggleSubtask 返回 %d", w.Code)
	}

	var result model.Subtask
	json.Unmarshal(w.Body.Bytes(), &result)
	if !result.IsCompleted {
		t.Error("子任务应标记为已完成")
	}

	// 再次切换回未完成
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("PATCH", "/tasks/"+itoa(task.ID)+"/subtasks/"+itoa(sub.ID)+"/complete", nil)
	r.ServeHTTP(w, req)

	json.Unmarshal(w.Body.Bytes(), &result)
	if result.IsCompleted {
		t.Error("子任务应标记为未完成")
	}
}

func TestDeleteSubtask(t *testing.T) {
	db, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	sub := model.Subtask{TaskID: task.ID, Title: "待删"}
	db.Create(&sub)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/tasks/"+itoa(task.ID)+"/subtasks/"+itoa(sub.ID), nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("DeleteSubtask 返回 %d", w.Code)
	}

	var count int64
	db.Model(&model.Subtask{}).Where("id = ?", sub.ID).Count(&count)
	if count != 0 {
		t.Error("子任务未被删除")
	}
}

func TestDeleteSubtask_NotFound(t *testing.T) {
	db, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/tasks/"+itoa(task.ID)+"/subtasks/99999", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
	_ = db
}

func TestCreateSubtask_InvalidJSON(t *testing.T) {
	_, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/tasks/"+itoa(task.ID)+"/subtasks", bytes.NewBufferString("not json"))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("无效 JSON 应返回 400, 实际 %d", w.Code)
	}
}

func TestUpdateSubtask_NotFound(t *testing.T) {
	_, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	body := map[string]interface{}{"title": "不存在"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/tasks/"+itoa(task.ID)+"/subtasks/99999", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("更新不存在的子任务应返回 404, 实际 %d", w.Code)
	}
}

func TestUpdateSubtask(t *testing.T) {
	db, handler, user, task := setupSubtaskTest(t)
	r := newSubtaskRouter(handler, user.ID)

	sub := model.Subtask{TaskID: task.ID, Title: "旧标题"}
	db.Create(&sub)

	body := map[string]interface{}{"title": "新标题"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/tasks/"+itoa(task.ID)+"/subtasks/"+itoa(sub.ID), bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("UpdateSubtask 返回 %d", w.Code)
	}

	var result model.Subtask
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result.Title, "新标题", "Title")
}

// helper: require handler files to compile
var _ = (*SubtaskHandler)(nil)

func TestGetSubtaskProgress_Empty(t *testing.T) {
	_, handler, user, task := setupSubtaskTest(t)

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.GET("/tasks/:id/subtasks/progress", handler.GetSubtaskProgress)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/"+itoa(task.ID)+"/subtasks/progress", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetSubtaskProgress 返回 %d, 期望 200. Body: %s", w.Code, w.Body.String())
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	if result["total"].(float64) != 0 {
		t.Errorf("total = %v, 期望 0", result["total"])
	}
	if result["completed"].(float64) != 0 {
		t.Errorf("completed = %v, 期望 0", result["completed"])
	}
}

func TestGetSubtaskProgress_PartialComplete(t *testing.T) {
	db, handler, user, task := setupSubtaskTest(t)

	db.Create(&model.Subtask{TaskID: task.ID, Title: "已完成1", IsCompleted: true})
	db.Create(&model.Subtask{TaskID: task.ID, Title: "已完成2", IsCompleted: true})
	db.Create(&model.Subtask{TaskID: task.ID, Title: "未完成1"})

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.GET("/tasks/:id/subtasks/progress", handler.GetSubtaskProgress)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/"+itoa(task.ID)+"/subtasks/progress", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetSubtaskProgress 返回 %d, 期望 200", w.Code)
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	assertEqual(t, int(result["total"].(float64)), 3, "total")
	assertEqual(t, int(result["completed"].(float64)), 2, "completed")
}

func TestGetSubtaskProgress_AllComplete(t *testing.T) {
	db, handler, user, task := setupSubtaskTest(t)

	db.Create(&model.Subtask{TaskID: task.ID, Title: "子1", IsCompleted: true})
	db.Create(&model.Subtask{TaskID: task.ID, Title: "子2", IsCompleted: true})

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.GET("/tasks/:id/subtasks/progress", handler.GetSubtaskProgress)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/"+itoa(task.ID)+"/subtasks/progress", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetSubtaskProgress 返回 %d, 期望 200", w.Code)
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	assertEqual(t, int(result["total"].(float64)), 2, "total")
	assertEqual(t, int(result["completed"].(float64)), 2, "completed")
}

func TestGetSubtaskProgress_NonExistentTask(t *testing.T) {
	_, handler, user, _ := setupSubtaskTest(t)

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.GET("/tasks/:id/subtasks/progress", handler.GetSubtaskProgress)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/tasks/99999/subtasks/progress", nil)
	r.ServeHTTP(w, req)

	// 与其他子任务接口保持一致：不存在或无权访问的父任务不暴露进度信息。
	if w.Code != http.StatusNotFound {
		t.Fatalf("GetSubtaskProgress 返回 %d, 期望 404", w.Code)
	}
}
