package model

import (
	"time"

	"gorm.io/gorm"
)

// User 用户模型
type User struct {
	ID        uint           `json:"id" gorm:"primaryKey"`
	Username  string         `json:"username" gorm:"size:50;uniqueIndex;not null"`
	Email     string         `json:"email" gorm:"size:100;uniqueIndex;not null"`
	Password  string         `json:"-" gorm:"size:255;not null"` // 不返回密码
	Nickname  string         `json:"nickname" gorm:"size:50;default:''"`
	Avatar    string         `json:"avatar" gorm:"size:255;default:''"`
	Timezone  string         `json:"timezone" gorm:"size:50;default:'Asia/Shanghai'"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `json:"-" gorm:"index"`
}

// List 清单模型
type List struct {
	ID        uint           `json:"id" gorm:"primaryKey"`
	UserID    uint           `json:"user_id" gorm:"not null;uniqueIndex:idx_user_list_name"`
	Name      string         `json:"name" gorm:"size:100;not null;uniqueIndex:idx_user_list_name"`
	Icon      string         `json:"icon" gorm:"size:50;default:'📋'"`
	Color     string         `json:"color" gorm:"size:20;default:'#1890ff'"`
	SortOrder int            `json:"sort_order" gorm:"default:0"`
	IsInbox   bool           `json:"is_inbox" gorm:"default:false;index"`
	CalDAVURL string         `json:"-" gorm:"size:500"` // Vikunja CalDAV 路径，如 /dav/projects/5
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `json:"deleted_at,omitempty" gorm:"index"`
}

// Task 任务模型
type Task struct {
	ID          uint           `json:"id" gorm:"primaryKey"`
	UserID      uint           `json:"user_id" gorm:"not null;index"`
	ListID      uint           `json:"list_id" gorm:"not null"`
	List        List           `json:"list" gorm:"foreignKey:ListID"`
	Title       string         `json:"title" gorm:"size:500;not null"`
	Description string         `json:"description" gorm:"default:''"`
	DueDate     *FlexibleTime  `json:"due_date"`
	DueTime     *string        `json:"due_time" gorm:"size:10"`
	IsCompleted bool           `json:"is_completed" gorm:"default:false"`
	CompletedAt *time.Time     `json:"completed_at"`
	Priority    string         `json:"priority" gorm:"size:10;default:'none'"`
	SortOrder   int            `json:"sort_order" gorm:"default:0"`

	// 重复任务
	RepeatType     string `json:"repeat_type" gorm:"size:20;default:'none'"`
	RepeatInterval int    `json:"repeat_interval" gorm:"default:1"`
	RepeatDays     string `json:"repeat_days" gorm:"size:20;default:''"`

	// 提醒
	ReminderAt            *FlexibleTime `json:"reminder_at"`
	ReminderAdvanceMinutes int          `json:"reminder_advance_minutes" gorm:"default:0"`

	// 子任务进度（只读，非数据库字段）
	SubtaskCount     int `json:"subtask_count" gorm:"-"`
	CompletedSubtask int `json:"completed_subtask" gorm:"-"`

	// 子任务列表（GET /tasks/:id 时返回）
	Subtasks []Subtask `json:"subtasks,omitempty" gorm:"-"`

	// 标签列表
	Tags []Tag `json:"tags,omitempty" gorm:"many2many:task_tags;"`

	// 传递的 tag_ids（用于创建/更新任务时设置标签，不存储在数据库）
	TagIDs []uint `json:"tag_ids,omitempty" gorm:"-"`

	// 系统标签（可选，用于番茄钟自动继承）
	SystemTagID *uint `json:"system_tag_id" gorm:"index"`

	// CalDAV 同步标识
	CalDAVUID string `json:"-" gorm:"size:255;index"`  // VTODO UID，用于关联远程任务
	CalDAVTag string `json:"-" gorm:"size:255"`         // ETag，用于检测变更

	// Phase 2: 任务模型升级
	TaskType       string `json:"task_type" gorm:"size:20;default:'daily'"`         // main/branch/daily/explore
	MoodBefore     int    `json:"mood_before" gorm:"default:0"`                     // 情绪评分 1-5，0=未评
	MoodAfter      int    `json:"mood_after" gorm:"default:0"`                      // 情绪评分 1-5，0=未评
	IsMilestone    bool   `json:"is_milestone" gorm:"default:false"`                // 是否里程碑
	RelatedQuestID *uint  `json:"related_quest_id" gorm:"index"`                   // 关联的主线任务
	ObsidianLink   string `json:"obsidian_link" gorm:"size:500;default:''"`         // Obsidian 笔记路径
	OutputLevel    string `json:"output_level" gorm:"size:5;default:''"`            // S/A/B/C 输出等级

	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `json:"deleted_at,omitempty" gorm:"index"`
}

// Habit 习惯打卡模型
type Habit struct {
	ID              uint           `json:"id" gorm:"primaryKey"`
	UserID          uint           `json:"user_id" gorm:"not null;index"`
	Name            string         `json:"name" gorm:"size:100;not null"`
	Icon            string         `json:"icon" gorm:"size:50;default:'✅'"`
	Color           string         `json:"color" gorm:"size:20;default:'#52c41a'"`
	Frequency       string         `json:"frequency" gorm:"size:20;default:'daily'"` // daily/weekly/monthly
	TargetDays      int            `json:"target_days" gorm:"default:0"`            // 0 = 无限制
	StreakCount     int            `json:"streak_count" gorm:"default:0"`           // 连续打卡天数
	PreferredPeriod string         `json:"preferred_period" gorm:"size:20;default:''"` // morning/afternoon/evening/night
	SystemTagID     *uint          `json:"system_tag_id" gorm:"index"`              // 关联系统标签（可选）
	GenerateTask    bool           `json:"generate_task" gorm:"default:false"`      // 是否自动生成任务
	DurationMin     int            `json:"duration_min" gorm:"default:0"`           // 预期时长（分钟）
	SpecificTime    string         `json:"specific_time" gorm:"size:5;default:''"`  // 计划执行时间 HH:mm
	ShowCheckinDialog bool          `json:"show_checkin_dialog" gorm:"default:false"`       // 打卡时是否弹窗填写日志
	ReminderAt      string         `json:"reminder_at" gorm:"type:jsonb;default:'{}'"` // 提醒配置 JSON
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `json:"deleted_at,omitempty" gorm:"index"`
	CheckedToday    bool           `json:"checked_today" gorm:"-"`                     // 今日是否已打卡（非数据库字段）
	CheckedDays     []string       `json:"checked_days" gorm:"-"`                      // 本周打卡日期（非数据库字段）
}

// HabitLog 打卡记录
type HabitLog struct {
	ID           uint           `json:"id" gorm:"primaryKey"`
	HabitID      uint           `json:"habit_id" gorm:"not null;index"`
	Date         string         `json:"date" gorm:"size:10;not null"`          // YYYY-MM-DD
	Period       string         `json:"period" gorm:"size:20;default:''"`      // morning/afternoon/evening/night
	DurationMin  int            `json:"duration_min" gorm:"default:0"`         // 实际时长
	Note         string         `json:"note" gorm:"size:500;default:''"`
	TaskID       *uint          `json:"task_id" gorm:"index"`                  // 关联任务 ID（可选）
	CreatedAt    time.Time      `json:"created_at"`
	DeletedAt    gorm.DeletedAt `json:"-" gorm:"index"`
}

// UserConfig 用户配置（用于存储飞书等第三方配置）
type UserConfig struct {
	ID        uint           `json:"id" gorm:"primaryKey"`
	UserID    uint           `json:"user_id" gorm:"not null;uniqueIndex:idx_user_key"`
	Key       string         `json:"key" gorm:"size:50;not null;uniqueIndex:idx_user_key"`
	Value     string         `json:"value" gorm:"type:text"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `json:"-" gorm:"index"`
}

// SyncLog 同步日志模型 - 记录用户最后同步时间
type SyncLog struct {
	ID            uint      `json:"id" gorm:"primaryKey"`
	UserID        uint      `json:"user_id" gorm:"not null;index"`
	LastSyncedAt  time.Time `json:"last_synced_at"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// SyncDeletedItem 用于返回已删除的记录信息
type SyncDeletedItem struct {
	ID        uint           `json:"id"`
	DeletedAt gorm.DeletedAt `json:"deleted_at"`
}

// BatchOperation 批量同步操作
type BatchOperation struct {
	Type   string                 `json:"type"`   // create, update, delete
	Entity string                 `json:"entity"` // task, list, habit
	ID     uint                   `json:"id,omitempty"`
	Data   map[string]interface{} `json:"data,omitempty"`
}

// BatchSyncRequest 批量同步请求
type BatchSyncRequest struct {
	Operations []BatchOperation `json:"operations"`
}

// BatchSyncResult 批量同步结果项
type BatchSyncResult struct {
	Index    int    `json:"index"`
	Success  bool   `json:"success"`
	Entity   string `json:"entity"`
	ID       uint   `json:"id,omitempty"`
	OldID    uint   `json:"old_id,omitempty"`
	Error    string `json:"error,omitempty"`
}

// BatchSyncResponse 批量同步响应
type BatchSyncResponse struct {
	Results []BatchSyncResult `json:"results"`
}

// SyncTimestampRequest 同步时间戳请求
type SyncTimestampRequest struct {
	LastSyncedAt time.Time `json:"last_synced_at"`
}

// CalDAVSyncState CalDAV 同步状态
type CalDAVSyncState struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	UserID       uint      `json:"user_id" gorm:"not null;uniqueIndex:idx_caldav_user_path"`
	ProjectPath  string    `json:"project_path" gorm:"size:500;not null;uniqueIndex:idx_caldav_user_path"` // /dav/projects/{id}
	SyncToken    string    `json:"sync_token" gorm:"size:500;default:''"`                                  // 增量同步 token
	LastSyncedAt time.Time `json:"last_synced_at"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}
