#!/usr/bin/env bash
# Slowlight - 子任务模块测试
# 用法: ./test_subtasks.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "子任务模块测试"

setup_user
WORK_LIST_ID=$(get_list_by_name "工作")

# 创建父任务
PARENT=$(api POST /tasks "{\"title\":\"父任务\",\"list_id\":$WORK_LIST_ID}")
PARENT_ID=$(echo "$PARENT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
info "父任务 ID: $PARENT_ID"

# 1. 创建子任务
info "测试 POST /api/tasks/:id/subtasks..."
SUB=$(api POST "/tasks/$PARENT_ID/subtasks" '{"title":"子任务1","sort_order":1}')
assert_field "$SUB" "id"
SUB_ID=$(echo "$SUB" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
info "子任务 ID: $SUB_ID"

# 2. 获取子任务列表
info "测试 GET /api/tasks/:id/subtasks..."
SUBS=$(api GET "/tasks/$PARENT_ID/subtasks")
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取子任务列表成功"

# 3. 更新子任务
info "测试 PUT /api/tasks/:id/subtasks/:subtaskId..."
UPDATED=$(api PUT "/tasks/$PARENT_ID/subtasks/$SUB_ID" '{"title":"更新后的子任务"}')
assert_field "$UPDATED" "title"

# 4. 切换子任务完成状态
info "测试 PATCH /api/tasks/:id/subtasks/:subtaskId/toggle..."
TOGGLED=$(curl -sf -X PATCH "$BASE_URL/tasks/$PARENT_ID/subtasks/$SUB_ID/toggle" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null)
PASS_COUNT=$((PASS_COUNT + 1))
pass "切换子任务状态成功"

# 5. 获取子任务进度
info "测试 GET /api/tasks/:id/subtasks/progress..."
PROGRESS=$(api GET "/tasks/$PARENT_ID/subtasks/progress")
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取子任务进度成功"

# 6. 删除子任务
info "测试 DELETE /api/tasks/:id/subtasks/:subtaskId..."
DEL_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/tasks/$PARENT_ID/subtasks/$SUB_ID" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "000")
if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "删除子任务成功 ($DEL_RESP)"
else
    fail "删除子任务返回 $DEL_RESP"
fi

# 清理
curl -sf -X DELETE "$BASE_URL/tasks/$PARENT_ID" -H "Authorization: Bearer $TOKEN" > /dev/null 2>&1
cleanup_user
print_summary
