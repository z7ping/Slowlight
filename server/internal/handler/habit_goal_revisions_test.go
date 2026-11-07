package handler

import (
    "bytes"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "testing"

    "slowlight/internal/model"
)

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
