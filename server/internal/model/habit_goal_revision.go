package model

import "time"

// HabitGoalRevision is append-only evidence of the goal contract as it was
// saved. Old habits have no fabricated revisions: periods without a revision
// cannot be assigned a historical target retroactively.
type HabitGoalRevision struct {
    ID           uint      `json:"id" gorm:"primaryKey"`
    UserID       uint      `json:"user_id" gorm:"not null;index"`
    HabitID      uint      `json:"habit_id" gorm:"not null;uniqueIndex:idx_habit_goal_revision,priority:1"`
    Revision     int       `json:"revision" gorm:"not null;uniqueIndex:idx_habit_goal_revision,priority:2"`
    GoalPeriod   string    `json:"goal_period" gorm:"size:10;not null"`
    GoalMetric   string    `json:"goal_metric" gorm:"size:12;not null"`
    GoalValue    int       `json:"goal_value" gorm:"not null"`
    RecordUnit   string    `json:"record_unit" gorm:"size:20;not null"`
    RecordType   string    `json:"record_type" gorm:"size:20;not null"`
    ScheduleRule string    `json:"schedule_rule" gorm:"type:text;not null"`
    EffectiveAt  time.Time `json:"effective_at" gorm:"not null;index"`
}
