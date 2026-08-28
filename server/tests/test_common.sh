#!/usr/bin/env bash
# Slowlight 测试公共函数
# 所有测试脚本 source 此文件，统一配置和工具函数
set -euo pipefail

# ─── 配置 ───
BASE_URL="${SLOWLIGHT_API:-http://localhost:8088/api}"
DB_HOST="${DB_HOST:?请设置 DB_HOST 环境变量}"
DB_PORT="${DB_PORT:?请设置 DB_PORT 环境变量}"
DB_USER="${DB_USER:?请设置 DB_USER 环境变量}"
DB_PASS="${DB_PASS:?请设置 DB_PASS 环境变量}"
DB_NAME="${DB_NAME:?请设置 DB_NAME 环境变量}"

# ─── 颜色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── 全局状态 ───
TOKEN=""
USER_ID=""
TEST_USER="test_$(date +%s)"

# ─── 日志函数 ───
pass() { echo -e "${GREEN}[✓ PASS]${NC} $1"; }
fail() { echo -e "${RED}[✗ FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo -e "${YELLOW}[! WARN]${NC} $1"; }
info() { echo -e "${BLUE}[i INFO]${NC} $1"; }
section() { echo -e "\n${CYAN}══════ $1 ══════${NC}"; }

FAIL_COUNT=0
PASS_COUNT=0

# ─── HTTP 工具 ───
# 发送认证请求，自动带 token
# 用法: api METHOD PATH [JSON_BODY]
api() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sf -X "$method" "$BASE_URL$path" -H "Authorization: Bearer $TOKEN")
    if [ -n "$body" ]; then
        args+=(-H "Content-Type: application/json" -d "$body")
    fi
    curl "${args[@]}" 2>/dev/null
}

# 发送无认证请求
# 用法: pubapi METHOD PATH [JSON_BODY]
pubapi() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sf -X "$method" "$BASE_URL$path")
    if [ -n "$body" ]; then
        args+=(-H "Content-Type: application/json" -d "$body")
    fi
    curl "${args[@]}" 2>/dev/null
}

# 验证 JSON 字段是否存在
# 用法: assert_field RESPONSE FIELD_NAME
assert_field() {
    local resp="$1" field="$2"
    if echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$field' in d" 2>/dev/null; then
        PASS_COUNT=$((PASS_COUNT + 1))
        pass "$field 字段存在"
        return 0
    else
        fail "$field 字段缺失"
        return 1
    fi
}

# 验证 HTTP 状态码
# 用法: assert_status EXPECTED METHOD PATH [JSON_BODY]
assert_status() {
    local expected="$1" method="$2" path="$3" body="${4:-}"
    local args=(-o /dev/null -w "%{http_code}" -X "$method" "$BASE_URL$path")
    if [ -n "$TOKEN" ]; then
        args+=(-H "Authorization: Bearer $TOKEN")
    fi
    if [ -n "$body" ]; then
        args+=(-H "Content-Type: application/json" -d "$body")
    fi
    local actual
    actual=$(curl -sf "${args[@]}" 2>/dev/null || echo "000")
    if [ "$actual" = "$expected" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        pass "$method $path → $actual"
        return 0
    else
        fail "$method $path → 期望 $expected，实际 $actual"
        return 1
    fi
}

# ─── 注册+登录 ───
# 用法: setup_user [USERNAME] [PASSWORD]
setup_user() {
    local username="${1:-$TEST_USER}"
    local password="${2:-Test123456!}"
    local email="${username}@test.com"

    info "注册用户: $username"

    local resp
    resp=$(pubapi POST /auth/register "{\"username\":\"$username\",\"email\":\"$email\",\"password\":\"$password\"}" 2>/dev/null) || true

    if echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'token' in d" 2>/dev/null; then
        TOKEN=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
        pass "注册成功，获取 token"
    else
        # 可能已注册，尝试登录
        info "注册失败（可能已存在），尝试登录..."
        resp=$(pubapi POST /auth/login "{\"username\":\"$username\",\"password\":\"$password\"}" 2>/dev/null) || true
        if echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'token' in d" 2>/dev/null; then
            TOKEN=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
            pass "登录成功，获取 token"
        else
            fail "注册和登录都失败: $resp"
            return 1
        fi
    fi

    # 获取用户信息
    local profile
    profile=$(api GET /auth/profile 2>/dev/null) || true
    if [ -n "$profile" ]; then
        USER_ID=$(echo "$profile" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "0")
        info "用户 ID: $USER_ID"
    fi
}

# ─── 获取用户的第一个清单 ID ───
# 用法: get_first_list_id
get_first_list_id() {
    local lists
    lists=$(api GET /lists 2>/dev/null)
    echo "$lists" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    print(data[0]['id'])
else:
    print(0)
" 2>/dev/null || echo "0"
}

# ─── 按名字查找清单 ID ───
# 用法: get_list_by_name "工作"
get_list_by_name() {
    local name="$1"
    local lists
    lists=$(api GET /lists 2>/dev/null)
    echo "$lists" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for l in data:
    if l['name'] == '$name':
        print(l['id'])
        sys.exit(0)
print(0)
" 2>/dev/null || echo "0"
}

# ─── 清理测试用户 ───
cleanup_user() {
    if [ -n "$USER_ID" ] && [ "$USER_ID" != "0" ]; then
        info "清理测试用户 ID=$USER_ID..."
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -c "UPDATE users SET deleted_at = NOW() WHERE id = $USER_ID;" > /dev/null 2>&1 || true
    fi
}

# ─── 打印测试总结 ───
print_summary() {
    local total=$((PASS_COUNT + FAIL_COUNT))
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "  测试总结: ${GREEN}$PASS_COUNT 通过${NC} / ${RED}$FAIL_COUNT 失败${NC} / $total 总计"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}
