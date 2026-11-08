package handler

import (
    "bytes"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"
    "time"

    "slowlight/internal/model"
)

func TestP05HistoricalStreakRespectsGoalRevision(t *testing.T) {
    db,handler,userID:=setupHabitTest(t)
    router:=newHabitRouter(handler,userID)
    body,_:=json.Marshal(map[string]interface{}{
        "name":"每日阅读目标","goal_period":"day",
        "goal_metric":"events","goal_value":1,
    })
    request:=httptest.NewRequest(http.MethodPost,"/habits",bytes.NewReader(body))
    request.Header.Set("Content-Type","application/json")
    created:=httptest.NewRecorder()
    router.ServeHTTP(created,request)
    if created.Code!=http.StatusCreated{t.Fatalf("create: %s",created.Body.String())}
    var habit model.Habit
    if err:=json.Unmarshal(created.Body.Bytes(),&habit);err!=nil{t.Fatal(err)}
    if err:=db.Model(&model.HabitGoalRevision{}).
        Where("habit_id = ? AND revision = 1",habit.ID).
        Update("effective_at",time.Now().AddDate(0,0,-3).UTC()).Error;err!=nil{t.Fatal(err)}
    var user model.User
    if err:=db.First(&user,userID).Error;err!=nil{t.Fatal(err)}
    now:=time.Now().In(model.UserLocation(user.Timezone))
    yesterday:=now.AddDate(0,0,-1).Format("2006-01-02")
    today:=now.Format("2006-01-02")
    for _,date:=range []string{yesterday,today,today} {
        if err:=db.Create(&model.HabitLog{HabitID:habit.ID,Date:date}).Error;err!=nil{t.Fatal(err)}
    }
    updatedBody:=[]byte(`{"goal_value":2}`)
    update:=httptest.NewRequest(http.MethodPut,
        "/habits/"+itoa(habit.ID),bytes.NewReader(updatedBody))
    update.Header.Set("Content-Type","application/json")
    response:=httptest.NewRecorder()
    router.ServeHTTP(response,update)
    if response.Code!=http.StatusOK{t.Fatalf("update: %s",response.Body.String())}
    var updated model.Habit
    if err:=json.Unmarshal(response.Body.Bytes(),&updated);err!=nil{t.Fatal(err)}
    if updated.StreakCount!=2{
        t.Fatalf("old goal must not be recalculated: streak=%d",updated.StreakCount)
    }
}

func TestP05HabitGoalRevisionIsAppendOnlyAndAccountScoped(t *testing.T) {
    db, handler, userID := setupHabitTest(t)
    router := newHabitRouter(handler,userID)
    send := func(method,route string,body map[string]interface{},expected int) model.Habit {
        data,_:=json.Marshal(body)
        request:=httptest.NewRequest(method,route,bytes.NewReader(data))
        request.Header.Set("Content-Type","application/json")
        response:=httptest.NewRecorder()
        router.ServeHTTP(response,request)
        if response.Code!=expected {t.Fatalf("%s %s got %d: %s",method,route,response.Code,response.Body.String())}
        var value model.Habit
        if err:=json.Unmarshal(response.Body.Bytes(),&value);err!=nil{t.Fatal(err)}
        return value
    }
    created:=send(http.MethodPost,"/habits",map[string]interface{}{
        "name":"每周三次", "goal_period":"week","goal_metric":"events","goal_value":3,
    },http.StatusCreated)
    if len(created.GoalHistory)!=1 || created.GoalHistory[0].GoalValue!=3 ||
        created.GoalHistory[0].Revision!=1 {
        t.Fatalf("create must persist revision 1: %+v",created.GoalHistory)
    }
    route:="/habits/"+itoa(created.ID)
    cosmetic:=send(http.MethodPut,route,map[string]interface{}{"name":"改名"},http.StatusOK)
    if len(cosmetic.GoalHistory)!=1 {t.Fatalf("cosmetic edit appended revision: %+v",cosmetic.GoalHistory)}
    updated:=send(http.MethodPut,route,map[string]interface{}{"goal_value":5},http.StatusOK)
    if len(updated.GoalHistory)!=2 || updated.GoalHistory[0].GoalValue!=3 ||
        updated.GoalHistory[1].GoalValue!=5 || updated.GoalHistory[1].Revision!=2 {
        t.Fatalf("goal change lost evidence: %+v",updated.GoalHistory)
    }
    retried:=send(http.MethodPut,route,map[string]interface{}{"goal_value":5},http.StatusOK)
    if len(retried.GoalHistory)!=2 {t.Fatalf("replay made extra revision: %+v",retried.GoalHistory)}
    if err:=db.Create(&model.HabitLog{
        HabitID:created.ID,Date:"2026-11-05",Note:"不可修改的真实记录",
    }).Error;err!=nil{t.Fatal(err)}
    for _,payload:=range []map[string]interface{}{
        {"record_type":"count"},
        {"record_unit":"杯"},
        {"schedule_rule":map[string]interface{}{
            "version":1,"kind":"interval","unit":"day","every":1,
            "anchor_date":"2026-12-01","anchor_time":"08:00",
            "reminder_mode":"off","reminder_time":"09:00",
        }},
    }{
        body,_:=json.Marshal(payload)
        response:=httptest.NewRecorder()
        req:=httptest.NewRequest(http.MethodPut,route,bytes.NewReader(body))
        req.Header.Set("Content-Type","application/json")
        router.ServeHTTP(response,req)
        if response.Code!=http.StatusConflict{
            t.Fatalf("history contract mutated: %d %s",response.Code,response.Body.String())
        }
    }
    var revisions []model.HabitGoalRevision
    if err:=db.Where("habit_id = ?",created.ID).Find(&revisions).Error;err!=nil{t.Fatal(err)}
    if len(revisions)!=2 {t.Fatalf("rejected edits changed goal history: %+v",revisions)}
    legacy:=model.Habit{UserID:userID,Name:"旧目标",GoalPeriod:"day",GoalMetric:"events",GoalValue:1}
    if err:=db.Create(&legacy).Error;err!=nil{t.Fatal(err)}
    saved:=send(http.MethodPut,"/habits/"+itoa(legacy.ID),
        map[string]interface{}{"goal_value":2},http.StatusOK)
    if len(saved.GoalHistory)!=1 || saved.GoalHistory[0].GoalValue!=2 {
        t.Fatalf("legacy old target must remain unknown: %+v",saved.GoalHistory)
    }

    foreign:=createTestUser(t,db)
    other:=model.HabitGoalRevision{
        UserID:foreign.ID,HabitID:created.ID,Revision:999,
        GoalPeriod:"day",GoalMetric:"events",GoalValue:999,
        RecordType:"check",ScheduleRule:"{}",
    }
    // Unique (habit,revision) stays independent from user ID. This foreign
    // row simulates bad historic input: the owner-scoped reader must ignore it.
    if err:=db.Create(&other).Error;err!=nil{t.Fatal(err)}
    list:=httptest.NewRecorder()
    router.ServeHTTP(list,httptest.NewRequest(http.MethodGet,"/habits",nil))
    if list.Code!=http.StatusOK {t.Fatalf("list failed: %s",list.Body.String())}
    var habits []model.Habit
    if err:=json.Unmarshal(list.Body.Bytes(),&habits);err!=nil{t.Fatal(err)}
    for _,habit:=range habits {
        if habit.ID==created.ID && len(habit.GoalHistory)!=2 {
            t.Fatalf("cross-account revision leaked: %+v",habit.GoalHistory)
        }
    }
}
