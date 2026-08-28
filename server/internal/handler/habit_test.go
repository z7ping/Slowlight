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

func setupHabitTest(t *testing.T) (*gorm.DB, *HabitHandler, uint) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewHabitHandler(tx)
	user := createTestUser(t, tx)
	return tx, handler, user.ID
}

func newHabitRouter(h *HabitHandler, userID uint) *gin.Engine {
	r := newTestGin()
	r.Use(func(c *gin.Context) { withUser(c, userID); c.Next() })
	r.GET("/habits", h.GetHabits)
	r.POST("/habits", h.CreateHabit)
	r.PUT("/habits/:id", h.UpdateHabit)
	r.DELETE("/habits/:id", h.DeleteHabit)
	r.POST("/habits/:id/checkin", h.CheckInHabit)
	r.DELETE("/habits/:id/checkin", h.UncheckInHabit)
	r.GET("/habits/:id/logs", h.GetHabitLogs)
	r.GET("/habits/:id/streak", h.GetHabitStreak)
	return r
}

func TestCreateHabit(t *testing.T) {
	_, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	body := map[string]interface{}{
		"name":      "早起",
		"icon":      "🌅",
		"color":     "#ff6600",
		"frequency": "daily",
	}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("CreateHabit 返回 %d, 期望 201. Body: %s", w.Code, w.Body.String())
	}

	var habit model.Habit
	json.Unmarshal(w.Body.Bytes(), &habit)

	assertEqual(t, habit.Name, "早起", "Name")
	assertEqual(t, habit.Icon, "🌅", "Icon")
	assertEqual(t, habit.Frequency, "daily", "Frequency")
	assertEqual(t, habit.UserID, userID, "UserID")
}

func TestCreateHabit_InvalidJSON(t *testing.T) {
	_, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits", bytes.NewBufferString("bad"))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("返回 %d, 期望 400", w.Code)
	}
}

func TestGetHabits(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	db.Create(&model.Habit{UserID: userID, Name: "喝水", Frequency: "daily"})
	db.Create(&model.Habit{UserID: userID, Name: "运动", Frequency: "daily"})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/habits", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetHabits 返回 %d", w.Code)
	}

	var habits []model.Habit
	json.Unmarshal(w.Body.Bytes(), &habits)

	if len(habits) != 2 {
		t.Errorf("返回 %d 个习惯, 期望 2", len(habits))
	}
}

func TestUpdateHabit(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "旧名称", Frequency: "daily"}
	db.Create(&habit)

	body := map[string]interface{}{"name": "新名称", "color": "#00ff00"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/habits/"+itoa(habit.ID), bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("UpdateHabit 返回 %d", w.Code)
	}

	var result model.Habit
	json.Unmarshal(w.Body.Bytes(), &result)
	assertEqual(t, result.Name, "新名称", "Name")
}

func TestUpdateHabit_NotFound(t *testing.T) {
	_, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	body := map[string]interface{}{"name": "测试"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("PUT", "/habits/99999", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestDeleteHabit(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "待删除", Frequency: "daily"}
	db.Create(&habit)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/habits/"+itoa(habit.ID), nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("DeleteHabit 返回 %d", w.Code)
	}

	var count int64
	db.Model(&model.Habit{}).Where("id = ?", habit.ID).Count(&count)
	if count != 0 {
		t.Error("习惯未被删除")
	}
}

func TestDeleteHabit_NotFound(t *testing.T) {
	_, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/habits/99999", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestCheckInHabit(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily"}
	db.Create(&habit)

	body := map[string]interface{}{"note": "今天6点起床"}
	jsonBody, _ := json.Marshal(body)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("CheckInHabit 返回 %d. Body: %s", w.Code, w.Body.String())
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)

	if result["streak_count"].(float64) != 1 {
		t.Errorf("streak_count = %v, 期望 1", result["streak_count"])
	}
}

func TestCheckInHabit_DuplicateIsIdempotent(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily"}
	db.Create(&habit)

	body := []byte(`{}`)
	req1, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewBuffer(body))
	req1.Header.Set("Content-Type", "application/json")
	w1 := httptest.NewRecorder()
	r.ServeHTTP(w1, req1)
	if w1.Code != http.StatusOK {
		t.Fatalf("首次打卡返回 %d", w1.Code)
	}

	req2, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewBuffer(body))
	req2.Header.Set("Content-Type", "application/json")
	w2 := httptest.NewRecorder()
	r.ServeHTTP(w2, req2)

	if w2.Code != http.StatusOK {
		t.Fatalf("重复打卡应幂等返回 200, 实际 %d", w2.Code)
	}
	var result map[string]interface{}
	json.Unmarshal(w2.Body.Bytes(), &result)
	if result["already_checked"] != true {
		t.Fatalf("重复打卡应返回 already_checked=true, 实际 %v", result["already_checked"])
	}
}

func TestCheckInHabit_NotFound(t *testing.T) {
	_, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits/99999/checkin", bytes.NewBufferString(`{}`))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestGetHabitLogs(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "喝水", Frequency: "daily"}
	db.Create(&habit)
	db.Create(&model.HabitLog{HabitID: habit.ID, Date: "2026-04-14"})
	db.Create(&model.HabitLog{HabitID: habit.ID, Date: "2026-04-15"})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/habits/"+itoa(habit.ID)+"/logs", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetHabitLogs 返回 %d", w.Code)
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	logs := result["logs"].([]interface{})
	if len(logs) != 2 {
		t.Errorf("返回 %d 条记录, 期望 2", len(logs))
	}
}

func TestGetHabitLogs_FilterByMonth(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "喝水", Frequency: "daily"}
	db.Create(&habit)
	db.Create(&model.HabitLog{HabitID: habit.ID, Date: "2026-03-15"})
	db.Create(&model.HabitLog{HabitID: habit.ID, Date: "2026-04-15"})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/habits/"+itoa(habit.ID)+"/logs?month=2026-04", nil)
	r.ServeHTTP(w, req)

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	logs := result["logs"].([]interface{})
	if len(logs) != 1 {
		t.Errorf("按月筛选返回 %d 条, 期望 1", len(logs))
	}
}

func TestGetHabitStreak(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily", StreakCount: 5}
	db.Create(&habit)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/habits/"+itoa(habit.ID)+"/streak", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("GetHabitStreak 返回 %d", w.Code)
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	if result["streak_count"].(float64) != 5 {
		t.Errorf("streak_count = %v, 期望 5", result["streak_count"])
	}
}

func TestGetHabitStreak_NotFound(t *testing.T) {
	_, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/habits/99999/streak", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}

func TestUncheckInHabit(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily", StreakCount: 3}
	db.Create(&habit)

	checkInBody := map[string]interface{}{"note": "测试"}
	jsonBody, _ := json.Marshal(checkInBody)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/habits/"+itoa(habit.ID)+"/checkin", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("打卡失败: %d", w.Code)
	}

	w = httptest.NewRecorder()
	req, _ = http.NewRequest("DELETE", "/habits/"+itoa(habit.ID)+"/checkin", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("取消打卡返回 %d, 期望 200", w.Code)
	}

	var result map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &result)
	if result["message"] != "取消打卡成功" {
		t.Errorf("message = %v, 期望 '取消打卡成功'", result["message"])
	}

	var count int64
	db.Model(&model.HabitLog{}).Where("habit_id = ?", habit.ID).Count(&count)
	if count != 0 {
		t.Errorf("取消后打卡记录数 = %d, 期望 0", count)
	}
}

func TestUncheckInHabit_NotCheckedIn(t *testing.T) {
	db, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	habit := model.Habit{UserID: userID, Name: "早起", Frequency: "daily"}
	db.Create(&habit)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/habits/"+itoa(habit.ID)+"/checkin", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("未打卡取消返回 %d, 期望 404", w.Code)
	}
}

func TestUncheckInHabit_HabitNotFound(t *testing.T) {
	_, handler, userID := setupHabitTest(t)
	r := newHabitRouter(handler, userID)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("DELETE", "/habits/99999/checkin", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("返回 %d, 期望 404", w.Code)
	}
}
