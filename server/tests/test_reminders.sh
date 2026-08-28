#!/usr/bin/env bash
# Slowlight - 休息提醒模块测试
# 用法: ./test_reminders.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "休息提醒模块测试"

setup_user

# 1. 获取提醒配置
info "测试 GET /api/reminder/config..."
CONFIG=$(api GET /reminder/config)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取提醒配置成功"

# 2. 保存提醒配置
info "测试 PUT /api/reminder/config..."
SAVED=$(api PUT /reminder/config '{"work_duration":50,"rest_duration":10,"reminder_enabled":true}')
PASS_COUNT=$((PASS_COUNT + 1))
pass "保存提醒配置成功"

# 3. 开始工作
info "测试 POST /api/reminder/start-work..."
WORK=$(api POST /reminder/start-work)
PASS_COUNT=$((PASS_COUNT + 1))
pass "开始工作成功"

# 4. 开始休息
info "测试 POST /api/reminder/start-rest..."
REST=$(api POST /reminder/start-rest)
PASS_COUNT=$((PASS_COUNT + 1))
pass "开始休息成功"

# 5. 结束休息
info "测试 POST /api/reminder/end-rest..."
END_REST=$(api POST /reminder/end-rest)
PASS_COUNT=$((PASS_COUNT + 1))
pass "结束休息成功"

# 6. 跳过休息
info "测试 POST /api/reminder/skip-rest..."
# 先 start-work 再 skip
api POST /reminder/start-work > /dev/null 2>&1
SKIP=$(api POST /reminder/skip-rest)
PASS_COUNT=$((PASS_COUNT + 1))
pass "跳过休息成功"

# 7. 提醒统计
info "测试 GET /api/reminder/stats..."
STATS=$(api GET /reminder/stats)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取提醒统计成功"

# 8. 今日统计
info "测试 GET /api/reminder/today..."
TODAY=$(api GET /reminder/today)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取今日统计成功"

cleanup_user
print_summary
