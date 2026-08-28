#!/bin/bash
# Slowlight Android 构建
# 运行环境：安装了 Flutter 与 Android SDK 的机器
# 前置：Android SDK, Flutter

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_URL="${SERVER_URL:-http://localhost:8080/api}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "✗ 缺少必要命令: $1"
    exit 1
  fi
}

require_command flutter
require_command du
require_command awk
require_command cut

VERSION="${1:-$(awk '/^version:/ {print $2}' "$PROJECT_ROOT/pubspec.yaml" | cut -d+ -f1)}"

if ! flutter --version >/dev/null; then
  echo "✗ Flutter 当前不可用，请先完成 Flutter 与 Android SDK 配置"
  exit 1
fi

echo "═══════════════════════════════════════"
echo " Slowlight Android Build"
echo " Server: $SERVER_URL"
echo " Version: $VERSION"
echo "═══════════════════════════════════════"

cd "$PROJECT_ROOT"

flutter build apk --release \
  --dart-define=SERVER_URL="$SERVER_URL"

APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK" ]; then
  echo "✗ 构建结束但未找到 APK: $APK"
  exit 1
fi
SIZE=$(du -h "$APK" | cut -f1)
echo ""
echo "✓ APK: $APK ($SIZE)"
echo "  可通过 GitHub Actions 发布，或使用 release.sh 上传到已有 GitHub tag"
