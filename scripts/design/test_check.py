"""验证检查入口不会吞掉失败、缺SDK或不完整结果。"""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import check


class RunnerTests(unittest.TestCase):
    def run_case(self, events, code, sdk="flutter"):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "client/test/ui").mkdir(parents=True)
            (root / "client/test/widgets").mkdir()
            (root / "client/test/widgets/fx_form_size_contract_test.dart").touch()
            report = root / "report.json"
            process = SimpleNamespace(stdout=iter(json.dumps(e) + "\n" for e in events),
                                      wait=lambda: code, poll=lambda: code)
            with patch.object(check, "ROOT", root), patch.object(check.shutil, "which", return_value=sdk), \
                 patch.object(check.subprocess, "Popen", return_value=process), \
                 patch.object(check.subprocess, "run", return_value=SimpleNamespace(stdout="test-head")), \
                 patch("sys.argv", ["check.py", "--report", str(report)]), \
                 contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                result = check.main()
            return result, json.loads(report.read_text(encoding="utf-8"))

    def test_success_requires_complete_stream_and_keeps_device_unverified(self):
        result, report = self.run_case([[], {"type": "testDone", "testID": 1, "result": "success"},
                                       {"type": "done", "success": True}], 0)
        self.assertEqual(result, 0)
        self.assertEqual(report["统计"]["通过"], 1)
        self.assertEqual(report["真实设备验收"], "未执行")

    def test_failure_is_preserved_with_test_name(self):
        result, report = self.run_case([
            {"type": "testStart", "test": {"id": 1, "name": "违规样例"}},
            {"type": "error", "testID": 1, "error": "禁止绕过Fx"},
            {"type": "testDone", "testID": 1, "result": "failure"},
            {"type": "done", "success": False}], 1)
        self.assertEqual(result, 1)
        self.assertEqual(report["失败测试"][0]["名称"], "违规样例")

    def test_truncated_stream_cannot_pass_even_with_zero_exit_code(self):
        result, _ = self.run_case([], 0)
        self.assertNotEqual(result, 0)

    def test_missing_sdk_fails_and_produces_report(self):
        result, report = self.run_case([], 0, sdk=None)
        self.assertEqual(result, 2)
        self.assertTrue(report["启动错误"])


if __name__ == "__main__":
    unittest.main()
