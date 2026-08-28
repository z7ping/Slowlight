#!/usr/bin/env bash
# Windows 构建兼容入口；正式入口为 build_windows.ps1。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-}"
SERVER_URL="${SERVER_URL:-http://localhost:8080/api}"

if command -v pwsh.exe >/dev/null 2>&1; then
  POWERSHELL_COMMAND="pwsh.exe"
elif command -v pwsh >/dev/null 2>&1; then
  POWERSHELL_COMMAND="pwsh"
else
  echo "✗ 未找到 PowerShell 7。请在 Windows 中直接运行 build_windows.ps1"
  exit 1
fi

PS_SCRIPT="$SCRIPT_DIR/build_windows.ps1"
if command -v wslpath >/dev/null 2>&1 && [ "$POWERSHELL_COMMAND" = "pwsh.exe" ]; then
  PS_SCRIPT="$(wslpath -w "$PS_SCRIPT")"
fi

ARGS=(-NoProfile -File "$PS_SCRIPT" -ServerUrl "$SERVER_URL")
if [ -n "$VERSION" ]; then
  ARGS+=(-Version "$VERSION")
fi

"$POWERSHELL_COMMAND" "${ARGS[@]}"
