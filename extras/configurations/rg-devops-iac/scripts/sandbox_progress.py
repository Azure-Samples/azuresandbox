"""Allowlisted deployment/test progress; never return arbitrary log text."""

import re


PROGRESS = re.compile(
    r"^((?:module\.[A-Za-z_][A-Za-z0-9_-]*(?:\[[0-9]+\])?\.)*"
    r"(?:azurerm_[A-Za-z0-9_]+|azapi_[A-Za-z0-9_]+|azuread_[A-Za-z0-9_]+"
    r"|random_[A-Za-z0-9_]+|time_[A-Za-z0-9_]+|tls_[A-Za-z0-9_]+"
    r"|cloudinit_[A-Za-z0-9_]+|null_resource|terraform_data)"
    r"\.[A-Za-z_][A-Za-z0-9_-]*(?:\[[0-9]+\])?): "
    r"(Still (?:creating|modifying|destroying)\.\.\. \[[0-9hms ]+ elapsed\]"
    r"|(?:Creating|Modifying|Destroying)\.\.\."
    r"|(?:Creation|Modifications|Destruction) complete after [0-9hms ]+)"
)

TEST_MODULES = {
    "vnet-shared", "vnet-app", "vm-jumpbox-linux", "vm-mssql-win",
    "mssql", "mysql", "vwan", "avd", "petstore", "vnet-onprem", "integration",
}
INTEGRATIONS = {
    "SSH: jumpwin1 -> jumplinux1": "SSH connectivity",
    "SQL: jumpwin1 -> mssqlwin1": "SQL connectivity",
    "Azure SQL: jumpwin1 -> testdb": "Azure SQL connectivity",
    "MySQL: jumpwin1 -> mysql": "MySQL connectivity",
    "Petstore API: jumpwin1 -> petstore": "Petstore API connectivity",
    "P2S VPN: local -> sandbox endpoints": "P2S VPN connectivity",
    "AVD: personal session host config": "AVD personal configuration",
    "AVD: remoteapp session host config": "AVD remoteapp configuration",
    "Onprem -> cloud connectivity": "On-premises to cloud connectivity",
    "Cloud -> onprem DNS": "Cloud to on-premises DNS",
}


def filter_progress(lines, limit=4):
    latest = {}
    for line in lines:
        match = PROGRESS.match(line)
        if match:
            latest.pop(match[1], None)
            latest[match[1]] = match[0].rstrip()
    return list(latest.values())[-limit:]


def filter_test_progress(lines, limit=4):
    latest = {}
    counts = {}
    for line in lines:
        header = re.search(r"\b(Module|Integration): (.+?) \|", line)
        if header:
            kind, name = header.groups()
            label = name if kind == "Module" and name in TEST_MODULES else INTEGRATIONS.get(name)
            if label:
                key = f"{kind}: {label}"
                latest.pop(key, None)
                latest[key] = key
        result = re.search(r"\[MODULE:([A-Za-z0-9_-]+)\] \[(PASS|FAIL|SKIP|SUMMARY)\]", line)
        if result and result[1] in TEST_MODULES:
            module, status = result.groups()
            key = f"Results: {module}"
            summary = re.match(r" Passed:\s*([0-9]+)\s+Failed:\s*([0-9]+)\s+Total:\s*([0-9]+)\b", line[result.end():])
            if status == "SUMMARY" and summary:
                passed, failed, total = summary.groups()
                message = f"{module}: Passed={passed} Failed={failed} Total={total}"
            elif status in ("PASS", "FAIL", "SKIP"):
                observed = counts.setdefault(module, dict.fromkeys(("PASS", "FAIL", "SKIP"), 0))
                observed[status] += 1
                message = f"{module}: recent result lines " + " ".join(f"{name}={value}" for name, value in observed.items())
            else:
                message = f"{module}: result details withheld"
            latest.pop(key, None)
            latest[key] = message
        overall = re.search(r"\bOverall: Passed=([0-9]+) Failed=([0-9]+) Total=([0-9]+)\b", line)
        if overall:
            latest["overall"] = f"Overall: Passed={overall[1]} Failed={overall[2]} Total={overall[3]}"
        outcome = re.search(r"\bRESULT: (PASS|FAIL)\s*$", line)
        if outcome:
            latest["result"] = f"RESULT: {outcome[1]}"
    return list(latest.values())[-limit:]


def read_progress(path, start, stage="apply"):
    with path.open("rb") as stream:
        end = stream.seek(0, 2)
        offset = max(start, end - 65536)
        if offset:
            stream.seek(offset - 1)
            if stream.read(1) != b"\n":
                stream.readline()
        else:
            stream.seek(0)
        data = stream.read(65536)
    lines = data.decode("utf-8", errors="replace").splitlines()
    if lines and not data.endswith(b"\n"):
        lines.pop()
    return filter_test_progress(lines) if stage == "unit-test" else filter_progress(lines)
