import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


HELPER = Path(__file__).resolve().parents[1] / "Invoke-SandboxDeployment.py"
SPEC = importlib.util.spec_from_file_location("sandbox_deployment", HELPER)
deployment = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deployment)

BACKEND = '''terraform {
  backend "azurerm" {
    tenant_id = "test-tenant"
    subscription_id = "test-subscription"
    storage_account_name = "teststorage"
    container_name = "tfstate"
    use_msi = true
    use_azuread_auth = true
  }
}
'''


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.root = self.home / "checkout"
        self.root.mkdir()
        self.environment = {
            "GITHUB_WORKSPACE": str(self.root),
            "GITHUB_RUN_ID": "12345", "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_SERVER_URL": "https://github.com",
            "GITHUB_REPOSITORY": "Azure-Samples/azuresandbox",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_STEP_SUMMARY": str(self.home / "summary"),
            "GITHUB_OUTPUT": str(self.home / "github-output"),
            "RUNNER_TEMP": str(self.home),
            "RUNNER_NAME": "jumplinux2",
            "SANDBOX_DEPLOYMENT_MODE": "new",
            "SANDBOX_RUN_THROUGH": "preflight",
            "SANDBOX_BACKEND_HCL": BACKEND,
            "SANDBOX_TFVARS_HCL": 'arm_auth_mode = "msi"\n',
            "ARM_CLIENT_ID": "stale-identity",
            "TF_VAR_arm_client_secret": "must-not-inherit",
        }
        self.env_patch = patch.dict(os.environ, self.environment, clear=True)
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)
        self.home_patch = patch.object(Path, "home", return_value=self.home)
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)
        self.original_umask = os.umask(0o077)
        self.addCleanup(os.umask, self.original_umask)
        self.commands = []
        self.blob_exists = False
        self.apply_code = 0
        self.running = True
        self.test_code = 0
        self.has_outputs = False

    def fake_command(self, runner, args, *, output=None, input_text=None):
        self.commands.append(args)
        text = ""
        if args[:4] == ["az", "storage", "blob", "exists"]:
            text = json.dumps(self.blob_exists)
        elif args[:2] == ["terraform", "console"]:
            profile = {
                "arm_auth_mode": "msi", "arm_client_id": "test-client",
                "aad_tenant_id": "test-tenant", "subscription_id": "test-subscription",
                "base": [True] * 6, "extras": [False] * 3,
            }
            text = json.dumps(json.dumps(profile))
        elif args[:3] == ["az", "account", "show"]:
            text = json.dumps({"id": "test-subscription", "tenantId": "test-tenant"})
        elif args[:2] == ["terraform", "output"]:
            names = {"resource_group": "test-rg", "virtual_machine_adds1": "test-vm"}
            text = json.dumps(names if len(args) == 4 else {"resource_names": {"value": names}} if self.has_outputs else {})
        elif args[:2] == ["terraform", "plan"]:
            runner.plan.write_bytes(b"private-plan")
        elif args[:2] == ["terraform", "show"]:
            text = json.dumps({"resource_changes": [{"change": {"actions": ["delete", "create"]}}]})
        elif args[:2] == ["git", "rev-parse"]:
            text = "a" * 40
        elif args[:2] == ["terraform", "apply"]:
            if self.apply_code:
                raise deployment.StageFailure("simulated private apply error", self.apply_code)
        elif args[:3] == ["az", "vm", "list"]:
            text = json.dumps([{"name": "test-vm", "powerState": "VM running" if self.running else "VM deallocated"}])
        elif "-RunTests" in args:
            (self.root / "Invoke-UnitTests.ps1.log").write_text("private-test-log")
            deployment.write_json(runner.directory / "unit-test-results.json", {
                "schemaVersion": 1, "exitCode": self.test_code,
                "totals": {"passed": 3, "failed": 1 if self.test_code else 0, "suitesSkipped": 0},
            })
            (runner.directory / "unit-test-results.xml").write_text("<testsuites/>")
            if self.test_code:
                raise deployment.StageFailure("simulated test failure", self.test_code)
        if output:
            output.write_text(text)

    def execute(self, stage):
        runner = deployment.Runner()
        with patch.object(deployment.Runner, "command", autospec=True, side_effect=self.fake_command), contextlib.redirect_stdout(io.StringIO()):
            code = runner.execute(stage)
        return runner, code

    def test_preflight_private_receipt_and_backend_first(self):
        runner, code = self.execute("preflight")
        self.assertEqual(code, 0)
        self.assertEqual(runner.deployment_id, "sandbox-12345")
        self.assertNotIn("ARM_CLIENT_ID", runner.env)
        self.assertNotIn("TF_VAR_arm_client_secret", runner.env)
        self.assertNotIn("SANDBOX_BACKEND_HCL", runner.env)
        self.assertIn(["terraform", "init", "-input=false", "-backend-config=key=sandboxes/sandbox-12345/terraform.tfstate"], self.commands)
        receipt = json.loads(runner.receipt.read_text())
        self.assertEqual(receipt["changes"], {"create": 1, "update": 0, "delete": 1})
        self.assertEqual(receipt["plan_sha256"], deployment.digest(runner.plan))
        self.assertEqual(runner.directory.stat().st_mode & 0o777, 0o700)
        for name in ("sandbox.tfplan", "preflight.log", "plan-receipt.json", "backend.tf", "terraform.tfvars"):
            self.assertEqual((runner.directory / name).stat().st_mode & 0o777, 0o600)
        self.assertNotIn("test-tenant", Path(self.environment["GITHUB_STEP_SUMMARY"]).read_text())

    def test_new_existing_key_fails_before_init(self):
        self.blob_exists = True
        runner, code = self.execute("preflight")
        self.assertEqual(code, 1)
        self.assertFalse(runner.receipt.exists())
        self.assertFalse(any(args[:2] == ["terraform", "init"] for args in self.commands))

    def test_existing_requires_receipt_and_blob(self):
        os.environ.update(SANDBOX_DEPLOYMENT_MODE="existing", SANDBOX_EXISTING_ID="sandbox-999")
        _, code = self.execute("preflight")
        self.assertEqual(code, 1)
        self.assertFalse(any(args[:2] == ["terraform", "init"] for args in self.commands))

    def test_apply_uses_exact_plan_and_preserves_failure(self):
        runner, _ = self.execute("preflight")
        self.apply_code = 7
        _, code = self.execute("apply")
        self.assertEqual(code, 7)
        status = json.loads((runner.directory / "apply-status.json").read_text())
        self.assertEqual(status["exit_code"], 7)
        self.assertTrue((runner.directory / "apply.log").exists())
        self.assertIn(["terraform", "apply", "-input=false", "-no-color", str(runner.plan)], self.commands)

    def test_tampered_plan_prevents_apply(self):
        runner, _ = self.execute("preflight")
        runner.plan.write_bytes(b"tampered")
        _, code = self.execute("apply")
        self.assertEqual(code, 1)
        self.assertFalse(any(args[:2] == ["terraform", "apply"] for args in self.commands))

    def test_changed_inputs_prevent_apply(self):
        self.execute("preflight")
        (self.root / "terraform.tfvars").write_text("changed")
        _, code = self.execute("apply")
        self.assertEqual(code, 1)
        self.assertFalse(any(args[:2] == ["terraform", "apply"] for args in self.commands))

    def test_later_run_reuses_deployment_identity_and_key(self):
        first, _ = self.execute("preflight")
        self.blob_exists = True
        self.has_outputs = True
        os.environ.update(
            GITHUB_RUN_ID="67890", SANDBOX_DEPLOYMENT_MODE="existing",
            SANDBOX_EXISTING_ID=first.deployment_id,
        )
        later, code = self.execute("preflight")
        self.assertEqual(code, 0)
        self.assertEqual(later.key, first.key)
        self.assertNotEqual(later.directory, first.directory)
        self.assertEqual(json.loads(later.receipt.read_text())["origin_run_id"], "12345")
        enable = self.commands.index(["bash", "scripts/enable-public-access.sh"])
        plan = next(i for i, args in enumerate(self.commands[enable:], start=enable) if args[:2] == ["terraform", "plan"])
        self.assertLess(enable, plan)

    def test_retry_keeps_id_but_isolates_attempt_files(self):
        first, _ = self.execute("preflight")
        self.blob_exists = True
        os.environ["GITHUB_RUN_ATTEMPT"] = "2"
        retry, code = self.execute("preflight")
        self.assertEqual(code, 0)
        self.assertEqual(retry.key, first.key)
        self.assertNotEqual(retry.directory, first.directory)
        self.assertTrue(first.plan.exists())

    def test_actual_command_failure_preserves_private_stdout_stderr(self):
        runner = deployment.Runner()
        runner.directory.mkdir(parents=True, mode=0o700)
        runner.stage = "apply"
        public = io.StringIO()
        with (runner.directory / "apply.log").open("w") as stream, contextlib.redirect_stdout(public):
            runner.log = stream
            with self.assertRaises(deployment.StageFailure) as failure:
                runner.command([sys.executable, "-c", 'import sys; print("private-out"); print("private-error", file=sys.stderr); sys.exit(7)'])
        self.assertEqual(failure.exception.code, 7)
        log = (runner.directory / "apply.log").read_text()
        self.assertIn("private-out", log)
        self.assertIn("private-error", log)
        self.assertIn("Exit code: 7", log)
        self.assertEqual(public.getvalue(), "")

    def test_unit_test_after_apply_preserves_failed_test_log(self):
        runner, _ = self.execute("preflight")
        self.execute("apply")
        self.test_code = 1
        _, code = self.execute("unit-test")
        self.assertEqual(code, 1)
        self.assertTrue((runner.directory / "orchestrator.log").exists())
        self.assertEqual(json.loads((runner.directory / "apply-status.json").read_text())["exit_code"], 0)
        starts = next(i for i, args in enumerate(self.commands) if args == ["bash", "scripts/manage-vms.sh", "start"])
        tests = next(i for i, args in enumerate(self.commands) if "-RunTests" in args)
        self.assertLess(starts, tests)

    def test_vm_gate_blocks_tests_when_vm_not_running(self):
        self.execute("preflight")
        self.execute("apply")
        self.running = False
        with patch.object(deployment.time, "monotonic", side_effect=[0, 601]):
            _, code = self.execute("unit-test")
        self.assertEqual(code, 1)
        self.assertFalse(any("-RunTests" in args for args in self.commands))

    def test_summary_separates_apply_success_from_test_failure(self):
        self.execute("preflight")
        self.execute("apply")
        self.test_code = 1
        self.execute("unit-test")
        os.environ.update(PREFLIGHT_OUTCOME="success", APPLY_OUTCOME="success", UNIT_TEST_OUTCOME="failure")
        _, code = self.execute("summary")
        self.assertEqual(code, 0)
        summary = Path(self.environment["GITHUB_STEP_SUMMARY"]).read_text()
        self.assertIn("| apply | PASS |", summary)
        self.assertIn("| unit-test | FAIL |", summary)
        self.assertIn("passed=3, failed=1", summary)
        self.assertNotIn("test-tenant", summary)
        self.assertNotIn("test-client", summary)

    def test_evidence_contains_only_json_and_junit_on_success_and_failure(self):
        for test_code in (0, 1, 2):
            with self.subTest(test_code=test_code):
                os.environ["GITHUB_RUN_ID"] = str(20000 + test_code)
                self.execute("preflight")
                self.execute("apply")
                self.test_code = test_code
                runner, code = self.execute("unit-test")
                self.assertEqual(code, test_code)
                _, code = self.execute("evidence")
                self.assertEqual(code, 0)
                staging = self.home / f"sandbox-test-evidence-{runner.run_id}-1"
                self.assertEqual({path.name for path in staging.iterdir()}, {"unit-test-results.json", "unit-test-results.xml"})
                self.assertEqual(
                    (staging / "unit-test-results.json").read_bytes(),
                    (runner.directory / "unit-test-results.json").read_bytes(),
                )
                self.assertEqual(staging.stat().st_mode & 0o777, 0o700)
                outputs = Path(self.environment["GITHUB_OUTPUT"]).read_text()
                self.assertIn("ready=true", outputs)
                self.assertIn(f"name=unit-test-evidence-{runner.deployment_id}-{runner.run_id}-1", outputs)
                self.assertTrue(runner.plan.exists())

    def test_evidence_unavailable_when_vm_gate_fails(self):
        self.execute("preflight")
        self.execute("apply")
        self.running = False
        with patch.object(deployment.time, "monotonic", side_effect=[0, 601]):
            self.execute("unit-test")
        _, code = self.execute("evidence")
        self.assertEqual(code, 0)
        self.assertIn("ready=false", Path(self.environment["GITHUB_OUTPUT"]).read_text())
        self.assertIn("No test results were fabricated", Path(self.environment["GITHUB_STEP_SUMMARY"]).read_text())
        self.assertFalse((self.home / "sandbox-test-evidence-12345-1").exists())

    def test_partial_evidence_is_explicit(self):
        runner, _ = self.execute("preflight")
        self.execute("apply")
        self.execute("unit-test")
        (runner.directory / "unit-test-results.xml").unlink()
        self.execute("evidence")
        self.assertIn("Partial unit-test evidence", Path(self.environment["GITHUB_STEP_SUMMARY"]).read_text())
        self.assertEqual(
            {path.name for path in (self.home / "sandbox-test-evidence-12345-1").iterdir()},
            {"unit-test-results.json"},
        )

    def test_invalid_results_are_not_staged(self):
        runner, _ = self.execute("preflight")
        self.execute("apply")
        self.execute("unit-test")
        (runner.directory / "unit-test-results.xml").write_text("<broken")
        with self.assertRaises(deployment.ET.ParseError):
            self.execute("evidence")
        self.assertFalse((self.home / "sandbox-test-evidence-12345-1").exists())
        self.assertFalse(Path(self.environment["GITHUB_OUTPUT"]).exists())

    def test_summary_links_published_artifact(self):
        self.execute("preflight")
        os.environ.update(
            UNIT_TEST_ARTIFACT_OUTCOME="success",
            UNIT_TEST_ARTIFACT_URL="https://github.com/Azure-Samples/azuresandbox/actions/runs/12345/artifacts/456",
        )
        self.execute("summary")
        self.assertIn("Download sanitized unit-test evidence", Path(self.environment["GITHUB_STEP_SUMMARY"]).read_text())

    def test_backend_rejects_fixed_key(self):
        with self.assertRaises(deployment.StageFailure):
            deployment.backend_settings(BACKEND.replace('use_msi = true', 'key = "shared.tfstate"\n    use_msi = true'))

    def test_existing_id_cannot_escape_directory(self):
        os.environ.update(SANDBOX_DEPLOYMENT_MODE="existing", SANDBOX_EXISTING_ID="../../unsafe")
        with self.assertRaises(deployment.StageFailure):
            deployment.Runner()


class LinuxResultPrivacyTests(unittest.TestCase):
    def run_result(self, arguments):
        path = Path(__file__).resolve().parents[5] / "modules/vm-jumpbox-linux/scripts/test-vm-jumpbox-linux.sh"
        text = path.read_text()
        options = re.search(r'(?ms)^verbosity=.*?^esac$', text).group()
        helper = re.search(r'(?ms)^write_test_result\(\) \{.*?^\}', text).group()
        fixture = (
            options + '\nmodule_name=test\nwrite_log() { printf "%s\\n" "$1"; }\n'
            + helper + '\nwrite_test_result PASS "DNS private-host.example.invalid" "Safe DNS check"\n'
            + 'write_test_result SUMMARY "Passed: 1 Failed: 0 Total: 1"\n'
        )
        return subprocess.run(["bash", "-c", fixture, "fixture", *arguments], text=True, capture_output=True)

    def test_default_linux_result_is_sanitized(self):
        result = self.run_result([])
        self.assertEqual(result.returncode, 0)
        self.assertIn("Safe DNS check", result.stdout)
        self.assertNotIn("private-host.example.invalid", result.stdout)
        self.assertIn("Passed: 1 Failed: 0 Total: 1", result.stdout)

    def test_linux_verbose_direct_and_run_command_options(self):
        for option in ("--verbose-results", "true", "VerboseResults=true"):
            with self.subTest(option=option):
                result = self.run_result([option])
                self.assertEqual(result.returncode, 0)
                self.assertIn("private-host.example.invalid", result.stdout)

    def test_linux_invalid_verbosity_fails_explicitly(self):
        result = self.run_result(["invalid"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("Invalid verbose-results", result.stderr)


if __name__ == "__main__":
    unittest.main()
