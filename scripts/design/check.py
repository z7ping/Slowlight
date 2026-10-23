#!/usr/bin/env python3
"""复用现有 Fx 契约测试，输出可追溯的设计一致性检查结果。"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGETS = ("test/ui", "test/widgets/fx_form_size_contract_test.dart")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="可选 JSON 结果路径；建议置于 client/build 下")
    args = parser.parse_args()
    errors = [f"缺少检查目标：client/{target}" for target in TARGETS
              if not (ROOT / "client" / target).exists()]
    flutter = shutil.which("flutter")
    if not flutter:
        errors.append("未找到 Flutter，请将项目所用 SDK 加入 PATH")
    command = [flutter or "flutter", "test", "--no-pub", "--machine", *TARGETS]
    failures = []
    counts = {"通过": 0, "失败": 0, "跳过": 0}
    print("[设计检查] 复用 test/ui 全目录及 Fx 表单尺寸契约，不创建第二套扫描规则。", flush=True)
    if errors:
        for error in errors:
            print(f"[设计检查] {error}", file=sys.stderr)
        result = 2
    else:
        # 参数列表调用，兼容 Windows flutter.bat；不拼接用户提供的 shell 文本。
        tests = {}
        finished = False
        runner_success = False
        events = None
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            events = args.report.with_suffix(".events.jsonl").open("w", encoding="utf-8")
        try:
            process = subprocess.Popen(command, cwd=ROOT / "client", stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
            for line in process.stdout:
                if events:
                    events.write(line)
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    if line.strip():
                        print(line.rstrip(), flush=True)
                    continue
                if not isinstance(event, dict):
                    continue
                kind = event.get("type")
                if kind == "done":
                    finished = True
                    runner_success = event.get("success") is True
                elif kind == "testStart":
                    item = event["test"]
                    tests[item["id"]] = {"名称": item["name"], "错误": []}
                elif kind == "error":
                    test = tests.setdefault(event.get("testID"), {"名称": "测试加载", "错误": []})
                    test["错误"].append(event.get("error", ""))
                elif kind == "testDone":
                    test = tests.get(event["testID"], {"名称": "未知测试", "错误": []})
                    if event.get("skipped"):
                        counts["跳过"] += 1
                    elif event.get("result") != "success":
                        counts["失败"] += 1
                        failures.append(test)
                        print(f"[设计检查] 失败：{test['名称']}", flush=True)
                    elif not event.get("hidden", False):
                        counts["通过"] += 1
            result = process.wait()
            if result == 0 and (not finished or not runner_success):
                errors.append("Flutter 未返回完整的成功结束事件，不能认定检查通过")
                result = 1
        except OSError as error:
            errors.append(str(error))
            print(f"[设计检查] 无法启动 Flutter：{error}", file=sys.stderr)
            result = 2
        finally:
            if 'process' in locals() and process.poll() is None:
                process.terminate()
                process.wait()
            if events:
                events.close()
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
                              capture_output=True, check=False).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, text=True,
                               capture_output=True, check=False).stdout.strip()
        args.report.write_text(json.dumps({
            "时间UTC": datetime.now(timezone.utc).isoformat(),
            "提交": head, "工作区有未提交改动": bool(dirty),
            "检查目标": list(TARGETS), "退出码": result,
            "统计": counts, "失败测试": failures, "启动错误": errors,
            "契约检查": "通过" if result == 0 else "失败或未能执行",
            "整页视觉验收": "未执行", "真实设备验收": "未执行",
            "说明": "测试覆盖 Fx/Token/平台与几何契约，不证明整页外观或真实数据链路。",
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[设计检查] 通过{counts['通过']} / 失败{counts['失败']} / 跳过{counts['跳过']}。")
    print(f"[设计检查] {'通过' if result == 0 else '失败'}；整页视觉与真实设备验收仍须单独执行。")
    return result


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(main())
