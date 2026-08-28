#!/usr/bin/env bash
# Slowlight - 标签模块测试
# 用法: ./test_tags.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "标签模块测试"

setup_user
WORK_LIST_ID=$(get_list_by_name "工作")

# 1. 创建标签
info "测试 POST /api/tags..."
TAG=$(api POST /tags '{"name":"紧急","color":"#ff0000","icon":"🔥"}')
assert_field "$TAG" "id"
TAG_ID=$(echo "$TAG" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
info "标签 ID: $TAG_ID"

# 2. 获取标签列表
info "测试 GET /api/tags..."
TAGS=$(api GET /tags)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取标签列表成功"

# 3. 更新标签
info "测试 PUT /api/tags/:id..."
UPDATED=$(api PUT "/tags/$TAG_ID" '{"name":"紧急-更新","color":"#ff4444"}')
assert_field "$UPDATED" "name"

# 4. 标签统计
info "测试 GET /api/tags/stats..."
STATS=$(api GET /tags/stats)
PASS_COUNT=$((PASS_COUNT + 1))
pass "标签统计成功"

# 5. 创建带标签的任务
info "创建带标签的任务..."
TASK=$(api POST /tasks "{\"title\":\"带标签任务\",\"list_id\":$WORK_LIST_ID,\"tag_ids\":[$TAG_ID]}")
TASK_ID=$(echo "$TASK" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "0")
if [ "$TASK_ID" != "0" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "创建带标签任务成功"
fi

# 6. 获取标签下的任务
info "测试 GET /api/tags/:id/tasks..."
TAG_TASKS=$(api GET "/tags/$TAG_ID/tasks")
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取标签任务成功"

# 7. 删除标签
info "测试 DELETE /api/tags/:id..."
DEL_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/tags/$TAG_ID" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "000")
if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "删除标签成功 ($DEL_RESP)"
else
    fail "删除标签返回 $DEL_RESP"
fi

# 清理
[ "$TASK_ID" != "0" ] && curl -sf -X DELETE "$BASE_URL/tasks/$TASK_ID" -H "Authorization: Bearer $TOKEN" > /dev/null 2>&1
cleanup_user
print_summary
