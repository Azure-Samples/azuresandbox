import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch, Mock


SPEC = importlib.util.spec_from_file_location(
    "runner_monitor", Path(__file__).resolve().parents[1] / "Watch-SandboxRunner.py"
)
MONITOR = importlib.util.module_from_spec(SPEC)
with patch.object(sys, "path", [str(Path(__file__).resolve().parents[1]), *sys.path]):
    SPEC.loader.exec_module(MONITOR)


class MonitorTests(unittest.TestCase):
    def test_progress_omits_resource_ids(self):
        line = (
            "module.vnet_app[0].azurerm_storage_account.this: "
            "Creation complete after 1m2s [id=/subscriptions/private/resourceGroups/private]"
        )
        value = MONITOR.PROGRESS.match(line)[0]
        self.assertIn("Creation complete after 1m2s", value)
        self.assertNotIn("subscriptions", value)
        self.assertNotIn("private", value)

    def test_heartbeat_preserves_elapsed_counter(self):
        value = MONITOR.PROGRESS.match(
            "module.vwan[0].azurerm_vpn_gateway.this: Still creating... [32m10s elapsed]"
        )[0]
        self.assertIn("32m10s elapsed", value)

    def test_private_text_is_not_progress(self):
        self.assertIsNone(MONITOR.PROGRESS.match("Error: tenant private policy details"))
        self.assertIsNone(MONITOR.PROGRESS.match("secret = private"))
        self.assertIsNone(MONITOR.PROGRESS.match('resource.this["private-ip"]: Creating...'))
        self.assertIsNone(MONITOR.PROGRESS.match("private-host.example: Creating..."))

    def test_quiet_time_does_not_reset_as_elapsed_time_increases(self):
        previous = {
            "stage": "preflight", "changed_at": 1000,
            "log": {"bytes": 10, "modified": 900, "elapsed_seconds": 1},
        }
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(MONITOR.subprocess, "run", return_value=Mock(stdout="active\n")):
                with patch.object(MONITOR, "process_counts", return_value={}):
                    with patch.object(MONITOR, "read_log", side_effect=[
                        ({"bytes": 10, "modified": 900, "elapsed_seconds": 500}, []),
                        (None, []), (None, []),
                    ]):
                        with patch.object(MONITOR.time, "time", return_value=1241):
                            result = MONITOR.snapshot("unit", Path(temporary), previous)
        self.assertEqual(result["health"], "possibly-stalled")
        self.assertEqual(result["quiet_seconds"], 241)

    def test_failed_stage_is_terminal(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "preflight-status.json").write_text('{"exit_code": 1}')
            with patch.object(MONITOR.subprocess, "run", return_value=Mock(stdout="active\n")):
                with patch.object(MONITOR, "process_counts", return_value={}):
                    result = MONITOR.snapshot("unit", directory, {})
        self.assertTrue(result["terminal"])
        self.assertEqual(result["health"], "failed")


if __name__ == "__main__":
    unittest.main()
