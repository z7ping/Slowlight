package handler

import (
    "net/http"
    "strconv"
    "sort"
    "time"

    "slowlight/internal/model"

    "github.com/gin-gonic/gin"
)

// todayTimelineItem 只投影已有事实和用户自己记录的观察/反思。
type todayTimelineItem struct {
    ID          string    `json:"id"`
    Kind        string    `json:"kind"`
    Title       string    `json:"title"`
    DurationMin int       `json:"duration_min"`
    OccurredAt  time.Time `json:"occurred_at"`
}

// GetTodayTimeline 使用账号时区确定今天，按实际发生时间逆序展示。
// 软删除、取消打卡/完成的旧事件不能回到时间轨迹。
func (h *ReviewHandler) GetTodayTimeline(c *gin.Context) {
    userID := c.GetUint("userID")
    var user model.User
    if err := h.DB.Select("timezone").First(&user, userID).Error; err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "无法读取用户时区"})
        return
    }
    loc := model.UserLocation(user.Timezone)
    now := time.Now().In(loc)
    start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
    end := start.AddDate(0, 0, 1)

    var events []struct {
        ID          uint
        EventType   string
        Title       string
        DurationMin int
        OccurredAt  time.Time
    }
    err := h.DB.Table("behavior_events AS be").
        Select("be.id, be.event_type, be.occurred_at, be.duration_min, COALESCE(t.title, h.name, '') AS title").
        Joins("LEFT JOIN tasks AS t ON be.entity_type = 'task' AND be.entity_id = t.id AND t.user_id = ? AND t.deleted_at IS NULL AND t.is_completed = true", userID).
        Joins("LEFT JOIN habits AS h ON be.entity_type = 'habit' AND be.entity_id = h.id AND h.user_id = ? AND h.deleted_at IS NULL", userID).
        Where("be.user_id = ? AND be.is_deleted = false AND be.occurred_at >= ? AND be.occurred_at < ?", userID, start, end).
        Where("(be.event_type = 'task_completed' AND t.id IS NOT NULL) OR (be.event_type = 'habit_checked' AND h.id IS NOT NULL) OR be.event_type = 'session_ended'").
        Order("be.occurred_at DESC, be.id DESC").Limit(60).Scan(&events).Error
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "无法读取今日行为记录"})
        return
    }

    var reflections []model.Reflection
    err = h.DB.Where("user_id = ? AND created_at >= ? AND created_at < ? AND entry_type IN ?", userID, start, end, []string{"observation", "reflection"}).
        Order("created_at DESC, id DESC").Limit(60).Find(&reflections).Error
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "无法读取今日观察记录"})
        return
    }
    items := make([]todayTimelineItem, 0, len(events)+len(reflections))
    for _, e := range events {
        items = append(items, todayTimelineItem{
            ID: "event:" + strconv.FormatUint(uint64(e.ID), 10), Kind: e.EventType,
            Title: e.Title, DurationMin: e.DurationMin, OccurredAt: e.OccurredAt,
        })
    }
    for _, r := range reflections {
        items = append(items, todayTimelineItem{
            ID: "reflection:" + strconv.FormatUint(uint64(r.ID), 10), Kind: r.EntryType,
            Title: r.Content, OccurredAt: r.CreatedAt,
        })
    }
    sort.Slice(items, func(i, j int) bool {
        if items[i].OccurredAt.Equal(items[j].OccurredAt) {
            return items[i].ID < items[j].ID
        }
        return items[i].OccurredAt.After(items[j].OccurredAt)
    })
    if len(items) > 40 { items = items[:40] }
    c.JSON(http.StatusOK, gin.H{"items": items})
}
