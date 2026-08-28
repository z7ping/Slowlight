package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"slowlight/internal/model"
)

func setupListTest(t *testing.T) (*ListHandler, uint) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	return handler, user.ID
}

func newListRouter(h *ListHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) {
		withUser(c, userID)
		c.Next()
	})
	r.GET("/lists", h.GetLists)
	r.POST("/lists", h.CreateList)
	r.PUT("/lists/:id", h.UpdateList)
	r.DELETE("/lists/:id", h.DeleteList)
	return r
}

func TestCreateList(t *testing.T) {
	handler, userID := setupListTest(t)
	r := newListRouter(handler, userID)

	body := map[string]interface{}{
		"name":  "项目",
		"icon":  "📁",
		"color": "#ff6600",
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/lists", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("CreateList 返回 %d, 期望 201. Body: %s", w.Code, w.Body.String())
	}

	var list model.List
	json.Unmarshal(w.Body.Bytes(), &list)

	assertEqual(t, list.Name, "项目", "Name")
	assertEqual(t, list.Icon, "📁", "Icon")
	assertEqual(t, list.Color, "#ff6600", "Color")
}

func TestCreateList_InvalidJSON(t *testing.T) {
	handler, userID := setupListTest(t)
	r := newListRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/lists", bytes.NewBufferString("bad"))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("返回 %d, 期望 400", w.Code)
	}
}

func TestGetLists(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)

	// 注册默认会创建 3 个清单，但这里用测试数据
	createTestList(t, tx, user.ID, "工作")
	createTestList(t, tx, user.ID, "生活")

	r := newListRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/lists", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetLists 返回 %d, 期望 200", w.Code)
	}

	var lists []model.List
	json.Unmarshal(w.Body.Bytes(), &lists)

	if len(lists) != 2 {
		t.Errorf("返回 %d 个清单, 期望 2", len(lists))
	}
}

func TestUpdateList(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "旧名称")

	r := newListRouter(handler, user.ID)

	body := map[string]interface{}{"name": "新名称", "color": "#00ff00"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/lists/"+itoa(list.ID), bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("UpdateList 返回 %d, 期望 200", w.Code)
	}

	var result model.List
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result.Name, "新名称", "Name")
	assertEqual(t, result.Color, "#00ff00", "Color")
}

func TestUpdateList_NotFound(t *testing.T) {
	handler, userID := setupListTest(t)
	r := newListRouter(handler, userID)

	body := map[string]interface{}{"name": "测试"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/lists/99999", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestDeleteList(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "待删除")

	r := newListRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/lists/"+itoa(list.ID), nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("DeleteList 返回 %d, 期望 200. Body: %s", w.Code, w.Body.String())
	}
}

func TestDeleteList_HasTasks(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "有任务")
	createTestTask(t, tx, user.ID, list.ID, "清单内任务")

	r := newListRouter(handler, user.ID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/lists/"+itoa(list.ID), nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("有任务的清单不应被删除, 返回 %d, 期望 400", w.Code)
	}
}

func TestDeleteList_NotFound(t *testing.T) {
	handler, userID := setupListTest(t)
	r := newListRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/lists/99999", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestGetListStats_Empty(t *testing.T) {
	handler, userID := setupListTest(t)
	// 不创建任何清单，直接查询统计
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.GET("/lists/stats", handler.GetStats)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/lists/stats", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetListStats 返回 %d, 期望 200", w.Code)
	}

	var stats []struct {
		ListID    uint    `json:"list_id"`
		ListName  string  `json:"list_name"`
		Color     string  `json:"color"`
		Total     int64   `json:"total"`
		Completed int64   `json:"completed"`
		Rate      float64 `json:"rate"`
	}
	json.Unmarshal(w.Body.Bytes(), &stats)

	if len(stats) != 0 {
		t.Errorf("无清单时应返回空数组, 实际 %d 条", len(stats))
	}
}

func TestGetListStats_WithTasks(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)

	list1 := createTestList(t, tx, user.ID, "工作")
	list2 := createTestList(t, tx, user.ID, "生活")

	// list1: 2 tasks, 1 completed
	t1 := createTestTask(t, tx, user.ID, list1.ID, "任务A1")
	createTestTask(t, tx, user.ID, list1.ID, "任务A2")
	tx.Model(&t1).Update("is_completed", true)

	// list2: 1 task, 0 completed
	createTestTask(t, tx, user.ID, list2.ID, "任务B1")

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.GET("/lists/stats", handler.GetStats)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/lists/stats", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetListStats 返回 %d, 期望 200. Body: %s", w.Code, w.Body.String())
	}

	var stats []struct {
		ListID    uint    `json:"list_id"`
		ListName  string  `json:"list_name"`
		Total     int64   `json:"total"`
		Completed int64   `json:"completed"`
		Rate      float64 `json:"rate"`
	}
	json.Unmarshal(w.Body.Bytes(), &stats)

	if len(stats) != 2 {
		t.Fatalf("返回 %d 条统计, 期望 2", len(stats))
	}

	// 按 list_id 匹配，避免依赖返回顺序
	var s1, s2 struct {
		ListID    uint    `json:"list_id"`
		ListName  string  `json:"list_name"`
		Total     int64   `json:"total"`
		Completed int64   `json:"completed"`
		Rate      float64 `json:"rate"`
	}
	for _, s := range stats {
		if s.ListID == list1.ID {
			s1 = s
		} else if s.ListID == list2.ID {
			s2 = s
		}
	}

	assertEqual(t, s1.Total, int64(2), "list1 total")
	assertEqual(t, s1.Completed, int64(1), "list1 completed")
	assertEqual(t, s1.Rate, float64(50), "list1 rate")
	assertEqual(t, s1.ListName, "工作", "list1 name")

	assertEqual(t, s2.Total, int64(1), "list2 total")
	assertEqual(t, s2.Completed, int64(0), "list2 completed")
	assertEqual(t, s2.ListName, "生活", "list2 name")
}

func TestGetListStats_EmptyList(t *testing.T) {
	tx := setupTestDB(t)
	tx = beginTx(t, tx)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)

	// 创建清单但不创建任务
	createTestList(t, tx, user.ID, "空清单")

	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.GET("/lists/stats", handler.GetStats)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/lists/stats", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetListStats 返回 %d, 期望 200", w.Code)
	}

	var stats []struct {
		Total     int64   `json:"total"`
		Completed int64   `json:"completed"`
		Rate      float64 `json:"rate"`
	}
	json.Unmarshal(w.Body.Bytes(), &stats)

	if len(stats) != 1 {
		t.Fatalf("返回 %d 条统计, 期望 1", len(stats))
	}
	assertEqual(t, stats[0].Total, int64(0), "empty list total")
	assertEqual(t, stats[0].Completed, int64(0), "empty list completed")
	assertEqual(t, stats[0].Rate, float64(0), "empty list rate")
}
