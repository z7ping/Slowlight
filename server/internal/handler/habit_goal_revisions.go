package handler

import (
    "errors"
    "time"

    "gorm.io/gorm"

    "slowlight/internal/model"
)

var errHabitRecordContractUsed = errors.New("已有记录，不能修改记录类型或单位")
var errHabitAnchorAfterHistory = errors.New("起算日不能晚于已有最早记录")

func habitGoalChanged(old, next model.Habit) bool {
    return old.GoalPeriod != next.GoalPeriod ||
        old.GoalMetric != next.GoalMetric ||
        old.GoalValue != next.GoalValue ||
        old.RecordType != next.RecordType ||
        old.RecordUnit != next.RecordUnit ||
        old.ScheduleRule != next.ScheduleRule
}

func recordHabitGoalRevision(tx *gorm.DB, habit model.Habit) error {
    var last model.HabitGoalRevision
    err := tx.Where("habit_id = ? AND user_id = ?", habit.ID, habit.UserID).
        Order("revision DESC").First(&last).Error
    if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) { return err }
    next := 1
    if err == nil { next = last.Revision + 1 }
    return tx.Create(&model.HabitGoalRevision{
        UserID: habit.UserID,
        HabitID: habit.ID,
        Revision: next,
        GoalPeriod: habit.GoalPeriod,
        GoalMetric: habit.GoalMetric,
        GoalValue: habit.GoalValue,
        RecordType: habit.RecordType,
        RecordUnit: habit.RecordUnit,
        ScheduleRule: habit.ScheduleRule,
        EffectiveAt: time.Now().UTC(),
    }).Error
}

// A period with no recorded contract is unknown, not retrospectively met.
// The client receives the saved revisions only; it never modifies them.
func loadHabitGoalRevisions(db *gorm.DB, userID uint, habits []model.Habit) error {
    if len(habits) == 0 { return nil }
    ids := make([]uint, 0, len(habits))
    index := make(map[uint]int, len(habits))
    for i, habit := range habits {
        ids = append(ids, habit.ID)
        index[habit.ID] = i
    }
    var revisions []model.HabitGoalRevision
    if err := db.Where("user_id = ? AND habit_id IN ?", userID, ids).
        Order("habit_id ASC, revision ASC").Find(&revisions).Error; err != nil {
        return err
    }
    for _, revision := range revisions {
        if i, ok := index[revision.HabitID]; ok {
            habits[i].GoalHistory = append(habits[i].GoalHistory, revision)
        }
    }
    return nil
}
