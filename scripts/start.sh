#!/bin/bash
# Slowlight 后端服务启动脚本
# 用法: ./start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/../server"
PID_FILE="/tmp/slowlight-server.pid"
LOG_FILE="/tmp/slowlight-server.log"

# ========== 环境变量 ==========
# 数据库（从 server/.env 读取）
if [ -f "$SERVER_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$SERVER_DIR/.env"
    set +a
fi

export PORT="${PORT:-8080}"
if [ -z "${DATABASE_URL:-}" ]; then echo "DATABASE_URL is required" >&2; exit 1; fi

# ========== 停止旧进程 ==========
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "停止旧进程 PID=$OLD_PID ..."
        kill "$OLD_PID" 2>/dev/null
        sleep 1
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# 也清理残留进程
pkill -f "./slowlight-server" 2>/dev/null || true
sleep 1

# ========== 编译 ==========
echo "编译 Slowlight Server ..."
cd "$SERVER_DIR"
go build -o slowlight-server ./cmd/ 2>&1

# ========== 启动 ==========
echo "启动服务 (PORT=$PORT) ..."
nohup ./slowlight-server > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

# ========== 等待就绪 ==========
for i in $(seq 1 10); do
    if curl -s "http://localhost:$PORT/health" | grep -q '"ok"'; then
        echo "✅ Slowlight 服务已启动 (PID=$(cat $PID_FILE), port=$PORT)"
        exit 0
    fi
    sleep 1
done

echo "❌ 服务启动失败，查看日志: tail $LOG_FILE"
exit 1
