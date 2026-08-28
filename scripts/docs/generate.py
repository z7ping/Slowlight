#!/usr/bin/env python3
"""从代码权威源生成 AI Agent 可读取的结构事实文档。"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GENERATED_DIR = ROOT / "docs" / "_generated"
AUTO_MARK = "<!-- AUTO-GENERATED: scripts/docs/generate.py；禁止手工修改 -->"


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def render_api_routes() -> str:
    source = ROOT / "server" / "cmd" / "main.go"
    pattern = re.compile(
        r'^\s*(r|api)\.(GET|POST|PUT|PATCH|DELETE)\("([^"]+)"', re.MULTILINE
    )
    rows: list[tuple[str, str]] = []
    for owner, method, path in pattern.findall(source.read_text(encoding="utf-8")):
        full_path = path if owner == "r" else f"/api{path}"
        rows.append((method, full_path))

    lines = [
        "# API 路由（自动生成）",
        "",
        AUTO_MARK,
        "",
        "权威源：`server/cmd/main.go`。本文件只描述实际注册的 HTTP 方法与路径。",
        "",
        "| 方法 | 路径 |",
        "|---|---|",
    ]
    lines.extend(f"| {method} | `{path}` |" for method, path in rows)
    lines.extend(["", f"共 {len(rows)} 条路由。", ""])
    return "\n".join(lines)


def parse_go_models() -> list[tuple[Path, str, list[tuple[str, str]]]]:
    models: list[tuple[Path, str, list[tuple[str, str]]]] = []
    start_re = re.compile(r"^type\s+(\w+)\s+struct\s*\{")
    field_re = re.compile(r"^\s*(\w+)\s+([^\s`]+)\s+`([^`]*)`")

    for path in sorted((ROOT / "server" / "internal" / "model").glob("*.go")):
        lines = path.read_text(encoding="utf-8").splitlines()
        i = 0
        while i < len(lines):
            match = start_re.match(lines[i])
            if not match:
                i += 1
                continue
            name = match.group(1)
            i += 1
            fields: list[tuple[str, str]] = []
            has_gorm = False
            while i < len(lines) and lines[i].strip() != "}":
                field = field_re.match(lines[i])
                if field:
                    field_name, go_type, tags = field.groups()
                    gorm_match = re.search(r'gorm:"([^"]*)"', tags)
                    gorm_value = gorm_match.group(1) if gorm_match else ""
                    if gorm_match:
                        has_gorm = True
                    if gorm_value != "-":
                        fields.append((field_name, go_type))
                i += 1
            if has_gorm:
                models.append((path, name, fields))
            i += 1
    return models


def parse_migrations() -> list[tuple[str, str]]:
    results: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    block_re = re.compile(r"AutoMigrate\s*\((.*?)\)", re.DOTALL)
    model_re = re.compile(r"&model\.(\w+)\{\}")

    for path in sorted((ROOT / "server").rglob("*.go")):
        text = path.read_text(encoding="utf-8")
        for block in block_re.findall(text):
            for model in model_re.findall(block):
                item = (model, rel(path))
                if item not in seen:
                    results.append(item)
                    seen.add(item)
    return results


def render_data_model() -> str:
    lines = [
        "# Go 数据模型（自动生成）",
        "",
        AUTO_MARK,
        "",
        "权威源：`server/internal/model/*.go`。只收录包含 GORM 标签的结构体；`gorm:\"-\"` 字段不列出。",
        "",
        "> 第一版稳定生成字段名与 Go 类型，用于阻止最常见的模型文档漂移；索引、长度、默认值等精确 GORM 约束仍以源代码为准。",
        "",
        "| Model | 来源 | 字段 |",
        "|---|---|---|",
    ]
    for path, name, fields in parse_go_models():
        field_text = "<br>".join(f"`{field}:{go_type}`" for field, go_type in fields)
        lines.append(f"| {name} | `{rel(path)}` | {field_text} |")

    lines.extend([
        "",
        "## 扫描到的 AutoMigrate",
        "",
        "| Model | 触发位置 |",
        "|---|---|",
    ])
    migrations = parse_migrations()
    lines.extend(f"| {model} | `{source}` |" for model, source in migrations)
    lines.extend(["", f"共扫描到 {len(migrations)} 个 Model/位置组合。", ""])
    return "\n".join(lines)


def parse_go_direct_dependencies() -> list[tuple[str, str]]:
    lines = read("server/go.mod").splitlines()
    deps: list[tuple[str, str]] = []
    in_block = False
    used_block = False
    for line in lines:
        stripped = line.strip()
        if stripped == "require (" and not used_block:
            in_block = True
            used_block = True
            continue
        if in_block and stripped == ")":
            break
        if in_block and stripped and not stripped.startswith("//"):
            parts = stripped.split()
            if len(parts) >= 2:
                deps.append((parts[0], parts[1]))
    return deps


def parse_pubspec_section(section: str) -> list[tuple[str, str]]:
    lines = read("client/pubspec.yaml").splitlines()
    deps: list[tuple[str, str]] = []
    in_section = False
    for line in lines:
        if line and not line.startswith(" "):
            if line.strip() == f"{section}:":
                in_section = True
                continue
            if in_section:
                break
        if in_section:
            match = re.match(r"^  ([A-Za-z0-9_]+):\s*(.*)$", line)
            if match:
                name, value = match.groups()
                deps.append((name, value.strip() or "SDK/嵌套配置"))
    return deps


def render_dependencies() -> str:
    lines = [
        "# 依赖清单（自动生成）",
        "",
        AUTO_MARK,
        "",
        "## Go 直接依赖",
        "",
        "权威源：`server/go.mod` 第一个 `require` 块。",
        "",
        "| 依赖 | 版本 |",
        "|---|---|",
    ]
    lines.extend(f"| `{name}` | `{version}` |" for name, version in parse_go_direct_dependencies())

    for section, title in (("dependencies", "Flutter 运行依赖"), ("dev_dependencies", "Flutter 开发依赖")):
        lines.extend(["", f"## {title}", "", f"权威源：`client/pubspec.yaml` 的 `{section}`。", "", "| 依赖 | 版本/来源 |", "|---|---|"])
        lines.extend(f"| `{name}` | `{version}` |" for name, version in parse_pubspec_section(section))
    lines.append("")
    return "\n".join(lines)


def server_env_vars() -> set[str]:
    pattern = re.compile(r'os\.Getenv\("([A-Z][A-Z0-9_]*)"\)')
    result: set[str] = set()
    for path in (ROOT / "server").rglob("*.go"):
        result.update(pattern.findall(path.read_text(encoding="utf-8")))
    return result


def example_env_vars() -> set[str]:
    pattern = re.compile(r"^([A-Z][A-Z0-9_]*)=", re.MULTILINE)
    return set(pattern.findall(read(".env.example")))


def render_project_meta() -> str:
    pubspec = read("client/pubspec.yaml")
    go_mod = read("server/go.mod")
    name = re.search(r"^name:\s*(.+)$", pubspec, re.MULTILINE).group(1).strip()
    version = re.search(r"^version:\s*(.+)$", pubspec, re.MULTILINE).group(1).strip()
    go_version = re.search(r"^go\s+(.+)$", go_mod, re.MULTILINE).group(1).strip()
    code_env = sorted(server_env_vars())
    example_env = example_env_vars()

    lines = [
        "# 项目元信息（自动生成）",
        "",
        AUTO_MARK,
        "",
        "| 项目 | 值 | 权威源 |",
        "|---|---|---|",
        f"| Flutter package | `{name}` | `client/pubspec.yaml` |",
        f"| 客户端版本 | `{version}` | `client/pubspec.yaml` |",
        f"| Go 版本 | `{go_version}` | `server/go.mod` |",
        "",
        "## 服务端环境变量",
        "",
        "从 `server/**/*.go` 的 `os.Getenv(...)` 自动扫描，并标记 `.env.example` 是否覆盖。",
        "",
        "| 环境变量 | `.env.example` |",
        "|---|---|",
    ]
    for key in code_env:
        status = "✅" if key in example_env else "❌ 缺失"
        lines.append(f"| `{key}` | {status} |")
    lines.append("")
    return "\n".join(lines)


def render_all() -> dict[Path, str]:
    return {
        GENERATED_DIR / "api-routes.md": render_api_routes(),
        GENERATED_DIR / "data-model.md": render_data_model(),
        GENERATED_DIR / "dependencies.md": render_dependencies(),
        GENERATED_DIR / "project-meta.md": render_project_meta(),
    }


def generate(check: bool = False) -> int:
    outputs = render_all()
    failures: list[str] = []
    for path, content in outputs.items():
        content = content.rstrip() + "\n"
        if check:
            if not path.exists():
                failures.append(f"缺少生成文件: {rel(path)}")
                continue
            current = path.read_text(encoding="utf-8")
            if current != content:
                failures.append(f"生成文件已过期: {rel(path)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
            print(f"generated {rel(path)}")

    if failures:
        for failure in failures:
            print(f"[docs] {failure}", file=sys.stderr)
        print("[docs] 请运行: python scripts/docs/generate.py", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只检查生成文件是否最新")
    args = parser.parse_args()
    return generate(check=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
