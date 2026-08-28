#!/bin/bash
# 向已有 GitHub tag 创建预发布版本或上传制品
# 用法：./release.sh <制品路径> <tag>

set -euo pipefail

ARTIFACT="${1:?用法: $0 <制品路径> <tag>}"
TAG="${2:?用法: $0 <制品路径> <tag>}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "✗ 缺少必要命令: $1"
    exit 1
  fi
}

if [ ! -f "$ARTIFACT" ]; then
  echo "✗ 文件不存在: $ARTIFACT"
  exit 1
fi

require_command gh
require_command git
require_command du
require_command cut

if ! gh auth status >/dev/null 2>&1; then
  echo "✗ GitHub CLI 尚未登录，请先运行 gh auth login"
  exit 1
fi

REPO_ARGS=()
if [ -n "${GH_REPO:-}" ]; then
  REPO_ARGS=(--repo "$GH_REPO")
elif ! gh repo view >/dev/null 2>&1; then
  echo "✗ 无法从当前 Git 仓库识别 GitHub 远程；请先配置远程或设置 GH_REPO=owner/repository"
  exit 1
fi

if ! git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "✗ 本地不存在 tag: $TAG"
  exit 1
fi

SIZE=$(du -h "$ARTIFACT" | cut -f1)
echo "═══════════════════════════════════════"
echo " Slowlight Release"
echo " Tag: $TAG"
echo " Artifact: $ARTIFACT ($SIZE)"
echo "═══════════════════════════════════════"

if gh release view "$TAG" "${REPO_ARGS[@]}" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ARTIFACT" "${REPO_ARGS[@]}" --clobber
else
  gh release create "$TAG" "$ARTIFACT" "${REPO_ARGS[@]}" \
    --verify-tag \
    --title "Slowlight $TAG · 预览版" \
    --prerelease \
    --generate-notes
fi

echo "✓ GitHub Release 制品已上传"
