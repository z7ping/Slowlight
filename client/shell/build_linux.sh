#!/bin/bash
# Slowlight Linux 桌面版构建
# 运行环境：安装了 Flutter 与 GTK3 的 Linux 机器
# 前置：Flutter, GTK3

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_URL="${SERVER_URL:-http://localhost:8080/api}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "✗ 缺少必要命令: $1"
    exit 1
  fi
}

require_command uname

if [ "$(uname -s)" != "Linux" ]; then
  echo "✗ Linux 桌面构建只能在 Linux 宿主机执行"
  exit 1
fi

require_command flutter
require_command du
require_command tar
require_command awk
require_command cut

VERSION="${1:-$(awk '/^version:/ {print $2}' "$PROJECT_ROOT/pubspec.yaml" | cut -d+ -f1)}"

if ! flutter --version >/dev/null; then
  echo "✗ Flutter 当前不可用，请先完成 Linux 桌面工具链配置"
  exit 1
fi

echo "═══════════════════════════════════════"
echo " Slowlight Linux Build"
echo " Server: $SERVER_URL"
echo " Version: $VERSION"
echo "═══════════════════════════════════════"

cd "$PROJECT_ROOT"

flutter build linux --release \
  --dart-define=SERVER_URL="$SERVER_URL"

case "$(uname -m)" in
  x86_64|amd64) FLUTTER_ARCH="x64" ;;
  aarch64|arm64) FLUTTER_ARCH="arm64" ;;
  *)
    echo "✗ 暂不支持的 Linux 架构: $(uname -m)"
    exit 1
    ;;
esac

OUT="$PROJECT_ROOT/build/linux/$FLUTTER_ARCH/release/bundle"
if [ ! -d "$OUT" ]; then
  echo "✗ 构建结束但未找到 Linux Bundle: $OUT"
  exit 1
fi
SIZE=$(du -sh "$OUT" | cut -f1)
echo ""
echo "✓ Linux: $OUT ($SIZE)"

# 打包
ARCHIVE="$PROJECT_ROOT/build/slowlight-linux-${VERSION}.tar.gz"
cd "$PROJECT_ROOT/build/linux/$FLUTTER_ARCH/release"
tar czf "$ARCHIVE" bundle/
if [ ! -s "$ARCHIVE" ]; then
  echo "✗ Linux 压缩包生成失败: $ARCHIVE"
  exit 1
fi
echo "✓ Archive: $ARCHIVE"
echo "  可通过 GitHub Actions 发布，或使用 release.sh 上传到已有 GitHub tag"
