package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"slowlight/internal/model"
)

func setupAuthTest(t *testing.T) *AuthHandler {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	return NewAuthHandler(tx)
}

func TestRegister(t *testing.T) {
	h := setupAuthTest(t)

	body := map[string]interface{}{
		"username": "newuser",
		"email":    "new@example.com",
		"password": "123456",
		"nickname": "新用户",
	}
	jsonBody, _ := json.Marshal(body)

	r := newTestGin()
	r.POST("/register", h.Register)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("Register 返回 %d, 期望 201. Body: %s", w.Code, w.Body.String())
	}

	var resp AuthResponse
	json.Unmarshal(w.Body.Bytes(), &resp)

	if resp.Token == "" {
		t.Error("注册应返回 token")
	}
	if resp.User.Username != "newuser" {
		t.Errorf("Username = %q, 期望 %q", resp.User.Username, "newuser")
	}
	if resp.User.Nickname != "新用户" {
		t.Errorf("Nickname = %q, 期望 %q", resp.User.Nickname, "新用户")
	}
}

func TestRegister_AutoCreateDefaultLists(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	handler := NewAuthHandler(tx)

	body := map[string]interface{}{
		"username": "listuser",
		"email":    "list@example.com",
		"password": "123456",
	}
	jsonBody, _ := json.Marshal(body)

	r := newTestGin()
	r.POST("/register", handler.Register)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	var resp AuthResponse
	json.Unmarshal(w.Body.Bytes(), &resp)

	var lists []model.List
	tx.Where("user_id = ?", resp.User.ID).Find(&lists)
	if len(lists) != 3 {
		t.Errorf("注册应自动创建 3 个默认清单, 实际 %d", len(lists))
	}
}

func TestRegister_DuplicateUsername(t *testing.T) {
	h := setupAuthTest(t)

	body := map[string]interface{}{
		"username": "dupuser",
		"email":    "dup1@example.com",
		"password": "123456",
	}
	jsonBody, _ := json.Marshal(body)

	r := newTestGin()
	r.POST("/register", h.Register)

	// 第一次注册
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	// 同用户名再注册
	body["email"] = "dup2@example.com"
	jsonBody, _ = json.Marshal(body)
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/register", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusConflict {
		t.Errorf("重复用户名应返回 409, 实际 %d", w.Code)
	}
}

func TestRegister_DuplicateEmail(t *testing.T) {
	h := setupAuthTest(t)

	body := map[string]interface{}{
		"username": "user1",
		"email":    "same@example.com",
		"password": "123456",
	}
	jsonBody, _ := json.Marshal(body)

	r := newTestGin()
	r.POST("/register", h.Register)

	// 第一次
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	// 同邮箱
	body["username"] = "user2"
	jsonBody, _ = json.Marshal(body)
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/register", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusConflict {
		t.Errorf("重复邮箱应返回 409, 实际 %d", w.Code)
	}
}

func TestRegister_InvalidData(t *testing.T) {
	h := setupAuthTest(t)

	tests := []struct {
		name string
		body map[string]interface{}
	}{
		{"missing username", map[string]interface{}{"email": "a@b.com", "password": "123456"}},
		{"missing email", map[string]interface{}{"username": "user", "password": "123456"}},
		{"short password", map[string]interface{}{"username": "user", "email": "a@b.com", "password": "12"}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			jsonBody, _ := json.Marshal(tc.body)

			r := newTestGin()
			r.POST("/register", h.Register)

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(jsonBody))
			req.Header.Set("Content-Type", "application/json")
			r.ServeHTTP(w, req)

			if w.Code != http.StatusBadRequest {
				t.Errorf("%s: 返回 %d, 期望 400", tc.name, w.Code)
			}
		})
	}
}

func TestLogin(t *testing.T) {
	h := setupAuthTest(t)

	// 先注册
	regBody := map[string]interface{}{
		"username": "loginuser",
		"email":    "login@example.com",
		"password": "123456",
	}
	regJSON, _ := json.Marshal(regBody)

	r := newTestGin()
	r.POST("/register", h.Register)
	r.POST("/login", h.Login)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(regJSON))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	// 登录
	loginBody := map[string]interface{}{
		"username": "loginuser",
		"password": "123456",
	}
	loginJSON, _ := json.Marshal(loginBody)

	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/login", bytes.NewBuffer(loginJSON))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("Login 返回 %d, 期望 200. Body: %s", w.Code, w.Body.String())
	}

	var resp AuthResponse
	json.Unmarshal(w.Body.Bytes(), &resp)

	if resp.Token == "" {
		t.Error("登录应返回 token")
	}
	if resp.User.Username != "loginuser" {
		t.Errorf("Username = %q", resp.User.Username)
	}
}

func TestLogin_WrongPassword(t *testing.T) {
	h := setupAuthTest(t)

	regBody := map[string]interface{}{
		"username": "wrongpw",
		"email":    "wrongpw@example.com",
		"password": "123456",
	}
	regJSON, _ := json.Marshal(regBody)

	r := newTestGin()
	r.POST("/register", h.Register)
	r.POST("/login", h.Login)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/register", bytes.NewBuffer(regJSON))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	loginBody := map[string]interface{}{
		"username": "wrongpw",
		"password": "wrongpassword",
	}
	loginJSON, _ := json.Marshal(loginBody)

	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/login", bytes.NewBuffer(loginJSON))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("错误密码应返回 401, 实际 %d", w.Code)
	}
}

func TestLogin_NonexistentUser(t *testing.T) {
	h := setupAuthTest(t)

	body := map[string]interface{}{
		"username": "ghost",
		"password": "123456",
	}
	jsonBody, _ := json.Marshal(body)

	r := newTestGin()
	r.POST("/login", h.Login)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/login", bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("不存在的用户应返回 401, 实际 %d", w.Code)
	}
}
