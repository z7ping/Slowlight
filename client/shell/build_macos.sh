#!/bin/bash
# Slowlight macOS 构建
# 运行环境：安装了 Flutter 与 Xcode 的 macOS 机器
# 前置：Flutter, Xcode

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
  echo "✗ macOS 构建只能在 macOS 宿主机执行"
  exit 1
fi

require_command flutter
require_command zip
require_command awk
require_command cut

VERSION="${1:-$(awk '/^version:/ {print $2}' "$PROJECT_ROOT/pubspec.yaml" | cut -d+ -f1)}"

if ! flutter --version >/dev/null; then
  echo "✗ Flutter 当前不可用，请先完成 macOS 与 Xcode 工具链配置"
  exit 1
fi

echo "═══════════════════════════════════════"
echo " Slowlight macOS Build"
echo " Version: $VERSION"
echo "═══════════════════════════════════════"

cd "$PROJECT_ROOT"

flutter build macos --release

OUT="$PROJECT_ROOT/build/macos/Build/Products/Release"
if [ ! -d "$OUT" ]; then
  echo "✗ 构建结束但未找到 macOS Release 目录: $OUT"
  exit 1
fi
echo ""
echo "✓ macOS: $OUT"

# 打包
ARCHIVE="$PROJECT_ROOT/build/slowlight-macos-${VERSION}.zip"
cd "$OUT"
zip -r "$ARCHIVE" .
if [ ! -s "$ARCHIVE" ]; then
  echo "✗ macOS 压缩包生成失败: $ARCHIVE"
  exit 1
fi
echo "✓ Archive: $ARCHIVE"
echo "  可通过 GitHub Actions 发布，或使用 release.sh 上传到已有 GitHub tag"
