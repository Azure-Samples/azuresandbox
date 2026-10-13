#!/usr/bin/env python3
"""Collect read-only, sanitized runner/log progress without opening Terraform state."""

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import pwd
import re
import subprocess
import time

from sandbox_progress import PROGRESS, filter_progress


def runner_service():
    result = subprocess.run(
        ["systemctl", "list-units", "--all", "--type=service", "--plain",
         "--no-legend", "actions.runner.*"],
        check=True, capture_output=True, text=True,
    )
    units = [line.split()[0] for line in result.stdout.splitlines() if line.strip()]
    if len(units) != 1:
        raise ValueError("Expected exactly one runner service.")
    unit = units[0]
    user = subprocess.run(
        ["systemctl", "show", unit, "--property=User", "--value"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    return unit, Path(pwd.getpwnam(user).pw_dir)


def process_counts():
    counts = {"Runner.Listener": 0, "Runner.Worker": 0, "terraform": 0, "pwsh": 0}
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            name = (process / "comm").read_text().strip()
        except (FileNotFoundError, ProcessLookupError):
            continue
        if name in counts:
            counts[name] += 1
    return counts


def read_log(path):
    if not path.exists():
        return None, []
    stat = path.stat()
    with path.open("rb") as stream:
        header = stream.read(512).decode("utf-8", errors="replace")
        stream.seek(max(0, stat.st_size - 65536))
        tail = stream.read().decode("utf-8", errors="replace").splitlines()
    started = re.search(r"(?m)^Started: (.+)$", header)
    elapsed = None
    if started:
        when = dt.datetime.fromisoformat(started[1])
        elapsed = max(0, int((dt.datetime.now(dt.timezone.utc) - when).total_seconds()))
    return {"bytes": stat.st_size, "modified": stat.st_mtime, "elapsed_seconds": elapsed}, tail


def snapshot(unit, directory, previous):
    service = subprocess.run(
        ["systemctl", "show", unit, "--property=ActiveState", "--value"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    stages = {}
    stage = "awaiting-job"
    log_info = None
    lines = []
    for name in ("preflight", "apply", "unit-test"):
        status = directory / f"{name}-status.json"
        if status.exists():
            value = json.loads(status.read_text())
            code = value["exit_code"]
            if type(code) is not int:
                raise ValueError("Invalid stage exit code.")
            stages[name] = {"exit_code": code}
        info, tail = read_log(directory / f"{name}.log")
        if info is not None:
            stage, log_info, lines = name, info, tail
    now = time.time()
    changed_at = previous.get("changed_at", now)
    fingerprint = {key: log_info[key] for key in ("bytes", "modified")} if log_info else None
    old_log = previous.get("log")
    old_fingerprint = {key: old_log[key] for key in ("bytes", "modified")} if old_log else None
    if stage != previous.get("stage") or fingerprint != old_fingerprint:
        changed_at = now
    quiet = int(now - changed_at)
    terminal = any(value["exit_code"] != 0 for value in stages.values()) or "unit-test" in stages
    health = "waiting" if stage == "awaiting-job" else "healthy"
    if terminal:
        health = "failed" if any(value["exit_code"] != 0 for value in stages.values()) else "completed"
    elif stage != "awaiting-job" and quiet >= 600:
        health = "suspected-hang"
    elif stage != "awaiting-job" and quiet >= 240:
        health = "possibly-stalled"
    if service != "active" and not terminal:
        health = "runner-unavailable"
    progress = filter_progress(lines)
    result = {
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
        "runner_service": service,
        "processes": process_counts(),
        "stage": stage,
        "stages": stages,
        "log": log_info,
        "quiet_seconds": quiet,
        "health": health,
        "progress": progress[-4:],
        "error_seen": any(line.startswith("Error:") for line in lines),
        "terminal": terminal,
        "changed_at": changed_at,
    }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--attempt", default="1")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not all(re.fullmatch(r"[1-9][0-9]*", value) for value in (args.run_id, args.attempt)):
        parser.error("Run ID and attempt must be positive integers.")
    os.umask(0o077)
    args.output.mkdir(parents=True, exist_ok=True)
    unit, home = runner_service()
    directory = (
        home / ".local/state/azuresandbox/deployments" / f"sandbox-{args.run_id}"
        / "runs" / f"{args.run_id}-{args.attempt}"
    )
    previous = {}
    deadline = time.monotonic() + 21600
    while time.monotonic() < deadline:
        result = snapshot(unit, directory, previous)
        encoded = json.dumps(result)
        temporary = args.output / "latest.tmp"
        temporary.write_text(encoded + "\n")
        temporary.replace(args.output / "latest.json")
        with (args.output / "history.jsonl").open("a") as stream:
            stream.write(encoded + "\n")
        previous = result
        if result["terminal"]:
            return
        time.sleep(120)
    raise TimeoutError("Monitor lifetime expired after six hours.")


if __name__ == "__main__":
    main()
