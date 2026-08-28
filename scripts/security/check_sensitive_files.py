#!/usr/bin/env python3
"""Fail when tracked files contain credentials or private environment traces."""

from __future__ import annotations

import ipaddress
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SELF_PATH = "scripts/security/check_sensitive_files.py"
RULE_SOURCE_PATHS = {SELF_PATH, ".gitleaks.toml"}

FORBIDDEN_SUFFIXES = {
    ".jks",
    ".keystore",
    ".p12",
    ".pfx",
    ".pem",
    ".key",
    ".mobileprovision",
}

FORBIDDEN_NAMES = {
    "key.properties",
    "id_rsa",
    "id_ed25519",
    "credentials.json",
    "service-account.json",
    "service_account.json",
    "secrets.json",
    "secret.json",
}

ALLOWED_EXACT_PATHS = {".env.example"}

ALLOWED_PRIVATE_IPV4_BY_PATH = {
    "server/internal/handler/webhook_test.go": {"10.0.0.8", "169.254.169.254"},
}

ALLOWED_WINDOWS_USER_PATHS_BY_PATH = {
    "client/test/widgets/app_error_view_test.dart": {
        "C:\\Users\\tester\\",
    },
}

ALLOWED_CREDENTIAL_CANDIDATES_BY_PATH = {
    ".github/workflows/ci.yml": {"postgres"},
    "server/internal/caldav/cron_test.go": {"invalid"},
    "server/internal/config/database_test.go": {"invalid"},
}

SUSPICIOUS_TEXT_PATTERNS = [
    (
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
        "私钥内容",
    ),
    (
        re.compile(
            r"(?i)(?:JWT_SECRET|CONFIG_ENCRYPTION_KEY|SLOWLIGHT_ANDROID_KEYSTORE_BASE64|"
            r"SLOWLIGHT_ANDROID_STORE_PASSWORD|SLOWLIGHT_ANDROID_KEY_PASSWORD|"
            r"FEISHU_APP_SECRET|APP_SECRET)"
            r"[ \t]*[:=][ \t]*['\"]?"
            r"(\$\{\{[^\r\n]+\}\}|\$\{[^}\r\n]+\}|[^\s'\"]{8,})"
        ),
        "敏感变量硬编码",
    ),
    (
        re.compile(r"(?i)\bSERVER_URL\s*[:=]\s*['\"]https?://(?!localhost\b|127\.0\.0\.1\b)"),
        "硬编码远程 SERVER_URL；应通过配置注入",
    ),
    (
        re.compile(
            r"(?is)String\.fromEnvironment\(\s*['\"]SERVER(?:_[A-Z0-9]+)*_URL['\"]\s*,"
            r"\s*defaultValue:\s*['\"]https?://(?!localhost\b|127\.0\.0\.1\b)"
        ),
        "SERVER_*_URL 携带非本地默认地址；公开源码应通过构建配置注入",
    ),
    (
        re.compile(
            r"(?i)\b(?:postgres(?:ql)?|mysql|mariadb)://[^\s:/]+:([^\s@]+)@"
        ),
        "包含用户名和密码的数据库 URL",
    ),
    (
        re.compile(
            r"(?i)\b(?:DATABASE_URL|TEST_DATABASE_URL)[ \t]*[:=][^\r\n]*?"
            r"\bpassword=(\$\{[^}\r\n]+\}|[^\s]+)"
        ),
        "包含用户名和密码的数据库 URL",
    ),
]

PLACEHOLDER_RE = re.compile(
    r"(?i)^(?:change[_-]?me(?:[_-][a-z0-9]+)*|your[_-][a-z0-9_-]+|"
    r"(?:example|placeholder|dummy|test)[_-]?[a-z0-9_-]*|slowlight-ci-[a-z0-9_-]+|"
    r"\$\{\{.*\}\}|\$\{[A-Z][A-Z0-9_]*(?::[^}]*)?\}|"
    r"\$\{[A-Z][A-Z0-9_]*:\?[^}]+\}|\$\{[0-9]+:-\})$"
)

IPV4_RE = re.compile(r"(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9.])")
WINDOWS_USER_PATH_RE = re.compile(r"(?i)\b[A-Z]:\\Users\\(?!Public\\)[^\\\s]+\\")
UNIX_HOME_PATH_RE = re.compile(r"(?<![\w/])/home/(?!runner/work(?:/|\b))[^/\s]+/")
INTERNAL_HOST_RE = re.compile(
    r"(?i)(?:https?://|(?<![A-Za-z0-9_.-]))"
    r"(?:[a-z0-9-]+\.)+(?:internal|local|lan)(?::\d+)?(?:[/\s'\"]|$)"
)


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [p.decode("utf-8") for p in result.stdout.split(b"\0") if p]


def is_probably_binary(data: bytes) -> bool:
    return b"\0" in data[:8192]


def private_ipv4s(text: str) -> list[str]:
    found: list[str] = []
    for raw in IPV4_RE.findall(text):
        try:
            address = ipaddress.ip_address(raw)
        except ValueError:
            continue
        if address.version == 4 and address.is_private and not address.is_loopback:
            found.append(raw)
    return found


def windows_user_paths(text: str) -> list[str]:
    return [match.group(0) for match in WINDOWS_USER_PATH_RE.finditer(text)]


def main() -> int:
    problems: list[str] = []

    for rel in tracked_files():
        path = Path(rel)
        lower_name = path.name.lower()
        lower_suffix = path.suffix.lower()

        if lower_name.startswith(".env") and rel not in ALLOWED_EXACT_PATHS:
            problems.append(f"{rel}: 禁止提交真实环境变量文件")

        if lower_name in FORBIDDEN_NAMES:
            problems.append(f"{rel}: 禁止提交敏感/本地配置文件")

        if lower_suffix in FORBIDDEN_SUFFIXES:
            problems.append(f"{rel}: 禁止提交签名证书、keystore 或私钥文件")

        full = ROOT / rel
        try:
            data = full.read_bytes()
        except OSError as exc:
            problems.append(f"{rel}: 无法读取文件进行安全检查: {exc}")
            continue

        if is_probably_binary(data):
            continue

        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue

        # 规则源文件包含用于检测的正则文本，由 Gitleaks 继续扫描其实际内容。
        if rel in RULE_SOURCE_PATHS:
            continue

        for pattern, description in SUSPICIOUS_TEXT_PATTERNS:
            for match in pattern.finditer(text):
                if match.lastindex:
                    candidate = match.group(1)
                    allowed_candidates = ALLOWED_CREDENTIAL_CANDIDATES_BY_PATH.get(
                        rel, set()
                    )
                    if PLACEHOLDER_RE.match(candidate) or candidate in allowed_candidates:
                        continue
                problems.append(f"{rel}: 检测到{description}（不会输出具体值）")
                break

        private_addresses = set(private_ipv4s(text))
        private_addresses -= ALLOWED_PRIVATE_IPV4_BY_PATH.get(rel, set())
        if private_addresses:
            problems.append(f"{rel}: 检测到 RFC1918 私有网段地址")
        user_paths = set(windows_user_paths(text))
        user_paths -= ALLOWED_WINDOWS_USER_PATHS_BY_PATH.get(rel, set())
        if user_paths:
            problems.append(f"{rel}: 检测到 Windows 用户目录绝对路径")
        if UNIX_HOME_PATH_RE.search(text):
            problems.append(f"{rel}: 检测到 Linux 用户 home 绝对路径")
        if INTERNAL_HOST_RE.search(text):
            problems.append(f"{rel}: 检测到 .internal/.local/.lan 内部主机名")

    if problems:
        print("Slowlight 敏感信息门禁失败：", file=sys.stderr)
        for problem in sorted(set(problems)):
            print(f"- {problem}", file=sys.stderr)
        print(
            "\n请移除真实敏感信息或私有环境痕迹，改用 GitHub Secrets / Variables 或本地配置。",
            file=sys.stderr,
        )
        return 1

    print("Sensitive-file guard passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
