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
#   bash        ShellCheck                  (ci-bash.yml)        pin 0.11.0
#   powershell  PSScriptAnalyzer            (ci-powershell.yml)  pin 1.25.0
#   markdown    markdownlint-cli2           (ci-docs.yml)        pin 0.24.0, requires Node.js 20 (ci-docs.yml actions/setup-node)
#   links       lychee (offline/internal)   (ci-docs.yml)
#   actions     actionlint                  (ci-actions.yml)     pin 1.7.12
#   secrets     gitleaks                    (ci-secrets.yml)     pin 8.30.1
#   terraform   terraform fmt + tflint      (ci-terraform.yml)   tflint pin v0.65.0
#
# A missing tool is reported as SKIPPED (with an install hint) and does not fail
# the run, but the final summary flags it so you know the gate was not verified.
# Exit code: 0 when nothing FAILED, non-zero otherwise (CI-friendly).
#
# CI runs on a clean checkout, so git-ignored files (terraform.tfvars, *.tfstate,
# *.tfplan, .terraform/) are excluded from every check here too, except tflint,
# which still auto-loads a module directory's terraform.tfvars when evaluating.
#
# The tool version pins above are mirrored from the CI workflows and are NOT
# tracked by Dependabot. The scheduled ci-tool-versions.yml workflow (and its
# scripts/Check-ToolVersionDrift.sh helper) watches for upstream drift and files
# a tracking issue when any pin here or in a workflow falls behind latest.

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

# CI runs on a clean checkout, so it never sees git-ignored files such as
# terraform.tfvars, *.tfstate, *.tfplan, or .terraform/. Checks that would
# otherwise walk the working tree are fed this list instead: tracked plus
# untracked-but-not-ignored files that still exist on disk, NUL-delimited.
# Optional arguments are git pathspecs (e.g. '*.tf').
ci_files() {
    local f
    while IFS= read -r -d '' f; do
        if [ -f "$f" ]; then printf '%s\0' "$f"; fi
    done < <(git ls-files -z --cached --others --exclude-standard -- "$@")
}

# gitleaks has no option to honor .gitignore when scanning a directory, so copy
# the CI-visible files into a scratch directory and scan that instead.
scan_secrets() {
    local stage rc
    stage="$(mktemp -d)"
    ci_files | xargs -0 -r cp --parents -t "$stage" --
    (cd "$stage" && gitleaks dir . --redact --verbose --no-banner)
    rc=$?
    rm -rf "$stage"
    return "$rc"
}

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
    have shellcheck || { skip bash "install shellcheck 0.11.0 (https://github.com/koalaman/shellcheck/releases)"; return; }
    run_check bash "$repo_root/scripts/Invoke-ShellCheck.sh"
}

check_powershell() {
    have pwsh || { skip powershell "install PowerShell 7.x (pwsh)"; return; }
    # ci-powershell.yml uses `-Path . -Recurse` on a clean checkout. Locally that
    # would also scan git-ignored content such as .terraform/modules, so analyze
    # only the tracked and untracked, non-ignored files CI could see.
    run_check powershell pwsh -NoProfile -Command '
        if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
            Write-Host "SKIPPED: install PSScriptAnalyzer 1.25.0 (Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0)"; exit 0
        }
        $list = git ls-files -z --cached --others --exclude-standard -- "*.ps1" "*.psm1" "*.psd1"
        if ($LASTEXITCODE -ne 0) { Write-Host "git ls-files failed."; exit 1 }
        $files = @(($list -join "") -split "`0" | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Sort-Object -Unique)
        $r = @(foreach ($f in $files) {
            Invoke-ScriptAnalyzer -Path $f -Settings ./PSScriptAnalyzerSettings.psd1 -Severity @("Error","Warning")
        })
        Write-Host "PSScriptAnalyzer: analyzed $($files.Count) file(s)."
        if ($r) { $r | Format-Table -AutoSize Severity, RuleName, ScriptName, Line, Message | Out-String -Width 200 | Write-Host; exit 1 }
        Write-Host "PSScriptAnalyzer: no issues found."'
}

check_markdown() {
    have npx || { skip markdown "install Node.js/npm (provides npx)"; return; }
    # ci-docs.yml runs markdownlint-cli2 under actions/setup-node@v7 pinned to
    # Node 20. This isn't a hard requirement (markdownlint-cli2 runs fine on
    # other Node majors), but a mismatch is a plausible source of local-vs-CI
    # false negatives, so warn rather than silently diverge.
    local node_major
    node_major="$(node --version 2> /dev/null | grep -oP '^v\K[0-9]+')"
    if [ -n "$node_major" ] && [ "$node_major" != "20" ]; then
        printf '\n=== markdown ===\nWARNING: Node.js v%s detected; ci-docs.yml pins Node 20 (actions/setup-node@v7). Install Node 20.x for full CI parity.\n' "$node_major"
    fi
    run_check markdown npx --yes markdownlint-cli2@0.24.0
}

check_links() {
    have lychee || { skip links "install lychee (https://github.com/lycheeverse/lychee)"; return; }
    # ci-docs.yml passes the glob './**/*.md', which lychee expands without
    # honoring .gitignore; pass the CI-visible Markdown files explicitly instead.
    # The glob also skips hidden directories (e.g. .github/), so exclude those too.
    local md_files=()
    mapfile -d '' -t md_files < <(ci_files '*.md' ':(exclude,glob)**/.*/**')
    run_check links lychee --offline --no-progress "${md_files[@]}"
}

check_actions() {
    have actionlint || { skip actions "install actionlint 1.7.12 (https://github.com/rhysd/actionlint)"; return; }
    run_check actions actionlint -color
}

check_secrets() {
    have gitleaks || { skip secrets "install gitleaks 8.30.1 (https://github.com/gitleaks/gitleaks)"; return; }
    run_check secrets scan_secrets
}

check_terraform() {
    have terraform || { skip "terraform fmt" "install terraform"; }
    if have terraform; then
        # ci-terraform.yml runs `terraform fmt -check -recursive`; pass the same
        # file types explicitly so git-ignored files (terraform.tfvars) are skipped.
        local tf_files=()
        mapfile -d '' -t tf_files < <(ci_files '*.tf' '*.tfvars' '*.tftest.hcl')
        run_check "terraform fmt" terraform fmt -check -diff "${tf_files[@]}"
    fi
    if have tflint; then
        # tflint --init only initializes the current directory, so initialize
        # every directory that pins its own plugin before the recursive run.
        while IFS= read -r dir; do
            tflint --init --chdir="$dir" > /dev/null || true
        done < <(find . -name .tflint.hcl -printf '%h\n' | sort -u)
        run_check tflint tflint --recursive
    else
        skip tflint "install tflint v0.65.0 (https://github.com/terraform-linters/tflint)"
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
