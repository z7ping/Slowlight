package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
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

func TestReflection_CreateWithAtomicCanonicalTags(t *testing.T) {
	db := beginTx(t, setupTestDB(t))
	user := createTestUser(t, db)
	other := createTestUser(t, db)
	first := model.Tag{UserID: user.ID, Name: uniqueName("学习")}
	second := model.Tag{UserID: user.ID, Name: uniqueName("阅读")}
	foreign := model.Tag{UserID: other.ID, Name: uniqueName("他人")}
	for _, tag := range []*model.Tag{&first, &second, &foreign} {
		if err := db.Create(tag).Error; err != nil { t.Fatal(err) }
	}
	router := newTestGin()
	router.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
	router.POST("/reflections", NewReflectionHandler(db).Create)
	call := func(body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		req := httptest.NewRequest("POST", "/reflections", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)
		return w
	}
	valid := fmt.Sprintf(`{"entry_type":"observation","content":"观察","tag_ids":[%d,%d,%d]}`,
		first.ID, second.ID, first.ID)
	result := call(valid)
	if result.Code != http.StatusCreated { t.Fatalf("create: %d %s", result.Code, result.Body.String()) }
	var saved reflectionResponse
	if err := json.Unmarshal(result.Body.Bytes(), &saved); err != nil { t.Fatal(err) }
	var links int64
	if err := db.Model(&model.ReflectionTag{}).Where("reflection_id = ?", saved.ID).Count(&links).Error; err != nil { t.Fatal(err) }
	assertEqual(t, links, int64(2), "UniqueTags")
	var before int64
	if err := db.Model(&model.Reflection{}).Where("user_id = ?", user.ID).Count(&before).Error; err != nil { t.Fatal(err) }
	invalid := fmt.Sprintf(`{"content":"should reject","tag_ids":[%d]}`, foreign.ID)
	result = call(invalid)
	assertEqual(t, result.Code, http.StatusBadRequest, "RejectForeignTag")
	var after int64
	if err := db.Model(&model.Reflection{}).Where("user_id = ?", user.ID).Count(&after).Error; err != nil { t.Fatal(err) }
	assertEqual(t, after, before, "NoPartialReflection")
}
