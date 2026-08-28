#!/bin/bash
# Slowlight API 快速测试脚本
# 用法: ./test_api.sh [端点路径]
# 示例: ./test_api.sh /api/analytics/daily-trend

BASE="http://localhost:8088"
USER="api_tester"
PASS="test123456"
TOKEN_FILE="/tmp/.slowlight_test_token"

# 自动注册 + 获取 token（有缓存）
get_token() {
  if [ -f "$TOKEN_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$TOKEN_FILE" 2>/dev/null || echo 0))) -lt 3600 ]; then
    cat "$TOKEN_FILE"
    return
  fi
  # 尝试登录
  TOKEN=$(curl -s -X POST "$BASE/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}" \
    | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$TOKEN" ]; then
    # 登录失败，注册
    TOKEN=$(curl -s -X POST "$BASE/api/auth/register" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$USER\",\"email\":\"${USER}@test.com\",\"password\":\"$PASS\",\"nickname\":\"测试用户\"}" \
      | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  fi

  if [ -n "$TOKEN" ]; then
    echo "$TOKEN" > "$TOKEN_FILE"
    echo "$TOKEN"
  else
    echo "ERROR: 获取 token 失败" >&2
    exit 1
  fi
}

TOKEN=$(get_token)

# 如果没传参数，列出常用端点
if [ -z "$1" ]; then
  echo "用法: $0 <端点路径>"
  echo ""
  echo "常用端点:"
  echo "  /api/lists"
  echo "  /api/tasks/today"
  echo "  /api/habits"
  echo "  /api/system-tags"
  echo "  /api/review/today"
  echo "  /api/analytics/daily-trend"
  echo "  /api/analytics/weekly-review"
  echo "  /api/analytics/output"
  echo "  /api/auth/profile"
  exit 0
fi

curl -s "$BASE$1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | python3 -m json.tool 2>/dev/null || \
curl -s "$BASE$1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"
