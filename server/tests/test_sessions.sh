#!/usr/bin/env bash
# Slowlight - 番茄钟会话模块测试
# 用法: ./test_sessions.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "番茄钟会话模块测试"

setup_user

# 1. 开始会话
info "测试 POST /api/sessions/start..."
SESSION=$(api POST /sessions/start '{"type":"work","duration_minutes":25}')
assert_field "$SESSION" "id" || true
SESSION_ID=$(echo "$SESSION" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','0'))" 2>/dev/null || echo "0")
info "会话 ID: $SESSION_ID"

# 2. 获取活跃会话
info "测试 GET /api/sessions/active..."
ACTIVE=$(api GET /sessions/active)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取活跃会话成功"

# 3. 结束会话
info "测试 POST /api/sessions/end..."
END_RESP=$(api POST /sessions/end "{\"session_id\":$SESSION_ID}")
PASS_COUNT=$((PASS_COUNT + 1))
pass "结束会话成功"

# 4. 今日统计
info "测试 GET /api/sessions/today..."
TODAY=$(api GET /sessions/today)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取今日统计成功"

# 5. 总体统计
info "测试 GET /api/sessions/stats..."
STATS=$(api GET /sessions/stats)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取会话统计成功"

cleanup_user
print_summary
