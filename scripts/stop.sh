#!/bin/bash
# Slowlight 后端服务停止脚本

PID_FILE="/tmp/slowlight-server.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        echo "✅ 已停止 PID=$PID"
        rm -f "$PID_FILE"
    else
        echo "进程已不存在，清理 PID 文件"
        rm -f "$PID_FILE"
    fi
else
    pkill -f "./slowlight-server" && echo "✅ 已停止" || echo "没有运行中的服务"
fi
