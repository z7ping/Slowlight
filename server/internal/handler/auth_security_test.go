package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

func TestAuthMiddlewareRejectsUnexpectedSigningMethod(t *testing.T) {
	secret := "test-jwt-secret-for-signing-method-check"
	t.Setenv("JWT_SECRET", secret)

	token := jwt.NewWithClaims(jwt.SigningMethodHS384, jwt.MapClaims{
		"user_id": float64(1),
		"exp":     time.Now().Add(time.Hour).Unix(),
	})
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatalf("生成测试 token 失败: %v", err)
	}

	r := newTestGin()
	r.GET("/protected", AuthMiddleware(), func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer "+tokenString)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("非 HS256 token 应返回 401，实际 %d", w.Code)
	}
}
