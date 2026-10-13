#!/usr/bin/env python3
"""Protected runner stages; configuration and raw diagnostics stay runner-local."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import traceback
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

from sandbox_progress import read_progress


class StageFailure(RuntimeError):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def backend_settings(text):
    """Backend values are literal strings; Terraform validates the complete HCL."""
    settings = {}
    for key in ("tenant_id", "subscription_id", "storage_account_name", "container_name"):
        matches = re.findall(rf'(?m)^\s*{key}\s*=\s*"([^"\n]+)"\s*(?:#.*)?$', text)
        if len(matches) != 1:
            raise StageFailure(f"Backend requires exactly one literal {key}.")
        settings[key] = matches[0]
    for key in ("use_msi", "use_azuread_auth"):
        if not re.search(rf"(?m)^\s*{key}\s*=\s*true\s*(?:#.*)?$", text):
            raise StageFailure(f"Backend requires {key} = true.")
    if re.search(r"(?m)^\s*(key|client_id|access_key|sas_token|client_secret)\s*=", text):
        raise StageFailure("Backend must omit fixed keys and authentication credentials.")
    return settings


class Runner:
    def __init__(self):
        os.umask(0o077)
        self.env = os.environ.copy()
        self.root = Path(self.env["GITHUB_WORKSPACE"])
        self.run_id = self.env["GITHUB_RUN_ID"]
        self.attempt = self.env["GITHUB_RUN_ATTEMPT"]
        self.through = self.env["SANDBOX_RUN_THROUGH"]
        if self.env.get("SANDBOX_DEPLOYMENT_MODE") not in (None, "", "new") or self.env.get("SANDBOX_EXISTING_ID"):
            raise StageFailure("Automated deployments provision new Sandboxes only.")
        if not re.fullmatch(r"[1-9][0-9]*", self.run_id) or not re.fullmatch(r"[1-9][0-9]*", self.attempt):
            raise StageFailure("Invalid workflow run metadata.")
        self.deployment_id = f"sandbox-{self.run_id}"
        if self.through not in ("preflight", "apply", "unit-test"):
            raise StageFailure("Invalid stage selection.")
        self.deployment_dir = Path.home() / ".local/state/azuresandbox/deployments" / self.deployment_id
        self.directory = self.deployment_dir / "runs" / f"{self.run_id}-{self.attempt}"
        self.key = f"sandboxes/{self.deployment_id}/terraform.tfstate"
        self.plan = self.directory / "sandbox.tfplan"
        self.receipt = self.directory / "plan-receipt.json"
        self.origin_id = self.deployment_id.removeprefix("sandbox-")
        self.run_base = f'{self.env["GITHUB_SERVER_URL"]}/{self.env["GITHUB_REPOSITORY"]}/actions/runs/'
        self.log = None
        self.stage = None
        # Do not inherit workstation credentials, Terraform overrides, or another backend's identity.
        for name in list(self.env):
            if name.startswith(("TF_VAR_", "ARM_", "TF_CLI_ARGS")) or name in (
                "SANDBOX_BACKEND_HCL", "SANDBOX_TFVARS_HCL",
            ):
                self.env.pop(name)
        self.env.update(
            TF_IN_AUTOMATION="true", TF_INPUT="false",
            TF_DATA_DIR=str(self.directory / "terraform-data"),
            AZURE_CONFIG_DIR=str(self.directory / "azure-cli"),
            ARM_USE_MSI="true", TF_WORKSPACE="default",
        )

    def command(self, args, *, output=None, input_text=None):
        self.log.write(f"\n[{utc_now()}] {json.dumps(args)}\n")
        self.log.flush()
        started = time.monotonic()
        last_size = self.log.tell()
        with output.open("w", encoding="utf-8") if output else open(os.devnull, "w") as target:
            with subprocess.Popen(
                args, cwd=self.root, env=self.env,
                stdin=subprocess.PIPE if input_text is not None else subprocess.DEVNULL,
                stdout=target if output else self.log, stderr=self.log, text=True,
            ) as process:
                if input_text is not None:
                    process.stdin.write(input_text)
                    process.stdin.close()
                while True:
                    try:
                        code = process.wait(timeout=120)
                        break
                    except subprocess.TimeoutExpired:
                        size = Path(self.log.name).stat().st_size
                        health = "log advancing" if size > last_size else "no new log output; review if persistent"
                        print(f"{self.stage}: {int((time.monotonic() - started) / 60)} min elapsed; {health}.", flush=True)
                        if self.stage in ("apply", "unit-test") and size > last_size:
                            try:
                                for line in read_progress(Path(self.log.name), last_size, stage=self.stage):
                                    print(f"  {line}", flush=True)
                            except OSError:
                                traceback.print_exc(file=self.log)
                                self.log.flush()
                                size = Path(self.log.name).stat().st_size
                                print(f"{self.stage}: sanitized progress preview unavailable; see private diagnostics.", flush=True)
                        last_size = size
        self.log.write(f"[{utc_now()}] Exit code: {code}\n")
        self.log.flush()
        if code != 0:
            raise StageFailure("Command failed; see the private stage log.", code if code > 0 else 1)

    def read_output(self, args, name, input_text=None):
        path = self.directory / name
        self.command(args, output=path, input_text=input_text)
        return path.read_text(encoding="utf-8")

    def summary(self, text):
        with Path(self.env["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
            stream.write(text)

    def source_sha(self):
        return self.read_output(["git", "rev-parse", "HEAD"], "source-sha.txt").strip()

    def fingerprints(self):
        values = {name: digest(self.root / name) for name in ("backend.tf", "terraform.tfvars")}
        values["profile.json"] = digest(self.directory / "profile.json")
        return values

    def check_receipt(self):
        record = json.loads(self.receipt.read_text())
        expected = {
            "deployment_id": self.deployment_id, "state_key": self.key,
            "run_id": self.run_id, "run_attempt": self.attempt,
            "source_sha": self.source_sha(), "configuration": self.fingerprints(),
            "plan_sha256": digest(self.plan), "plan_path": str(self.plan),
        }
        if any(record.get(key) != value for key, value in expected.items()):
            raise StageFailure("Saved plan does not match this run, source, or configuration.")
        return record

    def preflight(self):
        if self.env.get("GITHUB_REF") != "refs/heads/main":
            raise StageFailure("Dispatch the registered workflow from main.")
        if self.env.get("RUNNER_NAME") != "jumplinux2":
            raise StageFailure("Job did not run on the approved runner.")
        backend_text = os.environ.get("SANDBOX_BACKEND_HCL", "")
        inputs_text = os.environ.get("SANDBOX_TFVARS_HCL", "")
        if not backend_text.strip() or not inputs_text.strip():
            raise StageFailure("Both environment HCL secrets are required.")
        (self.root / "backend.tf").write_text(backend_text, encoding="utf-8")
        (self.root / "terraform.tfvars").write_text(inputs_text, encoding="utf-8")
        for name in ("backend.tf", "terraform.tfvars"):
            os.chmod(self.root / name, 0o600)
            (self.directory / name).write_bytes((self.root / name).read_bytes())
        backend = backend_settings(backend_text)
        self.env["ARM_TENANT_ID"] = backend["tenant_id"]
        self.summary(
            f"## Sandbox target\n\nDeployment: `{self.deployment_id}`\n\n"
            f"State key: `{self.key}`\n\n"
            f"[Originating run]({self.run_base}{self.origin_id}) / "
            f"[Current run]({self.run_base}{self.run_id})\n\n"
        )
        for args in (["git", "--version"], ["terraform", "version"], ["az", "version"]):
            self.command(args)
        self.command(["az", "login", "--identity", "--allow-no-subscriptions", "--output", "none"])
        exists = self.read_output([
            "az", "storage", "blob", "exists", "--auth-mode", "login",
            "--account-name", backend["storage_account_name"],
            "--container-name", backend["container_name"], "--name", self.key,
            "--query", "exists", "--output", "json",
        ], "blob-exists.json")
        blob_exists = json.loads(exists)
        if not isinstance(blob_exists, bool):
            raise StageFailure("Storage did not return a valid state-blob existence result.")
        if blob_exists:
            raise StageFailure("New-Sandbox automation requires an unused state key on every attempt; dispatch a new run.")
        manifest_path = self.deployment_dir / "deployment.json"
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text())
            if manifest != {"deployment_id": self.deployment_id, "backend": backend, "repository": self.env["GITHUB_REPOSITORY"]}:
                raise StageFailure("Deployment receipt does not match the selected backend.")
        write_json(manifest_path, {"deployment_id": self.deployment_id, "backend": backend, "repository": self.env["GITHUB_REPOSITORY"]})
        self.command(["terraform", "init", "-input=false", f"-backend-config=key={self.key}"])
        self.command(["terraform", "validate", "-no-color"])
        expression = (
            "jsonencode({arm_auth_mode=var.arm_auth_mode,arm_client_id=var.arm_client_id,"
            "aad_tenant_id=var.aad_tenant_id,subscription_id=var.subscription_id,"
            "base=[var.enable_module_vnet_app,var.enable_module_vm_jumpbox_linux,"
            "var.enable_module_vm_mssql_win,var.enable_module_mssql,var.enable_module_mysql,"
            "var.enable_module_vwan],extras=[var.enable_module_avd,var.enable_module_petstore,"
            "var.enable_module_vnet_onprem]})\n"
        )
        console = self.read_output(["terraform", "console", "-no-color"], "console.txt", expression)
        profile = json.loads(json.loads(console))
        if (
            profile["arm_auth_mode"] != "msi"
            or profile["aad_tenant_id"] != backend["tenant_id"]
            or profile["subscription_id"] != backend["subscription_id"]
            or not profile["arm_client_id"]
            or not all(value is True for value in profile["base"])
            or any(value is not False for value in profile["extras"])
        ):
            raise StageFailure("Inputs do not match the approved MSI, backend, or module scope.")
        write_json(self.directory / "profile.json", profile)
        self.login_provider(profile)
        self.command([
            "pwsh", "-NoLogo", "-NoProfile", "-File",
            "extras/configurations/rg-devops-iac/scripts/Connect-SandboxRunner.ps1",
            "-ProfilePath", str(self.directory / "profile.json"),
        ])
        self.command(["terraform", "plan", "-input=false", "-no-color", f"-out={self.plan}"])
        plan_json = self.directory / "plan.json"
        self.command(["terraform", "show", "-json", str(self.plan)], output=plan_json)
        counts = {action: 0 for action in ("create", "update", "delete")}
        for change in json.loads(plan_json.read_text()).get("resource_changes", []):
            for action in change["change"]["actions"]:
                if action in counts:
                    counts[action] += 1
        plan_json.unlink()
        record = {
            "deployment_id": self.deployment_id, "state_key": self.key,
            "origin_run_id": self.origin_id, "origin_run_url": self.run_base + self.origin_id,
            "run_id": self.run_id, "run_attempt": self.attempt,
            "source_sha": self.source_sha(), "configuration": self.fingerprints(),
            "plan_path": str(self.plan), "plan_sha256": digest(self.plan),
            "created_at": utc_now(), "changes": counts,
        }
        write_json(self.receipt, record)

    def login_provider(self, profile):
        self.env["ARM_TENANT_ID"] = profile["aad_tenant_id"]
        self.command(["az", "login", "--identity", "--client-id", profile["arm_client_id"], "--output", "none"])
        self.command(["az", "account", "set", "--subscription", profile["subscription_id"]])
        account = json.loads(self.read_output(["az", "account", "show", "--output", "json"], "account.json"))
        if account["id"] != profile["subscription_id"] or account["tenantId"] != profile["aad_tenant_id"]:
            raise StageFailure("Azure CLI context does not match the approved deployment.")

    def apply(self):
        if json.loads((self.directory / "preflight-status.json").read_text())["exit_code"] != 0:
            raise StageFailure("Apply requires a successful preflight.")
        record = self.check_receipt()
        self.log.write(f'Verified plan SHA-256: {record["plan_sha256"]}\n')
        profile = json.loads((self.directory / "profile.json").read_text())
        self.login_provider(profile)
        self.command(["terraform", "apply", "-input=false", "-no-color", str(self.plan)])

    def unit_test(self):
        if json.loads((self.directory / "apply-status.json").read_text())["exit_code"] != 0:
            raise StageFailure("Unit-test requires a successful apply.")
        self.check_receipt()
        profile = json.loads((self.directory / "profile.json").read_text())
        self.login_provider(profile)
        self.command(["bash", "scripts/manage-vms.sh", "start"])
        names = json.loads(self.read_output(["terraform", "output", "-json", "resource_names"], "resource-names.json"))
        vm_names = [value for key, value in names.items() if key.startswith("virtual_machine_")]
        if not vm_names:
            raise StageFailure("Approved all-module scope must contain VMs.")
        deadline = time.monotonic() + 600
        while True:
            vms = json.loads(self.read_output([
                "az", "vm", "list", "-g", names["resource_group"], "-d", "--output", "json",
            ], "vm-status.json"))
            states = {vm["name"]: vm.get("powerState") for vm in vms}
            if all(states.get(name) == "VM running" for name in vm_names):
                break
            if time.monotonic() >= deadline:
                raise StageFailure("VM-start gate did not confirm all deployed VMs running.")
            time.sleep(15)
        try:
            self.command([
                "pwsh", "-NoLogo", "-NoProfile", "-File",
                "extras/configurations/rg-devops-iac/scripts/Connect-SandboxRunner.ps1",
                "-ProfilePath", str(self.directory / "profile.json"), "-RunTests",
                "-ResultsJsonPath", str(self.directory / "unit-test-results.json"),
                "-JUnitXmlPath", str(self.directory / "unit-test-results.xml"),
            ])
        finally:
            orchestrator_log = self.root / "Invoke-UnitTests.ps1.log"
            if orchestrator_log.exists():
                orchestrator_log.replace(self.directory / "orchestrator.log")
        if any(not (self.directory / name).exists() for name in ("unit-test-results.json", "unit-test-results.xml")):
            raise StageFailure("Tests completed without both requested result files.", 2)

    def prepare_evidence(self):
        names = ("unit-test-results.json", "unit-test-results.xml")
        available = [name for name in names if (self.directory / name).is_file()]
        if not available:
            self.summary("\nUnit-test evidence unavailable: no structured result files were produced. No test results were fabricated.\n")
            with Path(self.env["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
                stream.write("ready=false\n")
            return
        for name in available:
            path = self.directory / name
            if name.endswith(".json"):
                record = json.loads(path.read_text())
                if (
                    not isinstance(record, dict) or record.get("schemaVersion") != 1
                    or type(record.get("exitCode")) is not int or record["exitCode"] not in (0, 1, 2)
                ):
                    raise StageFailure("Invalid unit-test JSON; evidence was not published.")
            elif ET.parse(path).getroot().tag != "testsuites":
                raise StageFailure("Invalid JUnit XML; evidence was not published.")
        staging = Path(self.env["RUNNER_TEMP"]) / f"sandbox-test-evidence-{self.run_id}-{self.attempt}"
        staging.mkdir(mode=0o700, exist_ok=False)
        for name in available:
            shutil.copyfile(self.directory / name, staging / name)
        with Path(self.env["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
            stream.write(
                f"json_path={staging / names[0] if names[0] in available else ''}\n"
                f"xml_path={staging / names[1] if names[1] in available else ''}\n"
                f"name=unit-test-evidence-{self.deployment_id}-{self.run_id}-{self.attempt}\n"
                "ready=true\n"
            )
        missing = [name for name in names if name not in available]
        if missing:
            self.summary(f"\nPartial unit-test evidence: not produced: {', '.join(missing)}.\n")

    def report(self):
        stages = (
            ("preflight", "PREFLIGHT_OUTCOME"), ("apply", "APPLY_OUTCOME"), ("unit-test", "UNIT_TEST_OUTCOME"),
        )
        self.summary("## Sandbox stage results\n\n| Stage | Result |\n|---|---|\n")
        for stage, variable in stages:
            outcome = self.env.get(variable, "")
            result = {"success": "PASS", "failure": "FAIL", "skipped": "NOT RUN", "cancelled": "INCOMPLETE"}.get(outcome, "NOT COMPLETED")
            self.summary(f"| {stage} | {result} |\n")
        for stage, _ in stages:
            status_path = self.directory / f"{stage}-status.json"
            if status_path.exists():
                status = json.loads(status_path.read_text())
                self.summary(
                    f"\n{stage}: exit `{status['exit_code']}`, start `{status['started_at']}`, "
                    f"end `{status['finished_at']}`.\n\n"
                    f"Private log: `~/.local/state/azuresandbox/deployments/{self.deployment_id}/"
                    f"runs/{self.run_id}-{self.attempt}/{stage}.log`\n\n"
                )
            elif self.env.get(dict(stages)[stage]) not in ("", "skipped"):
                self.summary(f"\n{stage}: no final exit record; execution or result logging is incomplete.\n\n")
        if self.receipt.exists():
            record = json.loads(self.receipt.read_text())
            self.summary(
                f"\nDeployment: `{self.deployment_id}`; state key: `{self.key}`.\n\n"
                f"[Originating run]({self.run_base}{self.origin_id}) / [Current run]({self.run_base}{self.run_id})\n\n"
                f"Plan SHA-256: `{record['plan_sha256']}`\n\nSource commit: `{record['source_sha']}`\n\n"
                f"Plan created: `{record['created_at']}`; attempt: `{self.attempt}`.\n\n"
                f"Changes: create={record['changes']['create']}, update={record['changes']['update']}, "
                f"delete={record['changes']['delete']}.\n\n"
                f"Private plan: `~/.local/state/azuresandbox/deployments/{self.deployment_id}/"
                f"runs/{self.run_id}-{self.attempt}/sandbox.tfplan`\n\n"
                "Preflight PASS is not proof that infrastructure was applied or tests passed.\n"
            )
        results_path = self.directory / "unit-test-results.json"
        if results_path.exists():
            totals = json.loads(results_path.read_text())["totals"]
            if any(type(totals.get(key)) is not int for key in ("passed", "failed", "suitesSkipped")):
                raise StageFailure("Invalid unit-test totals; do not publish raw results.")
            self.summary(
                f"\nUnit-test counts: passed={totals['passed']}, failed={totals['failed']}, "
                f"skipped suites={totals['suitesSkipped']}.\n"
            )
        artifact_url = self.env.get("UNIT_TEST_ARTIFACT_URL", "")
        if self.env.get("UNIT_TEST_ARTIFACT_OUTCOME") == "success" and artifact_url:
            self.summary(f"\n[Download sanitized unit-test evidence (JSON/JUnit)]({artifact_url})\n")
        elif self.env.get("UNIT_TEST_ARTIFACT_OUTCOME") == "failure":
            self.summary("\nUnit-test evidence upload failed; structured results remain on the runner.\n")

    def execute(self, stage):
        self.stage = stage
        if stage == "summary":
            self.report()
            return 0
        if stage not in ("preflight", "apply", "unit-test"):
            raise StageFailure("Invalid stage.")
        if stage == "preflight":
            self.deployment_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chmod(self.deployment_dir, 0o700)
            self.directory.mkdir(parents=True, exist_ok=False, mode=0o700)
        started = utc_now()
        code = 0
        with (self.directory / f"{stage}.log").open("x", encoding="utf-8") as stream:
            self.log = stream
            stream.write(f"Stage: {stage}\nStarted: {started}\n")
            try:
                {"preflight": self.preflight, "apply": self.apply, "unit-test": self.unit_test}[stage]()
            except StageFailure as error:
                traceback.print_exc(file=stream)
                code = error.code
            except (OSError, ValueError, KeyError, TypeError):
                traceback.print_exc(file=stream)
                code = 1
            if stage == "unit-test":
                try:
                    self.prepare_evidence()
                except (StageFailure, OSError, ValueError, KeyError, TypeError, ET.ParseError):
                    traceback.print_exc(file=stream)
                    self.summary("\nUnit-test evidence preparation failed; no artifact was approved for upload. Check the private result files and staging permissions.\n")
                    code = code or 1
            finished = utc_now()
            stream.write(f"\nFinished: {finished}\nStage exit code: {code}\n")
            stream.flush()
        write_json(self.directory / f"{stage}-status.json", {
            "started_at": started, "finished_at": finished, "exit_code": code,
        })
        if code:
            print(f"::error::{stage} failed (exit {code}); review its private runner log.")
        else:
            print(f"{stage}: PASS. Raw output retained privately on the runner.")
        return code


if __name__ == "__main__":
    try:
        sys.exit(Runner().execute(sys.argv[1]))
    except (StageFailure, OSError, KeyError, ValueError, IndexError, ET.ParseError):
        print("::error::Runner setup/reporting failed; check dispatch inputs, private records, and filesystem permissions.")
        sys.exit(1)
