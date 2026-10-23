import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_xcodebuild import run, retry_command, SERVICE_CRASH, collect_crash_reports


class Process:
    def __init__(self, output, code):
        self.stdout = io.StringIO(output)
        self.code = code

    def wait(self):
        return self.code


class XcodeRetryTests(unittest.TestCase):
    command = ["xcodebuild", "test", "-derivedDataPath", "build/TestDerivedData",
               "-resultBundlePath", "build/TestResults.xcresult", "-jobs", "2"]

    def execute(self, processes):
        root = Path(__file__).resolve().parents[2]
        temporary_root = (root / "build/ci-test-tmp").resolve()
        assert temporary_root.is_relative_to(root)
        temporary_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_root) as folder, contextlib.redirect_stdout(io.StringIO()):
            prefix = Path(folder) / "test"
            with patch("run_xcodebuild.subprocess.Popen", side_effect=processes) as popen:
                code = run(self.command, prefix)
                logs = [path.read_text() for path in sorted(Path(folder).glob("*.log"))]
                return code, popen.call_args_list, logs

    def test_success_is_not_repeated(self):
        code, calls, _ = self.execute([Process("TEST SUCCEEDED\n", 0)])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 1)

    def test_compilation_error_is_not_retried(self):
        code, calls, _ = self.execute([Process("error: cannot find type\n", 65)])
        self.assertEqual(code, 65)
        self.assertEqual(len(calls), 1)

    def test_failed_assertion_is_not_retried(self):
        code, calls, _ = self.execute([Process("XCTAssertEqual failed\nTEST FAILED\n", 65)])
        self.assertEqual(code, 65)
        self.assertEqual(len(calls), 1)

    def test_crash_retries_once_with_independent_paths_and_preserved_logs(self):
        code, calls, logs = self.execute([Process(SERVICE_CRASH + "\n", 65), Process("TEST SUCCEEDED\n", 0)])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 2)
        self.assertIn(str(Path("build/TestDerivedData-retry")), calls[1].args[0])
        self.assertIn(str(Path("build/TestResults-retry.xcresult")), calls[1].args[0])
        self.assertIn(SERVICE_CRASH, logs[0])
        self.assertIn("TEST SUCCEEDED", logs[1])
        self.assertEqual(self.command[3], "build/TestDerivedData")

    def test_second_crash_stops_with_failure(self):
        code, calls, _ = self.execute([Process(SERVICE_CRASH, 65), Process(SERVICE_CRASH, 65)])
        self.assertEqual(code, 65)
        self.assertEqual(len(calls), 2)

    def test_diagnostics_collects_only_recent_build_service_reports(self):
        root = Path(__file__).resolve().parents[2]
        temporary_root = (root / "build/ci-test-tmp").resolve()
        assert temporary_root.is_relative_to(root)
        temporary_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_root) as folder, contextlib.redirect_stdout(io.StringIO()):
            source = Path(folder) / "source"
            source.mkdir()
            (source / "XCBBuildService-2026.ips").write_text("build crash")
            (source / "UnrelatedApp.ips").write_text("unrelated")
            destination = Path(folder) / "collected"
            collect_crash_reports(destination, roots=[source])
            self.assertEqual([p.name for p in destination.iterdir()], ["XCBBuildService-2026.ips"])

    def test_missing_isolated_paths_are_rejected(self):
        with self.assertRaises(ValueError):
            retry_command(["xcodebuild", "test"])


if __name__ == "__main__":
    unittest.main()
