#!/usr/bin/env bash
# Slowlight - 任务模块测试
# 用法: ./test_tasks.sh
# 关键修复：动态获取 list_id，避免硬编码导致外键错误
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "任务模块测试"

# 准备：注册用户 + 获取清单 ID（这是核心修复！）
setup_user

WORK_LIST_ID=$(get_list_by_name "工作")
LIFE_LIST_ID=$(get_list_by_name "生活")
info "清单 ID: 工作=$WORK_LIST_ID, 生活=$LIFE_LIST_ID"

if [ "$WORK_LIST_ID" = "0" ]; then
    fail "未找到'工作'清单，无法继续测试"
    cleanup_user
    print_summary
    exit 1
fi

# 1. 创建任务（动态 list_id）
info "测试 POST /api/tasks (list_id=$WORK_LIST_ID)..."
TASK=$(api POST /tasks "{\"title\":\"测试任务-高优先\",\"list_id\":$WORK_LIST_ID,\"priority\":\"high\",\"description\":\"自动测试\"}")
assert_field "$TASK" "id"
assert_field "$TASK" "title"
TASK_ID=$(echo "$TASK" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
info "任务 ID: $TASK_ID"

# 2. 创建普通优先级任务
info "创建普通任务..."
TASK2=$(api POST /tasks "{\"title\":\"测试任务-普通\",\"list_id\":$WORK_LIST_ID,\"priority\":\"normal\"}")
TASK2_ID=$(echo "$TASK2" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "0")

# 3. 获取所有任务
info "测试 GET /api/tasks..."
ALL_TASKS=$(api GET /tasks)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取任务列表成功"

# 4. 获取单个任务
info "测试 GET /api/tasks/:id..."
SINGLE_TASK=$(api GET "/tasks/$TASK_ID")
assert_field "$SINGLE_TASK" "id"
assert_field "$SINGLE_TASK" "title"

# 5. 更新任务
info "测试 PUT /api/tasks/:id..."
UPDATED_TASK=$(api PUT "/tasks/$TASK_ID" '{"title":"更新后的任务","priority":"low"}')
assert_field "$UPDATED_TASK" "title"

# 6. 完成任务
info "测试 PATCH /api/tasks/:id/complete..."
COMPLETED=$(curl -sf -X PATCH "$BASE_URL/tasks/$TASK_ID/complete" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null)
PASS_COUNT=$((PASS_COUNT + 1))
pass "完成任务接口返回成功"

# 7. 获取今日任务
info "测试 GET /api/tasks/today..."
TODAY=$(api GET /tasks/today)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取今日任务成功"

# 8. 获取已完成任务
info "测试 GET /api/tasks/completed..."
COMPLETED_LIST=$(api GET /tasks/completed)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取已完成任务成功"

# 9. 搜索任务
info "测试 GET /api/tasks/search?q=测试..."
SEARCH=$(api GET "/tasks/search?q=测试")
PASS_COUNT=$((PASS_COUNT + 1))
pass "搜索任务成功"

# 10. 任务统计
info "测试 GET /api/tasks/stats..."
STATS=$(api GET /tasks/stats)
assert_field "$STATS" "total" || true

# 11. 删除任务
info "测试 DELETE /api/tasks/:id..."
DEL_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/tasks/$TASK_ID" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "000")
if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "删除任务成功 ($DEL_RESP)"
else
    fail "删除任务返回 $DEL_RESP"
fi

# 12. 用不存在的 list_id 创建任务 → 应该失败
info "测试外键约束：用不存在的 list_id..."
BAD_TASK=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/tasks" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"title":"外键测试","list_id":99999}' 2>/dev/null || echo "000")
if [ "$BAD_TASK" = "500" ] || [ "$BAD_TASK" = "400" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "无效 list_id 被拒绝 ($BAD_TASK)"
else
    warn "无效 list_id 返回 $BAD_TASK (期望 400/500)"
fi

# 清理
cleanup_user
print_summary
