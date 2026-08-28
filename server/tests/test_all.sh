#!/usr/bin/env bash
# Slowlight - 全量测试运行器
# 用法: ./test_all.sh [模块名...]
# 无参数运行全部模块
# 示例: ./test_all.sh auth tasks lists
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ALL_MODULES=(auth lists tasks tags subtasks sessions reminders habits feishu)
MODULES=("${@:-${ALL_MODULES[@]}}")

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
FAILED_MODULES=()

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║       Slowlight API 全量测试                  ║"
echo "║       $(date '+%Y-%m-%d %H:%M:%S')                      ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# 检查后端是否运行
echo -n "检查后端服务... "
if curl -sf http://localhost:8088/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 运行中${NC}"
else
    echo -e "${RED}✗ 未运行${NC}"
    echo "请先启动后端: cd server && ./slowlight"
    exit 1
fi

START_TIME=$(date +%s)

for mod in "${MODULES[@]}"; do
    SCRIPT="$SCRIPT_DIR/test_${mod}.sh"
    if [ ! -f "$SCRIPT" ]; then
        echo -e "${YELLOW}[SKIP]${NC} test_${mod}.sh 不存在"
        TOTAL_SKIP=$((TOTAL_SKIP + 1))
        continue
    fi

    echo ""
    echo -e "${BOLD}┌─────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│  运行: test_${mod}.sh${NC}"
    echo -e "${BOLD}└─────────────────────────────────────────┘${NC}"

    OUTPUT=$(bash "$SCRIPT" 2>&1) || true
    echo "$OUTPUT"

    # 提取通过/失败数
    P=$(echo "$OUTPUT" | grep -c "\[✓ PASS\]" || true)
    F=$(echo "$OUTPUT" | grep -c "\[✗ FAIL\]" || true)
    TOTAL_PASS=$((TOTAL_PASS + P))
    TOTAL_FAIL=$((TOTAL_FAIL + F))

    if [ "$F" -gt 0 ]; then
        FAILED_MODULES+=("$mod")
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║             全量测试结果                      ║"
echo "╠══════════════════════════════════════════════╣"
printf "║  ${GREEN}通过: %-4d${NC}${BOLD}${CYAN}  ${RED}失败: %-4d${NC}${BOLD}${CYAN}  跳过: %-4d${NC}${BOLD}${CYAN}     ║\n" \
    "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_SKIP"
echo "║  耗时: ${DURATION}s                                    ║"
echo "╠══════════════════════════════════════════════╣"
if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
    echo -e "║  ${RED}失败模块: ${FAILED_MODULES[*]}${NC}${BOLD}${CYAN}"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    exit 1
else
    echo -e "║  ${GREEN}全部通过 ✓${NC}${BOLD}${CYAN}"
    echo "╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
    exit 0
fi
