#!/usr/bin/env sh
# Deploy from a Git checkout so the running image can report its source.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "需要在 Git 检出目录运行，以记录准确的代码版本" >&2
  exit 1
fi
if [ -n "$(git -C "$ROOT" status --porcelain -- server client/pubspec.yaml)" ]; then
  echo "服务端源码或版本文件存在未提交修改，无法确认部署 SHA" >&2
  exit 1
fi
export SLOWLIGHT_APP_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/client/pubspec.yaml" | head -n 1 | cut -d+ -f1)"
export SLOWLIGHT_GIT_HASH="$(git -C "$ROOT" rev-parse HEAD)"
export SLOWLIGHT_GIT_TIME="$(git -C "$ROOT" show -s --format=%cI HEAD)"
export SLOWLIGHT_BUILD_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export SLOWLIGHT_DEPLOYED_AT="$SLOWLIGHT_BUILD_AT"
if [ -z "$SLOWLIGHT_APP_VERSION" ] || [ -z "$SLOWLIGHT_GIT_HASH" ]; then
  echo "版本与 Git 提交信息不可用，已取消部署" >&2
  exit 1
fi

cd "$SCRIPT_DIR"
exec docker compose up -d --build "$@"
