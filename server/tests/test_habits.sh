#!/usr/bin/env bash
# Slowlight - 习惯打卡模块测试
# 用法: ./test_habits.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "习惯打卡模块测试"

setup_user

# 1. 创建习惯
info "测试 POST /api/habits..."
HABIT=$(api POST /habits '{"name":"晨跑","icon":"🏃","color":"#52c41a","frequency":"daily","target_count":1}')
assert_field "$HABIT" "id"
HABIT_ID=$(echo "$HABIT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
info "习惯 ID: $HABIT_ID"

# 2. 获取习惯列表
info "测试 GET /api/habits..."
HABITS=$(api GET /habits)
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取习惯列表成功"

# 3. 更新习惯
info "测试 PUT /api/habits/:id..."
UPDATED=$(api PUT "/habits/$HABIT_ID" '{"name":"晨跑-更新","frequency":"daily"}')
assert_field "$UPDATED" "name"

# 4. 习惯打卡
info "测试 POST /api/habits/:id/checkin..."
CHECKIN=$(api POST "/habits/$HABIT_ID/checkin")
PASS_COUNT=$((PASS_COUNT + 1))
pass "习惯打卡成功"

# 5. 获取打卡记录
info "测试 GET /api/habits/:id/logs..."
LOGS=$(api GET "/habits/$HABIT_ID/logs")
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取打卡记录成功"

# 6. 获取连续打卡天数
info "测试 GET /api/habits/:id/streak..."
STREAK=$(api GET "/habits/$HABIT_ID/streak")
PASS_COUNT=$((PASS_COUNT + 1))
pass "获取连续打卡成功"

# 7. 删除习惯
info "测试 DELETE /api/habits/:id..."
DEL_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/habits/$HABIT_ID" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "000")
if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "删除习惯成功 ($DEL_RESP)"
else
    fail "删除习惯返回 $DEL_RESP"
fi

cleanup_user
print_summary
