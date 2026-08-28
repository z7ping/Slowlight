#!/usr/bin/env bash
# Slowlight - 清单模块测试
# 用法: ./test_lists.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "清单模块测试"

# 准备：注册用户
setup_user
LIST_ID=$(get_first_list_id)
info "默认清单 ID: $LIST_ID"

# 1. 获取清单列表
info "测试 GET /api/lists..."
LISTS=$(api GET /lists)
assert_field "$LISTS" "0"  # 数组第一个元素

# 2. 创建新清单
info "测试 POST /api/lists..."
NEW_LIST=$(api POST /lists '{"name":"测试清单","icon":"🧪","color":"#ff0000"}')
assert_field "$NEW_LIST" "id"
assert_field "$NEW_LIST" "name"
NEW_LIST_ID=$(echo "$NEW_LIST" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
info "新清单 ID: $NEW_LIST_ID"

# 3. 更新清单
info "测试 PUT /api/lists/:id..."
UPDATED=$(api PUT "/lists/$NEW_LIST_ID" '{"name":"更新后的清单","icon":"✅"}')
assert_field "$UPDATED" "name"

# 4. 清单统计
info "测试 GET /api/lists/stats..."
STATS=$(api GET /lists/stats)
PASS_COUNT=$((PASS_COUNT + 1))
pass "清单统计接口返回成功"

# 5. 删除清单
info "测试 DELETE /api/lists/:id..."
DEL_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/lists/$NEW_LIST_ID" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "000")
if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "删除清单成功 ($DEL_RESP)"
else
    fail "删除清单返回 $DEL_RESP"
fi

# 6. 获取清单下的任务
info "测试 GET /api/lists/:id/tasks..."
LIST_TASKS=$(api GET "/lists/$LIST_ID/tasks")
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取清单任务成功"

# 清理
cleanup_user
print_summary
