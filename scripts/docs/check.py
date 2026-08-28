#!/usr/bin/env python3
"""检查 Slowlight 公开仓库中的生成文档与相对链接一致性。"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import generate

ROOT = Path(__file__).resolve().parents[2]


def check_generated() -> list[str]:
    return [] if generate.generate(check=True) == 0 else ["自动生成文档与当前代码不一致"]


def check_env_example() -> list[str]:
    code_env = generate.server_env_vars()
    example_env = generate.example_env_vars()
    errors: list[str] = []
    missing = sorted(code_env - example_env)
    if missing:
        errors.append(".env.example 缺少代码实际读取的环境变量: " + ", ".join(missing))
    stale = sorted(example_env - code_env)
    if stale:
        print("[docs][warn] .env.example 中存在代码未扫描到的变量: " + ", ".join(stale))
    return errors


def public_markdown_files() -> list[Path]:
    files: set[Path] = set()

    for name in (
        "README.md",
        "ROADMAP.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "CHANGELOG.md",
        "AGENTS.md",
        "CLAUDE.md",
    ):
        path = ROOT / name
        if path.exists():
            files.add(path)

    for base in (
        ROOT / "docs",
        ROOT / "server" / "docs",
        ROOT / "assets" / "brand" / "slowlight",
    ):
        if base.is_dir():
            files.update(base.rglob("*.md"))

    server_readme = ROOT / "server" / "README.md"
    if server_readme.exists():
        files.add(server_readme)

    return sorted(files)


def check_markdown_links() -> list[str]:
    errors: list[str] = []
    link_re = re.compile(r"\[[^\]]*\]\(([^)]+)\)")

    for path in public_markdown_files():
        text = path.read_text(encoding="utf-8")
        for target in link_re.findall(text):
            target = target.strip()
            if not target or target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            clean = target.split("#", 1)[0]
            if not clean:
                continue
            resolved = (path.parent / clean).resolve()
            try:
                resolved.relative_to(ROOT.resolve())
            except ValueError:
                errors.append(f"{path.relative_to(ROOT)}: 链接越出仓库 {target}")
                continue
            if not resolved.exists():
                errors.append(f"{path.relative_to(ROOT)}: 无效相对链接 {target}")
    return errors


def check_generated_markers() -> list[str]:
    errors: list[str] = []
    generated_dir = ROOT / "docs" / "_generated"
    if not generated_dir.is_dir():
        return ["缺少 docs/_generated 目录"]
    for path in generated_dir.glob("*.md"):
        if generate.AUTO_MARK not in path.read_text(encoding="utf-8"):
            errors.append(f"{path.relative_to(ROOT)} 缺少自动生成标记")
    return errors


def main() -> int:
    errors: list[str] = []
    errors.extend(check_generated())
    errors.extend(check_env_example())
    errors.extend(check_markdown_links())
    errors.extend(check_generated_markers())

    if errors:
        print("\n[docs] 公开文档一致性检查失败：", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("[docs] 公开文档与生成工程事实检查通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
