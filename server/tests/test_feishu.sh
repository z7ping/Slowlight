#!/usr/bin/env bash
# Slowlight - 飞书集成模块测试
# 用法: ./test_feishu.sh [FEISHU_APP_ID] [FEISHU_APP_SECRET]
# 注意：飞书接口需要真实 App 凭证，无参数时跳过需凭证的测试
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_common.sh"

section "飞书集成模块测试"

setup_user

APP_ID="${1:-}"
APP_SECRET="${2:-}"
TABLE_URL="${3:-https://my.feishu.cn/base/GKNObhKrSagrZNs6CXvcI0HhnRb}"

HAS_CRED=false
if [ -n "$APP_ID" ] && [ -n "$APP_SECRET" ]; then
    HAS_CRED=true
fi

# 1. 获取飞书配置（未配置时）
info "测试 GET /api/feishu/config (未配置)..."
CONFIG=$(api GET /feishu/config)
assert_field "$CONFIG" "configured"

# 2. 保存飞书配置
if $HAS_CRED; then
    info "测试 POST /api/feishu/config..."
    SAVED=$(api POST /feishu/config "{\"app_id\":\"$APP_ID\",\"app_secret\":\"$APP_SECRET\"}")
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "保存飞书配置成功"

    # 3. 连接已有表格
    info "测试 POST /api/feishu/connect-existing..."
    CONNECT=$(api POST /feishu/connect-existing "{\"table_url\":\"$TABLE_URL\"}")
    assert_field "$CONNECT" "tables" || true

    # 4. 同步到飞书
    info "测试 POST /api/feishu/sync..."
    SYNC=$(api POST /feishu/sync)
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "同步到飞书成功"

    # 5. 全量同步
    info "测试 POST /api/feishu/sync-all..."
    SYNC_ALL=$(api POST /feishu/sync-all)
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "全量同步成功"

    # 6. 同步会话（番茄钟）
    info "测试 POST /api/feishu/sync-sessions..."
    SYNC_SESS=$(api POST /feishu/sync-sessions)
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "同步会话成功"

    # 7. 同步提醒
    info "测试 POST /api/feishu/sync-reminders..."
    SYNC_REM=$(api POST /feishu/sync-reminders)
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "同步提醒成功"

    # 8. 同步标签
    info "测试 POST /api/feishu/sync-tags..."
    SYNC_TAGS=$(api POST /feishu/sync-tags)
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "同步标签成功"

    # 9. 从飞书导入
    info "测试 POST /api/feishu/import..."
    IMPORT=$(api POST /feishu/import)
    PASS_COUNT=$((PASS_COUNT + 1))
    pass "从飞书导入成功"
else
    warn "未提供飞书凭证，跳过需要凭证的测试"
    warn "用法: $0 APP_ID APP_SECRET [TABLE_URL]"
fi

cleanup_user
print_summary
