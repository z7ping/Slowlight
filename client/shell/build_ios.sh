#!/bin/bash
# Slowlight iOS 构建
# 运行环境：安装了 Flutter 与 Xcode 的 macOS 机器
# 前置：Flutter, Xcode, Apple Developer 账号

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "✗ 缺少必要命令: $1"
    exit 1
  fi
}

require_command uname

if [ "$(uname -s)" != "Darwin" ]; then
  echo "✗ iOS 构建只能在 macOS 宿主机执行"
  exit 1
fi

require_command flutter
require_command awk
require_command cut

VERSION="${1:-$(awk '/^version:/ {print $2}' "$PROJECT_ROOT/pubspec.yaml" | cut -d+ -f1)}"

if ! flutter --version >/dev/null; then
  echo "✗ Flutter 当前不可用，请先完成 iOS 与 Xcode 工具链配置"
  exit 1
fi

echo "═══════════════════════════════════════"
echo " Slowlight iOS Build"
echo " Version: $VERSION"
echo "═══════════════════════════════════════"

cd "$PROJECT_ROOT"

# 构建 IPA
flutter build ios --release --no-codesign

APP="$PROJECT_ROOT/build/ios/iphoneos/Runner.app"
if [ ! -d "$APP" ]; then
  echo "✗ 构建结束但未找到 iOS App: $APP"
  exit 1
fi

echo ""
echo "✓ iOS 构建完成"
echo "  App: $APP"
echo "  Xcode 打开 ios/Runner.xcworkspace"
echo "  Product → Archive → Distribute App"
