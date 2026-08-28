#!/usr/bin/env python3
"""发布版本门禁：校验 Tag、pubspec 与 CHANGELOG 一致。"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TAG_RE = re.compile(
    r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def fail(message: str) -> int:
    print(f"[release-docs] {message}", file=sys.stderr)
    return 1


def main() -> int:
    if len(sys.argv) != 2:
        return fail("用法: python scripts/docs/release_check.py v0.2.0 或 v0.2.0-beta.1")

    tag = sys.argv[1].strip()
    if not TAG_RE.fullmatch(tag):
        return fail(f"Tag 格式不符合 vX.Y.Z 或 vX.Y.Z-prerelease: {tag}")

    pubspec = (ROOT / "client" / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([^\s]+)\s*$", pubspec, re.MULTILINE)
    if not match:
        return fail("client/pubspec.yaml 中未找到 version")

    client_version = match.group(1)
    release_version = client_version.split("+", 1)[0]
    expected_tag = f"v{release_version}"
    if tag != expected_tag:
        return fail(
            f"Tag 与客户端版本不一致: tag={tag}, pubspec={client_version}, 期望 {expected_tag}"
        )

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if not re.search(rf"^##\s+\[{re.escape(tag)}\](?:\s+-|\s*$)", changelog, re.MULTILINE):
        return fail(f"CHANGELOG.md 缺少 {tag} 版本段")

    print(f"[release-docs] 发布版本一致: tag={tag}, pubspec={client_version}, CHANGELOG 已覆盖")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
