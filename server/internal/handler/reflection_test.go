package handler

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"slowlight/internal/model"

	"github.com/gin-gonic/gin"
)

func TestReflection_CreateAndListForCurrentUser(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	other := createTestUser(t, tx)
	h := NewReflectionHandler(tx)
	r := newTestGin()
	r.Use(func(c *gin.Context) {
		withUser(c, user.ID)
		c.Next()
	})
	r.POST("/reflections", h.Create)
	r.GET("/reflections", h.List)

	body := []byte(`{"entry_type":"reflection","question_id":"q1","dimension_key":"body","content":"今天有点累","context":{"source":"test"}}`)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/reflections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	assertEqual(t, w.Code, http.StatusCreated, "CreateStatus")

	tx.Create(&model.Reflection{UserID: other.ID, EntryType: "observation", Content: "other"})

	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/reflections?limit=10", nil)
	r.ServeHTTP(w, req)
	assertEqual(t, w.Code, http.StatusOK, "ListStatus")
	var response struct {
		Items []reflectionResponse `json:"items"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	assertEqual(t, len(response.Items), 1, "OwnedItems")
	assertEqual(t, response.Items[0].Content, "今天有点累", "Content")
	assertEqual(t, response.Items[0].DimensionKey, model.DimensionBody, "Dimension")
}

func TestReflection_RejectsUnknownDimension(t *testing.T) {
	db := setupTestDB(t)
	tx := beginTx(t, db)
	user := createTestUser(t, tx)
	h := NewReflectionHandler(tx)
	c, w := newTestContext("POST", "/reflections", user.ID)
	c.Request.Body = io.NopCloser(strings.NewReader(`{"content":"x","dimension_key":"money"}`))
	c.Request.Header.Set("Content-Type", "application/json")
	h.Create(c)
	assertEqual(t, w.Code, http.StatusBadRequest, "Status")
}
