package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

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
	r.POST("/lists/undo", h.UndoListDelete)
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

	if len(lists) != 3 {
		t.Errorf("返回 %d 个清单, 期望包含补齐的收集箱在内 3 个", len(lists))
	}
	if len(lists) > 0 && (!lists[0].IsInbox || lists[0].Name != "收集箱") {
		t.Errorf("首位应为默认收集箱，实际 %+v", lists[0])
	}
	// 重复读取必须幂等，不能产生第二个收集箱。
	w = httptest.NewRecorder()
	r.ServeHTTP(w, req)
	var second []model.List
	if err := json.Unmarshal(w.Body.Bytes(), &second); err != nil {
		t.Fatal(err)
	}
	if len(second) != 3 {
		t.Errorf("重复读取新增了清单：%d", len(second))
	}
}

func TestGetLists_LegacySameNameIsPreserved(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	custom := createTestList(t, tx, user.ID, "收集箱")
	r := newListRouter(handler, user.ID)

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest("GET", "/lists", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("GetLists 返回 %d: %s", w.Code, w.Body.String())
	}
	var lists []model.List
	if err := json.Unmarshal(w.Body.Bytes(), &lists); err != nil {
		t.Fatal(err)
	}
	if len(lists) != 2 {
		t.Fatalf("已有同名清单应保留并补齐默认收集箱，实际 %d 个", len(lists))
	}
	var original, inbox *model.List
	for i := range lists {
		if lists[i].ID == custom.ID {
			original = &lists[i]
		}
		if lists[i].IsInbox {
			inbox = &lists[i]
		}
	}
	if original == nil || original.IsInbox {
		t.Fatal("原有同名普通清单不应被改写")
	}
	if inbox == nil || inbox.ID == original.ID {
		t.Fatal("应另建独立的默认收集箱")
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

func TestDeleteList_X08UndoRestoresOriginalListAndChildren(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "撤销清单")
	first := createTestTask(t, tx, user.ID, list.ID, "保留ID 1")
	second := createTestTask(t, tx, user.ID, list.ID, "保留ID 2")
	other := createTestList(t, tx, user.ID, "其他")
	otherTask := createTestTask(t, tx, user.ID, other.ID, "不受影响")
	r := newListRouter(NewListHandler(tx), user.ID)
	url := "/lists/" + itoa(list.ID) + "?delete_tasks=true&expected_tasks=2&undoable=true"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusOK { t.Fatalf("删除失败: %d %s", w.Code, w.Body.String()) }
	var result struct { UndoToken string `json:"undo_token"` }
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
	if len(result.UndoToken) != 32 { t.Fatal("没有可用的撤销凭据") }
	for _, id := range []uint{first.ID, second.ID} {
		if err := tx.First(&model.Task{}, id).Error; err == nil {
			t.Fatalf("删除后任务 %d 仍可见", id)
		}
	}
	data, _ := json.Marshal(map[string]string{"token": result.UndoToken})
	w = httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/lists/undo", bytes.NewReader(data))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK { t.Fatalf("撤销失败: %d %s", w.Code, w.Body.String()) }
	for _, id := range []uint{first.ID, second.ID, otherTask.ID} {
		var task model.Task
		if err := tx.First(&task, id).Error; err != nil { t.Fatalf("原任务ID未恢复 %d: %v", id, err) }
	}
	if err := tx.First(&model.List{}, list.ID).Error; err != nil { t.Fatal("原清单ID未恢复:", err) }
	w = httptest.NewRecorder()
	repeated := httptest.NewRequest(http.MethodPost, "/lists/undo", bytes.NewReader(data))
	repeated.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, repeated)
	if w.Code != http.StatusConflict { t.Fatalf("重复撤销应409: %d", w.Code) }
}

func TestDeleteList_X08UndoTokenCannotCrossAccounts(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	owner := createTestUser(t, tx)
	other := createTestUser(t, tx)
	list := createTestList(t, tx, owner.ID, "仅所有者恢复")
	router := newListRouter(NewListHandler(tx), owner.ID)
	w := httptest.NewRecorder()
	url := "/lists/" + itoa(list.ID) + "?delete_tasks=true&expected_tasks=0&undoable=true"
	router.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusOK { t.Fatalf("删除失败: %s", w.Body.String()) }
	var result struct { UndoToken string `json:"undo_token"` }
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
	body, _ := json.Marshal(map[string]string{"token": result.UndoToken})
	unauthorized := newListRouter(NewListHandler(tx), other.ID)
	w = httptest.NewRecorder()
	unauthorized.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/lists/undo",
		bytes.NewReader(body)))
	if w.Code != http.StatusConflict { t.Fatalf("跨用户撤销应拒绝: %d", w.Code) }
	if err := tx.First(&model.List{}, list.ID).Error; err == nil {
		t.Fatal("非本人恢复了清单")
	}
	w = httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/lists/undo",
		bytes.NewReader(body)))
	if w.Code != http.StatusOK { t.Fatalf("原用户应仍可恢复: %d", w.Code) }
}

func TestDeleteList_X08UndoCannotRestoreModifiedTombstone(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "过期状态")
	task := createTestTask(t, tx, user.ID, list.ID, "被改变的原任务")
	r := newListRouter(NewListHandler(tx), user.ID)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete,
		"/lists/"+itoa(list.ID)+"?delete_tasks=true&expected_tasks=1&undoable=true", nil))
	if w.Code != http.StatusOK { t.Fatalf("删除失败: %s", w.Body.String()) }
	var result struct { UndoToken string `json:"undo_token"` }
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
	if err := tx.Unscoped().Model(&model.Task{}).
		Where("id = ?", task.ID).Update("deleted_at", time.Now().UTC().Add(-time.Hour)).Error; err != nil {
		t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]string{"token": result.UndoToken})
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/lists/undo", bytes.NewReader(body)))
	if w.Code != http.StatusConflict { t.Fatalf("原任务已变化应拒绝撤销: %d", w.Code) }
	if err := tx.First(&model.List{}, list.ID).Error; err == nil {
		t.Fatal("部分恢复了清单，事务未回滚")
	}
}

func TestDeleteList_X08RejectsChangedApprovedTaskCount(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "X08 清单")
	task := createTestTask(t, tx, user.ID, list.ID, "确认后新增")
	r := newListRouter(NewListHandler(tx), user.ID)
	url := "/lists/" + itoa(list.ID) + "?delete_tasks=true&expected_tasks=0"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusConflict { t.Fatalf("旧范围应拒绝: %d %s", w.Code, w.Body.String()) }
	if err := tx.First(&model.Task{}, task.ID).Error; err != nil { t.Fatal("任务不应被删:", err) }
	if err := tx.First(&model.List{}, list.ID).Error; err != nil { t.Fatal("清单不应被删:", err) }
	url = "/lists/" + itoa(list.ID) + "?delete_tasks=true&expected_tasks=1"
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodDelete, url, nil))
	if w.Code != http.StatusOK { t.Fatalf("核对后删除失败: %d %s", w.Code, w.Body.String()) }
}

func TestDeleteList_HasTasks(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "有任务")
	other := createTestList(t, tx, user.ID, "其他清单")
	active := createTestTask(t, tx, user.ID, list.ID, "清单内任务")
	completed := createTestTask(t, tx, user.ID, list.ID, "已完成任务")
	if err := tx.Model(&completed).Update("is_completed", true).Error; err != nil {
		t.Fatal(err)
	}
	unrelated := createTestTask(t, tx, user.ID, other.ID, "其他任务")

	r := newListRouter(handler, user.ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/lists/"+itoa(list.ID)+"?delete_tasks=true", nil)
	r.ServeHTTP(w, req)

	assertEqual(t, w.Code, http.StatusOK, "delete populated list")
	var remaining int64
	tx.Model(&model.Task{}).Where("list_id = ? AND user_id = ?", list.ID, user.ID).Count(&remaining)
	assertEqual(t, remaining, int64(0), "list children soft deleted")
	var tombstones []model.Task
	if err := tx.Unscoped().Where("id IN ?", []uint{active.ID, completed.ID}).
		Find(&tombstones).Error; err != nil {
		t.Fatal(err)
	}
	for _, task := range tombstones {
		if !task.DeletedAt.Valid {
			t.Fatalf("任务 %d 未软删除", task.ID)
		}
	}
	var retained model.Task
	if err := tx.First(&retained, unrelated.ID).Error; err != nil {
		t.Fatal("其他清单任务被误删: ", err)
	}
	var deletedList model.List
	if err := tx.Unscoped().First(&deletedList, list.ID).Error; err != nil ||
		!deletedList.DeletedAt.Valid {
		t.Fatal("清单未软删除:", err)
	}
}

func TestDeleteList_P14LegacyDeleteRejectsPopulatedList(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	list := createTestList(t, tx, user.ID, "不能意外级联")
	task := createTestTask(t, tx, user.ID, list.ID, "保留任务")
	r := newListRouter(handler, user.ID)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/lists/"+itoa(list.ID), nil)
	r.ServeHTTP(w, req)
	assertEqual(t, w.Code, http.StatusBadRequest, "legacy delete blocked")
	if err := tx.First(&model.Task{}, task.ID).Error; err != nil {
		t.Fatal("旧接口误删任务:", err)
	}
	if err := tx.First(&model.List{}, list.ID).Error; err != nil {
		t.Fatal("旧接口误删清单:", err)
	}
}

func TestDeleteList_P14PreserveInboxAndOtherUsers(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	another := createTestUser(t, tx)
	inbox := createTestList(t, tx, user.ID, "默认收集箱")
	if err := tx.Model(&inbox).Update("is_inbox", true).Error; err != nil {
		t.Fatal(err)
	}
	inboxTask := createTestTask(t, tx, user.ID, inbox.ID, "收集箱任务")
	otherList := createTestList(t, tx, another.ID, "别人的清单")
	otherTask := createTestTask(t, tx, another.ID, otherList.ID, "别人的任务")
	r := newListRouter(handler, user.ID)
	for _, test := range []struct{
		id uint
		want int
	}{{inbox.ID, http.StatusBadRequest}, {otherList.ID, http.StatusNotFound}} {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/lists/"+itoa(test.id), nil)
		r.ServeHTTP(w, req)
		assertEqual(t, w.Code, test.want, "protected list delete")
	}
	for _, id := range []uint{inboxTask.ID, otherTask.ID} {
		var task model.Task
		if err := tx.First(&task, id).Error; err != nil {
			t.Fatal("受保护任务被误删: ", err)
		}
	}
}

func TestGetListStats_P14ExcludesDeletedListsAndTasks(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewListHandler(tx)
	user := createTestUser(t, tx)
	liveList := createTestList(t, tx, user.ID, "现有清单")
	deletedList := createTestList(t, tx, user.ID, "已删除清单")
	createTestTask(t, tx, user.ID, liveList.ID, "有效任务")
	deletedTask := createTestTask(t, tx, user.ID, liveList.ID, "已删除任务")
	createTestTask(t, tx, user.ID, deletedList.ID, "已删除清单任务")
	if err := tx.Delete(&deletedTask).Error; err != nil {
		t.Fatal(err)
	}
	if err := tx.Delete(&deletedList).Error; err != nil {
		t.Fatal(err)
	}
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	r.GET("/lists/stats", handler.GetStats)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/lists/stats", nil)
	r.ServeHTTP(w, req)
	assertEqual(t, w.Code, http.StatusOK, "GetStats status")
	var stats []struct {
		ListID uint  `json:"list_id"`
		Total  int64 `json:"total"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &stats); err != nil {
		t.Fatal(err)
	}
	assertEqual(t, len(stats), 1, "deleted lists omitted")
	assertEqual(t, stats[0].ListID, liveList.ID, "only live list")
	assertEqual(t, stats[0].Total, int64(1), "deleted tasks omitted")
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
