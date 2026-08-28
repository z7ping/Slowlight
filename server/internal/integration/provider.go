package integration

// Provider 外部平台集成接口
// 所有支持的平台（飞书、Notion 等）都实现此接口
type Provider interface {
	// Name 平台标识（如 "feishu", "notion"）
	Name() string

	// DisplayName 平台显示名称（如 "飞书", "Notion"）
	DisplayName() string

	// ValidateCredentials 验证凭据是否有效
	ValidateCredentials(credentials map[string]interface{}) error

	// CreateTemplate 在外部平台创建数据结构（如飞书多维表格）
	// 返回创建的资源信息（如表格 URL、表 ID 映射）
	CreateTemplate(credentials map[string]interface{}) (map[string]interface{}, error)

	// ConnectExisting 绑定外部平台已有的数据结构
	ConnectExisting(credentials map[string]interface{}, resourceURL string) (map[string]interface{}, error)

	// SyncTo 同步本地数据到外部平台
	SyncTo(credentials map[string]interface{}, tableIDs map[string]string, data *SyncData) (*SyncResult, error)

	// SyncFrom 从外部平台导入数据到本地
	SyncFrom(credentials map[string]interface{}, tableIDs map[string]string) (*ImportResult, error)

	// ListCalendars 获取外部平台的日历列表（可选，支持日历的平台实现）
	ListCalendars(credentials map[string]interface{}) ([]CalendarInfo, error)

	// SyncToCalendar 将任务同步到外部平台日历（可选，支持日历的平台实现）
	SyncToCalendar(credentials map[string]interface{}, calendarID string, data *CalendarSyncData) (*SyncResult, error)
}

// SyncData 同步数据（从本地数据库查询）
type SyncData struct {
	Tasks      []TaskRecord
	Lists      []ListRecord
	Habits     []HabitRecord
	Sessions   []SessionRecord
	Reminders  []ReminderRecord
	Tags       []TagRecord
}

// TaskRecord 任务记录
type TaskRecord struct {
	ID          uint
	Title       string
	Description string
	ListName    string
	Priority    string
	IsCompleted bool
	DueDate     *int64 // unix millis
	CompletedAt *int64
	CreatedAt   int64
}

// ListRecord 清单记录
type ListRecord struct {
	Name  string
	Color string
	Icon  string
}

// HabitRecord 习惯记录
type HabitRecord struct {
	Name         string
	Icon         string
	Color        string
	Frequency    string
	StreakCount  int
	TargetDays   int
}

// SessionRecord 番茄钟记录
type SessionRecord struct {
	Type        string // work/break/long_break
	StartedAt   int64
	EndedAt     *int64
	DurationSec int
	Device      string
	TaskID      *uint
}

// ReminderRecord 休息提醒记录
type ReminderRecord struct {
	StartedAt   int64
	WorkEndedAt *int64
	RestEndedAt *int64
	WorkSeconds int
	RestSeconds int
	SkippedRest bool
	Device      string
}

// TagRecord 标签记录
type TagRecord struct {
	Name        string
	Color       string
	TaskCount   int64
}

// SyncResult 同步结果
type SyncResult struct {
	Results map[string]int    // 表名 -> 同步条数
	Errors  []string          // 错误信息列表
}

// ImportResult 导入结果
type ImportResult struct {
	Imported int
	Message  string
}

// CalendarInfo 日历信息
type CalendarInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	IsPrimary   bool   `json:"is_primary"`   // 是否为主日历
	Role        string `json:"role"`          // owner/reader/writer
}

// CalendarEvent 日历事件
type CalendarEvent struct {
	Summary     string `json:"summary"`      // 标题
	Description string `json:"description"`  // 描述
	StartTime   int64  `json:"start_time"`   // 开始时间 unix timestamp (秒)
	EndTime     int64  `json:"end_time"`     // 结束时间 unix timestamp (秒)
	IsAllDay    bool   `json:"is_all_day"`   // 全天事件
	RRule       string `json:"rrule"`        // 重复规则 (RFC 5545)
	Color       string `json:"color"`        // 颜色
}

// CalendarSyncData 同步到日历的数据
type CalendarSyncData struct {
	Events []CalendarEvent
}
