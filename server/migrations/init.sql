-- Slowlight 数据库初始化脚本
-- 基于生产数据库 2026-04-21 完整 schema 导出

-- 创建数据库（手动执行）
-- CREATE DATABASE slowlight;

-- ========================================
-- 1. 用户表 (无外键依赖，最先创建)
-- ========================================
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    password VARCHAR(255) NOT NULL,
    nickname VARCHAR(50) DEFAULT '',
    avatar VARCHAR(255) DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    timezone VARCHAR(50) DEFAULT 'Asia/Shanghai'
);

-- ========================================
-- 2. 清单表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS lists (
    id SERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(50) DEFAULT '📋',
    color VARCHAR(20) DEFAULT '#1890ff',
    sort_order BIGINT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    is_inbox BOOLEAN DEFAULT FALSE,
    cal_dav_url VARCHAR(500)
);

-- ========================================
-- 3. 任务表 (依赖 users, lists)
-- ========================================
CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    list_id BIGINT NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    description TEXT DEFAULT '',
    due_date TIMESTAMPTZ,
    due_time VARCHAR(10),
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMP,
    priority VARCHAR(10) DEFAULT 'none',
    sort_order BIGINT DEFAULT 0,
    repeat_type VARCHAR(20) DEFAULT 'none',
    repeat_interval BIGINT DEFAULT 1,
    repeat_days VARCHAR(20) DEFAULT '',
    reminder_at TIMESTAMP,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    reminder_advance_minutes BIGINT DEFAULT 0,
    system_tag_id BIGINT,
    task_type VARCHAR(20) DEFAULT 'daily',
    mood_before BIGINT DEFAULT 0,
    mood_after BIGINT DEFAULT 0,
    is_milestone BOOLEAN DEFAULT FALSE,
    related_quest_id BIGINT,
    obsidian_link VARCHAR(500) DEFAULT '',
    output_level VARCHAR(5) DEFAULT '',
    cal_dav_uid VARCHAR(255),
    cal_dav_tag VARCHAR(255)
);

-- ========================================
-- 4. 标签表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS tags (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    color VARCHAR(20) DEFAULT '#0075de',
    user_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);

-- ========================================
-- 5. 任务-标签关联表 (依赖 tasks, tags)
-- ========================================
CREATE TABLE IF NOT EXISTS task_tags (
    task_id BIGINT NOT NULL,
    tag_id BIGINT NOT NULL,
    PRIMARY KEY (task_id, tag_id)
);

-- ========================================
-- 6. 子任务表 (依赖 tasks)
-- ========================================
CREATE TABLE IF NOT EXISTS subtasks (
    id BIGSERIAL PRIMARY KEY,
    task_id BIGINT NOT NULL,
    title VARCHAR(500) NOT NULL,
    is_completed BOOLEAN DEFAULT FALSE,
    sort_order BIGINT DEFAULT 0,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- ========================================
-- 7. 习惯表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS habits (
    id SERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(50) DEFAULT '✅',
    color VARCHAR(20) DEFAULT '#52c41a',
    frequency VARCHAR(20) DEFAULT 'daily',
    target_days BIGINT DEFAULT 0,
    streak_count BIGINT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    preferred_period VARCHAR(20) DEFAULT '',
    system_tag_id BIGINT,
    generate_task BOOLEAN DEFAULT FALSE,
    duration_min BIGINT DEFAULT 0
);

-- ========================================
-- 8. 打卡记录表 (依赖 habits, tasks)
-- ========================================
CREATE TABLE IF NOT EXISTS habit_logs (
    id SERIAL PRIMARY KEY,
    habit_id BIGINT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
    date VARCHAR(10) NOT NULL,
    note VARCHAR(500) DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    period VARCHAR(20) DEFAULT '',
    duration_min BIGINT DEFAULT 0,
    task_id BIGINT,
    UNIQUE(habit_id, date)
);

-- ========================================
-- 9. 系统标签表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS system_tags (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    name VARCHAR(50) NOT NULL,
    icon VARCHAR(10) DEFAULT '🏷️',
    color VARCHAR(20) DEFAULT '#1890ff',
    sort_order BIGINT DEFAULT 0,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- ========================================
-- 10. 用户配置表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS user_configs (
    id SERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key VARCHAR(50) NOT NULL,
    value TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(user_id, key)
);

-- ========================================
-- 11. 行为事件表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS behavior_events (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    event_type VARCHAR(30) NOT NULL,
    entity_type VARCHAR(20) NOT NULL,
    entity_id BIGINT NOT NULL,
    system_tag_id BIGINT,
    duration_min BIGINT DEFAULT 0,
    occurred_at TIMESTAMPTZ NOT NULL,
    metadata TEXT DEFAULT '{}',
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ
);

-- ========================================
-- 12. CalDAV 同步状态表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS cal_dav_sync_states (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    project_path VARCHAR(500) NOT NULL,
    sync_token VARCHAR(500) DEFAULT '',
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- ========================================
-- 13. 提醒配置表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS reminder_configs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    work_minutes BIGINT DEFAULT 50,
    rest_minutes BIGINT DEFAULT 10,
    lock_screen BOOLEAN DEFAULT FALSE,
    enabled BOOLEAN DEFAULT FALSE,
    notify_before_sec BIGINT DEFAULT 60,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- ========================================
-- 14. 提醒会话表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS reminder_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    work_ended_at TIMESTAMPTZ,
    rest_ended_at TIMESTAMPTZ,
    work_seconds BIGINT DEFAULT 0,
    rest_seconds BIGINT DEFAULT 0,
    skipped_rest BOOLEAN,
    device VARCHAR(50),
    created_at TIMESTAMPTZ
);

-- ========================================
-- 15. Webhooks 表
-- ========================================
CREATE TABLE IF NOT EXISTS webhooks (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    url VARCHAR(1024),
    event VARCHAR(50),
    secret VARCHAR(255),
    name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- ========================================
-- 16. 工作会话表 (依赖 users)
-- ========================================
CREATE TABLE IF NOT EXISTS work_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    session_type VARCHAR(20) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_sec BIGINT DEFAULT 0,
    device VARCHAR(50),
    task_id BIGINT,
    created_at TIMESTAMPTZ,
    system_tag_id BIGINT
);

-- ========================================
-- 唯一约束
-- ========================================
ALTER TABLE users ADD CONSTRAINT users_username_key UNIQUE (username);
ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email);
ALTER TABLE tags ADD CONSTRAINT idx_tags_user_id UNIQUE (user_id);
ALTER TABLE cal_dav_sync_states ADD CONSTRAINT idx_caldav_user_path UNIQUE (user_id, project_path);

-- ========================================
-- 索引
-- ========================================

-- users
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at);

-- lists
CREATE INDEX IF NOT EXISTS idx_lists_user_id ON lists(user_id);
CREATE INDEX IF NOT EXISTS idx_lists_deleted_at ON lists(deleted_at);
CREATE INDEX IF NOT EXISTS idx_lists_is_inbox ON lists(is_inbox);

-- tasks
CREATE INDEX IF NOT EXISTS idx_tasks_user_id ON tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_is_completed ON tasks(is_completed);
CREATE INDEX IF NOT EXISTS idx_tasks_reminder_at ON tasks(reminder_at);
CREATE INDEX IF NOT EXISTS idx_tasks_repeat_type ON tasks(repeat_type);
CREATE INDEX IF NOT EXISTS idx_tasks_deleted_at ON tasks(deleted_at);
CREATE INDEX IF NOT EXISTS idx_tasks_system_tag_id ON tasks(system_tag_id);
CREATE INDEX IF NOT EXISTS idx_tasks_related_quest_id ON tasks(related_quest_id);
CREATE INDEX IF NOT EXISTS idx_tasks_cal_dav_uid ON tasks(cal_dav_uid);

-- habits
CREATE INDEX IF NOT EXISTS idx_habits_user_id ON habits(user_id);
CREATE INDEX IF NOT EXISTS idx_habits_deleted_at ON habits(deleted_at);
CREATE INDEX IF NOT EXISTS idx_habits_system_tag_id ON habits(system_tag_id);

-- habit_logs
CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_id ON habit_logs(habit_id);
CREATE INDEX IF NOT EXISTS idx_habit_logs_date ON habit_logs(date);
CREATE INDEX IF NOT EXISTS idx_habit_logs_deleted_at ON habit_logs(deleted_at);
CREATE INDEX IF NOT EXISTS idx_habit_logs_task_id ON habit_logs(task_id);

-- user_configs
CREATE INDEX IF NOT EXISTS idx_user_key ON user_configs(user_id, key);
CREATE INDEX IF NOT EXISTS idx_user_configs_deleted_at ON user_configs(deleted_at);

-- behavior_events
CREATE INDEX IF NOT EXISTS idx_user_event_occurred ON behavior_events(user_id, event_type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_user_occurred ON behavior_events(user_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_user_system_occurred ON behavior_events(user_id, system_tag_id, occurred_at);

-- tags
CREATE INDEX IF NOT EXISTS idx_user_tag_name ON tags(user_id);
CREATE INDEX IF NOT EXISTS idx_tags_deleted_at ON tags(deleted_at);

-- subtasks
CREATE INDEX IF NOT EXISTS idx_subtasks_task_id ON subtasks(task_id);

-- system_tags
CREATE INDEX IF NOT EXISTS idx_system_tags_user_id ON system_tags(user_id);

-- reminder_configs
CREATE UNIQUE INDEX IF NOT EXISTS idx_reminder_configs_user_id ON reminder_configs(user_id);

-- reminder_sessions
CREATE INDEX IF NOT EXISTS idx_reminder_sessions_user_id ON reminder_sessions(user_id);

-- webhooks
CREATE INDEX IF NOT EXISTS idx_webhooks_user_id ON webhooks(user_id);
CREATE INDEX IF NOT EXISTS idx_webhooks_event ON webhooks(event);

-- work_sessions
CREATE INDEX IF NOT EXISTS idx_work_sessions_user_id ON work_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_work_sessions_system_tag_id ON work_sessions(system_tag_id);
