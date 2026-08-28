package model

import "gorm.io/gorm"

// AfterSave keeps task completion corrections consistent with BehaviorEvent.
// Habit uncheck already removes its corresponding event; task uncomplete follows
// the same semantics so Review/Analytics do not keep a completion the user reverted.
func (task *Task) AfterSave(tx *gorm.DB) error {
	if task.ID == 0 || task.UserID == 0 || task.IsCompleted {
		return nil
	}

	return tx.Where(
		"user_id = ? AND event_type = ? AND entity_type = ? AND entity_id = ?",
		task.UserID,
		"task_completed",
		"task",
		task.ID,
	).Delete(&BehaviorEvent{}).Error
}
