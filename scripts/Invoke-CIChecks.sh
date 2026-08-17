#!/bin/bash

# Local pre-push runner for the repository's PR-time CI gates.
#
# Runs the same lint/scan commands the GitHub Actions workflows under
# .github/workflows/ run, so contributors can reproduce CI results locally and
# avoid the push -> CI-fail -> fix -> re-push loop. Each check reads the same
# shared config file CI uses (single source of truth), and versions are pinned
# to match CI where a mismatch could produce false negatives.
#
# NOTE: `terraform init` / `terraform validate` are intentionally NOT run here.
# They are covered by the sandbox deployment workflow (terraform init before
# apply); this runner covers only the standalone static-analysis gates.
#
# Usage:
#   ./scripts/Invoke-CIChecks.sh                 # run every applicable check
#   ./scripts/Invoke-CIChecks.sh bash terraform  # run only the named checks
#
# Available checks (map 1:1 to a CI workflow):
#   bash        ShellCheck                  (ci-bash.yml)        pin 0.10.0
#   powershell  PSScriptAnalyzer            (ci-powershell.yml)  pin 1.24.0
#   markdown    markdownlint-cli2           (ci-docs.yml)        pin 0.22.1
#   links       lychee (offline/internal)   (ci-docs.yml)
#   actions     actionlint                  (ci-actions.yml)     pin 1.7.12
#   secrets     gitleaks                    (ci-secrets.yml)     pin 8.30.1
#   terraform   terraform fmt + tflint      (ci-terraform.yml)   tflint pin v0.64.0
#
# A missing tool is reported as SKIPPED (with an install hint) and does not fail
# the run, but the final summary flags it so you know the gate was not verified.
# Exit code: 0 when nothing FAILED, non-zero otherwise (CI-friendly).

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root" || exit 1

all_checks=(bash powershell markdown links actions secrets terraform)
if [ "$#" -gt 0 ]; then
    checks=("$@")
else
    checks=("${all_checks[@]}")
fi

failed=()
skipped=()
passed=()

have() { command -v "$1" > /dev/null 2>&1; }

run_check() {
    local name="$1"
    printf '\n=== %s ===\n' "$name"
    shift
    if "$@"; then
        passed+=("$name")
    else
        failed+=("$name")
    fi
}

skip() {
    local name="$1" hint="$2"
    printf '\n=== %s ===\nSKIPPED: %s\n' "$name" "$hint"
    skipped+=("$name")
}

check_bash() {
    have shellcheck || { skip bash "install shellcheck 0.10.0 (https://github.com/koalaman/shellcheck/releases)"; return; }
    run_check bash "$repo_root/scripts/Invoke-ShellCheck.sh"
}

check_powershell() {
    have pwsh || { skip powershell "install PowerShell 7.x (pwsh)"; return; }
    run_check powershell pwsh -NoProfile -Command '
        if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
            Write-Host "SKIPPED: install PSScriptAnalyzer 1.24.0 (Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0)"; exit 0
        }
        $r = Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -Severity @("Error","Warning")
        if ($r) { $r | Format-Table -AutoSize Severity, RuleName, ScriptName, Line, Message | Out-String -Width 200 | Write-Host; exit 1 }
        Write-Host "PSScriptAnalyzer: no issues found."'
}

check_markdown() {
    have npx || { skip markdown "install Node.js/npm (provides npx)"; return; }
    run_check markdown npx --yes markdownlint-cli2@0.22.1
}

check_links() {
    have lychee || { skip links "install lychee (https://github.com/lycheeverse/lychee)"; return; }
    run_check links lychee --offline --no-progress './**/*.md'
}

check_actions() {
    have actionlint || { skip actions "install actionlint 1.7.12 (https://github.com/rhysd/actionlint)"; return; }
    run_check actions actionlint -color
}

check_secrets() {
    have gitleaks || { skip secrets "install gitleaks 8.30.1 (https://github.com/gitleaks/gitleaks)"; return; }
    run_check secrets gitleaks dir . --redact --verbose --no-banner
}

check_terraform() {
    have terraform || { skip "terraform fmt" "install terraform"; }
    if have terraform; then
        run_check "terraform fmt" terraform fmt -check -recursive -diff
    fi
    if have tflint; then
        # tflint --init only initializes the current directory, so initialize
        # every directory that pins its own plugin before the recursive run.
        while IFS= read -r dir; do
            tflint --init --chdir="$dir" > /dev/null || true
        done < <(find . -name .tflint.hcl -printf '%h\n' | sort -u)
        run_check tflint tflint --recursive
    else
        skip tflint "install tflint v0.64.0 (https://github.com/terraform-linters/tflint)"
    fi
}

for c in "${checks[@]}"; do
    case "$c" in
        bash) check_bash ;;
        powershell) check_powershell ;;
        markdown) check_markdown ;;
        links) check_links ;;
        actions) check_actions ;;
        secrets) check_secrets ;;
        terraform) check_terraform ;;
        *) printf "ERROR: unknown check '%s' (valid: %s)\n" "$c" "${all_checks[*]}" >&2; exit 2 ;;
    esac
done

printf '\n===== summary =====\n'
[ "${#passed[@]}" -gt 0 ] && printf 'PASSED:  %s\n' "${passed[*]}"
[ "${#skipped[@]}" -gt 0 ] && printf 'SKIPPED: %s\n' "${skipped[*]}"
[ "${#failed[@]}" -gt 0 ] && printf 'FAILED:  %s\n' "${failed[*]}"

if [ "${#failed[@]}" -gt 0 ]; then
    exit 1
fi
printf 'No failures.\n'
