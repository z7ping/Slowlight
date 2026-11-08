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
	"time"

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


func TestReflection_ReplayRequestCreatesSingleEntry(t *testing.T) {
    db := beginTx(t, setupTestDB(t))
    user := createTestUser(t, db)
    router := newTestGin()
    router.Use(func(c *gin.Context) { withUser(c, user.ID); c.Next() })
    router.POST("/reflections", NewReflectionHandler(db).Create)
    send := func(content string) (int, reflectionResponse) {
        body, _ := json.Marshal(map[string]interface{}{
            "content": content, "entry_type": "reflection",
            "client_request_id": "device-42:reflection:10",
        })
        w := httptest.NewRecorder()
        req := httptest.NewRequest(http.MethodPost, "/reflections", bytes.NewReader(body))
        req.Header.Set("Content-Type", "application/json")
        router.ServeHTTP(w, req)
        var response reflectionResponse
        _ = json.Unmarshal(w.Body.Bytes(), &response)
        return w.Code, response
    }
    firstCode, first := send("同一条离线反思")
    replayCode, replay := send("同一条离线反思")
    if firstCode != http.StatusCreated || replayCode != http.StatusOK || first.ID != replay.ID {
        t.Fatalf("request replay failed: %d/%d ids %d/%d", firstCode, replayCode, first.ID, replay.ID)
    }
    changedCode, _ := send("不同内容")
    if changedCode != http.StatusConflict { t.Fatalf("same key with different content: %d", changedCode) }
    var count int64
    db.Model(&model.Reflection{}).Where("user_id = ?", user.ID).Count(&count)
    if count != 1 { t.Fatalf("duplicate reflection: %d", count) }
}

 
func TestReflection_PeriodQueryFindsLegacyBeyondRecentHundred(t *testing.T) {
    db := beginTx(t, setupTestDB(t))
    owner := createTestUser(t, db)
    other := createTestUser(t, db)
    key := "review-week:2026-11-02:2026-11-08"
    legacyContext := `{"source":"weekly_review","week_start":"2026-11-02","week_end":"2026-11-08"}`
    old := model.Reflection{
        UserID: owner.ID, EntryType: "reflection", Content: "早期本周回应",
        Context: legacyContext,
    }
    if err := db.Create(&old).Error; err != nil { t.Fatal(err) }
    if err := db.Model(&old).Update("created_at", time.Now().Add(-48*time.Hour)).Error; err != nil { t.Fatal(err) }
    foreign := model.Reflection{
        UserID: other.ID, EntryType: "reflection", Content: "其他账号不应出现",
        Context: legacyContext,
    }
    if err := db.Create(&foreign).Error; err != nil { t.Fatal(err) }
    for i := 0; i < 121; i++ {
        entry := model.Reflection{UserID: owner.ID, EntryType: "reflection", Content: fmt.Sprintf("ordinary-%d", i), Context: "{}"}
        if err := db.Create(&entry).Error; err != nil { t.Fatal(err) }
    }
    router := newTestGin()
    router.Use(func(c *gin.Context) { withUser(c, owner.ID); c.Next() })
    router.GET("/reflections", NewReflectionHandler(db).List)
    query := "/reflections?limit=1&question_id=" + key +
        "&legacy_week_start=2026-11-02&legacy_week_end=2026-11-08"
    w := httptest.NewRecorder()
    router.ServeHTTP(w, httptest.NewRequest(http.MethodGet, query, nil))
    if w.Code != http.StatusOK { t.Fatalf("period query: %d %s", w.Code, w.Body.String()) }
    var result struct{ Items []reflectionResponse `json:"items"` }
    if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
    if len(result.Items) != 1 || result.Items[0].ID != old.ID {
        t.Fatalf("legacy weekly reply missing or cross-account: %+v", result.Items)
    }

    exact := model.Reflection{UserID: owner.ID, EntryType: "reflection",
        QuestionID: "review-30d:2026-10-09:2026-11-07", Content: "30天回应", Context: "{}"}
    if err := db.Create(&exact).Error; err != nil { t.Fatal(err) }
    w = httptest.NewRecorder()
    router.ServeHTTP(w, httptest.NewRequest(http.MethodGet,
        "/reflections?limit=1&question_id=review-30d:2026-10-09:2026-11-07", nil))
    if w.Code != http.StatusOK { t.Fatalf("exact query: %d", w.Code) }
    if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil { t.Fatal(err) }
    if len(result.Items) != 1 || result.Items[0].ID != exact.ID {
        t.Fatalf("30day exact query lost: %+v", result.Items)
    }

    w = httptest.NewRecorder()
    router.ServeHTTP(w, httptest.NewRequest(http.MethodGet,
        "/reflections?question_id="+key+"&legacy_week_start=2026-11-03&legacy_week_end=2026-11-08", nil))
    if w.Code != http.StatusBadRequest { t.Fatalf("mismatched legacy week: %d", w.Code) }
}


func TestP08ReflectionCalendarMonthPagesAndAccountIsolation(t *testing.T) {
    db:=beginTx(t,setupTestDB(t))
    owner:=createTestUser(t,db)
    other:=createTestUser(t,db)
    month:=time.Date(2026,8,21,14,0,0,0,time.UTC)
    for i:=0;i<105;i++ {
        row:=model.Reflection{
            UserID:owner.ID,EntryType:"observation",
            Content:fmt.Sprintf("calendar-entry-%03d",i),CreatedAt:month,
        }
        if err:=db.Create(&row).Error;err!=nil{t.Fatal(err)}
    }
    for _,row:=range []model.Reflection{
        {UserID:owner.ID,EntryType:"observation",Content:"previous month",
            CreatedAt:time.Date(2026,7,31,15,0,0,0,time.UTC)},
        {UserID:other.ID,EntryType:"observation",Content:"foreign owner",
            CreatedAt:month},
    } {
        if err:=db.Create(&row).Error;err!=nil{t.Fatal(err)}
    }
    router:=newTestGin()
    router.Use(func(c *gin.Context){withUser(c,owner.ID);c.Next()})
    router.GET("/reflections",NewReflectionHandler(db).List)
    call:=func(q string) (int,[]reflectionResponse) {
        req:=httptest.NewRequest(http.MethodGet,"/reflections?"+q,nil)
        rec:=httptest.NewRecorder()
        router.ServeHTTP(rec,req)
        var answer struct{Items []reflectionResponse `json:"items"`}
        if rec.Code==http.StatusOK {
            if err:=json.Unmarshal(rec.Body.Bytes(),&answer);err!=nil{t.Fatal(err)}
        }
        return rec.Code,answer.Items
    }
    period:="start_at=2026-08-01T00%3A00%3A00Z&end_at=2026-09-01T00%3A00%3A00Z"
    code,first:=call("limit=100&"+period)
    if code!=200 || len(first)!=100 {t.Fatalf("first page: %d len=%d",code,len(first))}
    code,second:=call("limit=100&offset=100&"+period)
    if code!=200 || len(second)!=5 {t.Fatalf("second page: %d len=%d",code,len(second))}
    seen:=map[uint]bool{}
    for _,item:=range append(first,second...) {
        if seen[item.ID] {t.Fatalf("duplicate calendar record %d",item.ID)}
        seen[item.ID]=true
        if item.Content=="previous month"||item.Content=="foreign owner"{
            t.Fatalf("month/account isolation failed: %s",item.Content)
        }
    }
    for _,bad:=range []string{
        "offset=-1&"+period,
        "offset=abc&"+period,
        "start_at=2026-08-01T00%3A00%3A00Z",
        "start_at=garbage&end_at=2026-09-01T00%3A00%3A00Z",
        "start_at=2026-09-01T00%3A00%3A00Z&end_at=2026-08-01T00%3A00%3A00Z",
    } {
        status,_:=call(bad)
        if status!=400 {t.Fatalf("invalid calendar query accepted: %s (%d)",bad,status)}
    }
}
