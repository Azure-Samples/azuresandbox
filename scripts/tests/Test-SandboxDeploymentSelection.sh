#!/bin/bash

# Tests the "Select trusted deployment path" step of
# .github/workflows/sandbox-deployment.yml without GitHub or Azure access.
#
# The step's run: script is extracted from the workflow YAML and executed the
# way GitHub runs a bash step, against fixture events and environment, so the
# test always exercises the exact code that ships. Also asserts the manual
# source_branch input, the checkout/status wiring that depend on it, and that
# only the sandbox job can request a GitHub OIDC token (id-token: write).
#
# Usage: ./scripts/tests/Test-SandboxDeploymentSelection.sh
# Requires: bash, jq, python3 with PyYAML. Exit code 0 only if every case passes.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
workflow="$repo_root/.github/workflows/sandbox-deployment.yml"
repository="Azure-Samples/azuresandbox"
head_sha="1111111111111111111111111111111111111111"
base_sha="2222222222222222222222222222222222222222"

for tool in jq python3; do
    command -v "$tool" > /dev/null || { echo "ERROR: $tool is required." >&2; exit 2; }
done
python3 -c 'import yaml' 2> /dev/null || { echo "ERROR: python3 PyYAML is required." >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Extract the selection step script and the workflow facts asserted below.
if ! python3 - "$workflow" "$work" << 'PY'; then
import json, sys, yaml
workflow, work = sys.argv[1], sys.argv[2]
with open(workflow, encoding="utf-8") as f:
    doc = yaml.safe_load(f)
# PyYAML parses the bare "on" key as boolean True.
triggers = doc.get("on", doc.get(True))
steps = [s for s in doc["jobs"]["selection"]["steps"] if s.get("id") == "select"]
if len(steps) != 1:
    sys.exit("selection job must have exactly one step with id 'select'")
with open(f"{work}/select.sh", "w", encoding="utf-8") as f:
    f.write(steps[0]["run"])
checkout = [s for s in doc["jobs"]["sandbox"]["steps"] if str(s.get("uses", "")).startswith("actions/checkout@")]
facts = {
    "source_input": triggers["workflow_dispatch"]["inputs"].get("source_branch"),
    "select_env": steps[0].get("env", {}),
    "checkout": [s.get("with", {}) for s in checkout],
    "job_if": {name: doc["jobs"][name].get("if", "") for name in ("pending_status", "static_ci", "deployment_status")},
    "permissions": doc.get("permissions"),
    "id_token_jobs": sorted(name for name, job in doc["jobs"].items()
                            if isinstance(job.get("permissions"), dict) and "id-token" in job["permissions"]),
    "sandbox_id_token": doc["jobs"]["sandbox"].get("permissions", {}).get("id-token"),
    "write_all_jobs": sorted(name for name, job in doc["jobs"].items() if isinstance(job.get("permissions"), str)),
}
with open(f"{work}/facts.json", "w", encoding="utf-8") as f:
    json.dump(facts, f)
PY
    echo "ERROR: could not parse $workflow" >&2
    exit 2
fi

passed=0
failed=0

pass() { printf '[PASS] %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf '[FAIL] %s: %s\n' "$1" "$2"; failed=$((failed + 1)); }

# write_pr_event <file> [jq filter applied to a ready, eligible release PR event]
write_pr_event() {
    jq -n --arg repo "$repository" --arg head "$head_sha" --arg base "$base_sha" '{
        action: "synchronize",
        pull_request: {
            draft: false,
            head: {ref: "vnext", sha: $head, repo: {full_name: $repo}},
            base: {ref: "main", sha: $base, repo: {full_name: $repo}}
        }
    }' | jq "${2:-.}" > "$1"
}

# run_select <case dir> <event name> <ref> <run_through> <source_branch> [event file]
# Runs the step like GitHub's bash shell (bash -e -o pipefail) in a clean env.
run_select() {
    local dir="$1"
    mkdir -p "$dir"
    : > "$dir/output"
    : > "$dir/summary"
    env -i PATH="$PATH" HOME="$work" \
        GITHUB_EVENT_NAME="$2" GITHUB_REF="$3" GITHUB_REPOSITORY="$repository" \
        GITHUB_EVENT_PATH="${6:-/dev/null}" GITHUB_OUTPUT="$dir/output" \
        GITHUB_STEP_SUMMARY="$dir/summary" \
        MANUAL_RUN_THROUGH="$4" MANUAL_SOURCE_BRANCH="$5" \
        bash --noprofile --norc -e -o pipefail "$work/select.sh" > "$dir/log" 2>&1
}

# output_is <case dir> <expected GITHUB_OUTPUT content, newline-separated>
output_is() { [[ "$(sort "$1/output")" == "$(printf '%s\n' "$2" | sort)" ]]; }

n=0
next_dir() { n=$((n + 1)); printf '%s/case-%d' "$work" "$n"; }

# --- Manual path: both sources x every stage ---------------------------------
for source in vnext main; do
    for stage in preflight apply unit-test; do
        name="manual source=$source stage=$stage"
        dir="$(next_dir)"
        if ! run_select "$dir" workflow_dispatch refs/heads/main "$stage" "$source"; then
            fail "$name" "exited non-zero: $(cat "$dir/log")"
        elif ! output_is "$dir" "source_ref=refs/heads/$source
run_through=$stage
environment=sandbox-deployment
deploy=true"; then
            fail "$name" "unexpected outputs: $(tr '\n' ' ' < "$dir/output")"
        elif ! grep -q "\`$source\` branch" "$dir/summary"; then
            fail "$name" "run summary does not name the source branch"
        else
            pass "$name"
        fi
    done
done

# --- Manual path: invalid sources, stages, and workflow context --------------
invalid_sources=("" "feature/x" "refs/heads/main" "refs/tags/v1.0" "v1.0" "$head_sha" "fork:main" "Main" "main " "vnext;id")
for source in "${invalid_sources[@]}"; do
    name="manual invalid source='$source'"
    dir="$(next_dir)"
    if run_select "$dir" workflow_dispatch refs/heads/main apply "$source"; then
        fail "$name" "was accepted"
    elif [[ -s "$dir/output" ]]; then
        fail "$name" "wrote outputs before failing"
    elif ! grep -q 'Invalid deployment source' "$dir/log"; then
        fail "$name" "missing explicit error: $(cat "$dir/log")"
    else
        pass "$name"
    fi
done

for stage in "" destroy; do
    name="manual invalid stage='$stage'"
    dir="$(next_dir)"
    if run_select "$dir" workflow_dispatch refs/heads/main "$stage" main || [[ -s "$dir/output" ]]; then
        fail "$name" "was accepted or wrote outputs"
    else
        pass "$name"
    fi
done

name="manual dispatch outside the trusted main context"
dir="$(next_dir)"
if run_select "$dir" workflow_dispatch refs/heads/vnext apply main || [[ -s "$dir/output" ]]; then
    fail "$name" "was accepted or wrote outputs"
else
    pass "$name"
fi

# --- Release PR path: unchanged, and never influenced by the manual input ----
for source in "" main; do
    name="release PR deploys exact head SHA (MANUAL_SOURCE_BRANCH='$source')"
    dir="$(next_dir)"
    write_pr_event "$dir.json"
    if ! run_select "$dir" pull_request_target refs/heads/main "" "$source" "$dir.json"; then
        fail "$name" "exited non-zero: $(cat "$dir/log")"
    elif ! output_is "$dir" "source_ref=$head_sha
base_sha=$base_sha
run_through=unit-test
environment=sandbox-release-gate
deploy=true"; then
        fail "$name" "unexpected outputs: $(tr '\n' ' ' < "$dir/output")"
    else
        pass "$name"
    fi
done

for filter in '.pull_request.draft = true' '.action = "edited"'; do
    name="release PR no deployment ($filter)"
    dir="$(next_dir)"
    write_pr_event "$dir.json" "$filter"
    if ! run_select "$dir" pull_request_target refs/heads/main "" main "$dir.json"; then
        fail "$name" "exited non-zero: $(cat "$dir/log")"
    elif ! output_is "$dir" "deploy=false"; then
        fail "$name" "unexpected outputs: $(tr '\n' ' ' < "$dir/output")"
    else
        pass "$name"
    fi
done

name="release PR retarget (edited with base change) deploys"
dir="$(next_dir)"
write_pr_event "$dir.json" '.action = "edited" | .changes.base.ref.from = "vnext"'
if run_select "$dir" pull_request_target refs/heads/main "" "" "$dir.json" && grep -qx 'deploy=true' "$dir/output"; then
    pass "$name"
else
    fail "$name" "did not request deployment: $(cat "$dir/log")"
fi

for filter in '.pull_request.head.repo.full_name = "someone/fork"' '.pull_request.head.ref = "main"' \
    '.pull_request.head.ref = "feature/x"' '.pull_request.base.ref = "vnext"'; do
    name="release PR ineligible ($filter)"
    dir="$(next_dir)"
    write_pr_event "$dir.json" "$filter"
    if run_select "$dir" pull_request_target refs/heads/main "" main "$dir.json" || [[ -s "$dir/output" ]]; then
        fail "$name" "was accepted or wrote outputs"
    else
        pass "$name"
    fi
done

# --- Static wiring ------------------------------------------------------------
facts="$work/facts.json"

name="source_branch input is a vnext/main choice defaulting to vnext"
if jq -e '.source_input | .type == "choice" and .options == ["vnext", "main"] and .default == "vnext"' "$facts" > /dev/null; then
    pass "$name"
else
    fail "$name" "$(jq -c '.source_input' "$facts")"
fi

name="selection step reads the manual input only through env"
if jq -e '.select_env.MANUAL_SOURCE_BRANCH == "${{ inputs.source_branch }}"' "$facts" > /dev/null &&
    ! grep -q 'inputs\.' "$work/select.sh"; then
    pass "$name"
else
    fail "$name" "MANUAL_SOURCE_BRANCH env wiring missing or inputs interpolated into the script"
fi

name="sandbox checkout uses the validated source_ref from this repository"
if jq -e '.checkout | length == 1 and (.[0].ref == "${{ needs.selection.outputs.source_ref }}") and (.[0] | has("repository") | not)' "$facts" > /dev/null; then
    pass "$name"
else
    fail "$name" "$(jq -c '.checkout' "$facts")"
fi

name="release status jobs stay pull_request_target-only"
if jq -e '.job_if | to_entries | all(.value | contains("github.event_name == '\''pull_request_target'\''"))' "$facts" > /dev/null; then
    pass "$name"
else
    fail "$name" "$(jq -c '.job_if' "$facts")"
fi

name="only the sandbox job can request an OIDC token"
if jq -e '(.permissions | type == "object" and (has("id-token") | not)) and .id_token_jobs == ["sandbox"] and .sandbox_id_token == "write" and .write_all_jobs == []' "$facts" > /dev/null; then
    pass "$name"
else
    fail "$name" "$(jq -c '{permissions, id_token_jobs, sandbox_id_token, write_all_jobs}' "$facts")"
fi

printf '\nPassed=%d Failed=%d\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
