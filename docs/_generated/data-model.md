# Go 数据模型（自动生成）

<!-- AUTO-GENERATED: scripts/docs/generate.py；禁止手工修改 -->

权威源：`server/internal/model/*.go`。只收录包含 GORM 标签的结构体；`gorm:"-"` 字段不列出。

> 第一版稳定生成字段名与 Go 类型，用于阻止最常见的模型文档漂移；索引、长度、默认值等精确 GORM 约束仍以源代码为准。

| Model | 来源 | 字段 |
|---|---|---|
| SystemTag | `server/internal/model/behavior_event.go` | `ID:uint`<br>`UserID:uint`<br>`Name:string`<br>`Icon:string`<br>`Color:string`<br>`DimensionKey:DimensionKey`<br>`SortOrder:int`<br>`IsDefault:bool`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| BehaviorEvent | `server/internal/model/behavior_event.go` | `ID:uint`<br>`UserID:uint`<br>`EventType:string`<br>`EntityType:string`<br>`EntityID:uint`<br>`SystemTagID:*uint`<br>`DurationMin:int`<br>`OccurredAt:time.Time`<br>`Metadata:string`<br>`IsDeleted:bool`<br>`CreatedAt:time.Time` |
| MigrationReport | `server/internal/model/migration_report.go` | `ID:uint`<br>`UserID:uint`<br>`ConflictPolicy:string`<br>`Status:string`<br>`Fingerprint:string`<br>`Created:string`<br>`CreatedAt:time.Time` |
| User | `server/internal/model/models.go` | `ID:uint`<br>`Username:string`<br>`Email:string`<br>`Password:string`<br>`Nickname:string`<br>`Avatar:string`<br>`Timezone:string`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| List | `server/internal/model/models.go` | `ID:uint`<br>`UserID:uint`<br>`Name:string`<br>`Icon:string`<br>`Color:string`<br>`SortOrder:int`<br>`IsInbox:bool`<br>`CalDAVURL:string`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| Task | `server/internal/model/models.go` | `ID:uint`<br>`UserID:uint`<br>`ListID:uint`<br>`List:List`<br>`Title:string`<br>`Description:string`<br>`DueDate:*FlexibleTime`<br>`DueTime:*string`<br>`IsCompleted:bool`<br>`CompletedAt:*time.Time`<br>`Priority:string`<br>`SortOrder:int`<br>`RepeatType:string`<br>`RepeatInterval:int`<br>`RepeatDays:string`<br>`ReminderAt:*FlexibleTime`<br>`ReminderAdvanceMinutes:int`<br>`Tags:[]Tag`<br>`SystemTagID:*uint`<br>`CalDAVUID:string`<br>`CalDAVTag:string`<br>`TaskType:string`<br>`MoodBefore:int`<br>`MoodAfter:int`<br>`IsMilestone:bool`<br>`RelatedQuestID:*uint`<br>`ObsidianLink:string`<br>`OutputLevel:string`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| Habit | `server/internal/model/models.go` | `ID:uint`<br>`UserID:uint`<br>`Name:string`<br>`Icon:string`<br>`Color:string`<br>`Frequency:string`<br>`TargetDays:int`<br>`StreakCount:int`<br>`PreferredPeriod:string`<br>`SystemTagID:*uint`<br>`GenerateTask:bool`<br>`DurationMin:int`<br>`SpecificTime:string`<br>`ShowCheckinDialog:bool`<br>`ReminderAt:string`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| HabitLog | `server/internal/model/models.go` | `ID:uint`<br>`HabitID:uint`<br>`Date:string`<br>`Period:string`<br>`DurationMin:int`<br>`Note:string`<br>`TaskID:*uint`<br>`CreatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| UserConfig | `server/internal/model/models.go` | `ID:uint`<br>`UserID:uint`<br>`Key:string`<br>`Value:string`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| SyncLog | `server/internal/model/models.go` | `ID:uint`<br>`UserID:uint`<br>`LastSyncedAt:time.Time`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time` |
| CalDAVSyncState | `server/internal/model/models.go` | `ID:uint`<br>`UserID:uint`<br>`ProjectPath:string`<br>`SyncToken:string`<br>`LastSyncedAt:time.Time`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time` |
| Reflection | `server/internal/model/reflection.go` | `ID:uint`<br>`UserID:uint`<br>`EntryType:string`<br>`QuestionID:string`<br>`DimensionKey:DimensionKey`<br>`Content:string`<br>`Context:string`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| ReminderConfig | `server/internal/model/reminder.go` | `ID:uint`<br>`UserID:uint`<br>`WorkMinutes:int`<br>`MicroRestSeconds:int`<br>`LongRestMinutes:int`<br>`MicroRestsBeforeLong:int`<br>`LockScreenMode:string`<br>`NotifyBeforeSec:int`<br>`AutoLoop:bool`<br>`AutoStartOnLaunch:bool`<br>`MicroRestStrict:bool`<br>`LongRestStrict:bool`<br>`AllowPostponeMicro:bool`<br>`AllowPostponeLong:bool`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time` |
| ReminderSession | `server/internal/model/reminder.go` | `ID:uint`<br>`UserID:uint`<br>`StartedAt:time.Time`<br>`WorkEndedAt:*time.Time`<br>`RestEndedAt:*time.Time`<br>`WorkSeconds:int`<br>`RestSeconds:int`<br>`SkippedRest:bool`<br>`Device:string`<br>`CreatedAt:time.Time` |
| WorkSession | `server/internal/model/session.go` | `ID:uint`<br>`UserID:uint`<br>`SessionType:string`<br>`StartedAt:time.Time`<br>`EndedAt:*time.Time`<br>`DurationSec:int`<br>`Device:string`<br>`TaskID:*uint`<br>`SystemTagID:*uint`<br>`CreatedAt:time.Time` |
| Subtask | `server/internal/model/subtask.go` | `ID:uint`<br>`TaskID:uint`<br>`Title:string`<br>`IsCompleted:bool`<br>`SortOrder:int`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time` |
| Tag | `server/internal/model/tag.go` | `ID:uint`<br>`Name:string`<br>`Color:string`<br>`UserID:uint`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time`<br>`DeletedAt:gorm.DeletedAt` |
| TaskTag | `server/internal/model/tag.go` | `TaskID:uint`<br>`TagID:uint` |
| Webhook | `server/internal/model/webhook.go` | `ID:uint`<br>`UserID:uint`<br>`URL:string`<br>`Event:string`<br>`Secret:string`<br>`Name:string`<br>`IsActive:bool`<br>`CreatedAt:time.Time`<br>`UpdatedAt:time.Time` |

## 扫描到的 AutoMigrate

| Model | 触发位置 |
|---|---|
| User | `server/internal/config/database.go` |
| List | `server/internal/config/database.go` |
| Task | `server/internal/config/database.go` |
| Subtask | `server/internal/config/database.go` |
| Tag | `server/internal/config/database.go` |
| TaskTag | `server/internal/config/database.go` |
| Habit | `server/internal/config/database.go` |
| HabitLog | `server/internal/config/database.go` |
| UserConfig | `server/internal/config/database.go` |
| Webhook | `server/internal/config/database.go` |
| SystemTag | `server/internal/config/database.go` |
| BehaviorEvent | `server/internal/config/database.go` |
| Reflection | `server/internal/config/database.go` |
| CalDAVSyncState | `server/internal/config/database.go` |
| MigrationReport | `server/internal/config/database.go` |
| ReminderConfig | `server/internal/handler/reminder.go` |
| ReminderSession | `server/internal/handler/reminder.go` |
| WorkSession | `server/internal/handler/session.go` |
| User | `server/internal/handler/test_helper.go` |
| List | `server/internal/handler/test_helper.go` |
| Task | `server/internal/handler/test_helper.go` |
| Subtask | `server/internal/handler/test_helper.go` |
| Tag | `server/internal/handler/test_helper.go` |
| TaskTag | `server/internal/handler/test_helper.go` |
| Habit | `server/internal/handler/test_helper.go` |
| HabitLog | `server/internal/handler/test_helper.go` |
| UserConfig | `server/internal/handler/test_helper.go` |
| SystemTag | `server/internal/handler/test_helper.go` |
| BehaviorEvent | `server/internal/handler/test_helper.go` |
| Reflection | `server/internal/handler/test_helper.go` |
| WorkSession | `server/internal/handler/test_helper.go` |
| ReminderConfig | `server/internal/handler/test_helper.go` |
| ReminderSession | `server/internal/handler/test_helper.go` |
| CalDAVSyncState | `server/internal/handler/test_helper.go` |
| MigrationReport | `server/internal/handler/test_helper.go` |
| Webhook | `server/internal/handler/test_helper.go` |

共扫描到 36 个 Model/位置组合。
