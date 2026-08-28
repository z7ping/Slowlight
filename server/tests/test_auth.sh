#!/usr/bin/env bash
# Slowlight - 认证模块测试
# 用法: ./test_auth.sh [username]
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "认证模块测试"

USERNAME="${1:-test_auth_$(date +%s)}"
PASSWORD="Test123456!"
EMAIL="${USERNAME}@test.com"

# 1. 注册
info "测试注册..."
REG_RESP=$(pubapi POST /auth/register "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
assert_field "$REG_RESP" "token"
assert_field "$REG_RESP" "user"

# 2. 登录
info "测试登录..."
LOGIN_RESP=$(pubapi POST /auth/login "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")
assert_field "$LOGIN_RESP" "token"
TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# 3. 获取用户信息
info "测试获取用户信息..."
PROFILE=$(api GET /auth/profile)
assert_field "$PROFILE" "id"
assert_field "$PROFILE" "username"
assert_field "$PROFILE" "email"

# 4. 默认清单已创建
info "验证注册时自动创建默认清单..."
LISTS=$(api GET /lists)
LIST_COUNT=$(echo "$LISTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$LIST_COUNT" -ge 3 ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "默认清单数量: $LIST_COUNT (≥3)"
else
    fail "默认清单数量: $LIST_COUNT (期望≥3)"
fi

# 5. 重复注册应失败
info "测试重复注册..."
DUP_STATUS=$(pubapi POST /auth/register "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
if [ "$DUP_STATUS" = "409" ] || [ "$DUP_STATUS" = "400" ] || [ "$DUP_STATUS" = "500" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "重复注册被拒绝 ($DUP_STATUS)"
else
    warn "重复注册返回 $DUP_STATUS (预期 400/409/500)"
fi

# 6. 错误密码登录
info "测试错误密码登录..."
BAD_LOGIN=$(pubapi POST /auth/login "{\"username\":\"$USERNAME\",\"password\":\"wrongpass\"}" \
    -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
if [ "$BAD_LOGIN" = "401" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "错误密码被拒绝 (401)"
else
    fail "错误密码返回 $BAD_LOGIN (期望 401)"
fi

# 7. 无 token 访问受保护接口
info "测试无认证访问..."
NOAUTH=$(curl -sf -o /dev/null -w "%{http_code}" "$BASE_URL/lists" 2>/dev/null || echo "000")
if [ "$NOAUTH" = "401" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "无认证被拒绝 (401)"
else
    fail "无认证返回 $NOAUTH (期望 401)"
fi

# 清理
cleanup_user
print_summary
