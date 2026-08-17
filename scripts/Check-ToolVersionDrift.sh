#!/bin/bash

# CI tool-version drift detector.
#
# Dependabot covers the terraform and github-actions ecosystems, but every
# pinned CI *linter/scanner tool* version is invisible to it because each is
# pinned in a form Dependabot's parsers don't inspect: a direct binary download
# gated by an env-var version string, an Install-Module / npx inline invocation
# with no manifest, or an input parameter to a setup action. This script closes
# that gap: for each pinned tool it reads the version currently pinned in the
# workflow (and the mirrored copies in scripts/Invoke-CIChecks.sh, .tflint.hcl,
# terraform.tf, CONTRIBUTING.md), queries the upstream latest release, and
# reports any drift.
#
# It is consumed by the scheduled ci-tool-versions.yml workflow, which turns the
# report into a single tracking issue, but it also runs standalone so a
# contributor can check drift locally:
#
#   ./scripts/Check-ToolVersionDrift.sh                 # print report to stdout
#   ./scripts/Check-ToolVersionDrift.sh report.md       # also write body to file
#
# Requirements: bash, curl, jq, and GNU grep (-P). An optional GITHUB_TOKEN (or
# GH_TOKEN) is used for GitHub API calls to avoid unauthenticated rate limits.
#
# Output: a Markdown report (full status table + per-drifted-tool file lists) is
# written to the file named by $1 (default: tool-version-drift-report.md) and
# echoed to stdout. When run under GitHub Actions, drift_count/error_count/
# report_file are also appended to $GITHUB_OUTPUT. Exit code is always 0 unless
# a fatal script error occurs; callers decide what to do from the counts.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root" || exit 1

report_file="${1:-tool-version-drift-report.md}"
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

# id|display|source|pin_file::pin_regex|comma,separated,files,to,update
# source is one of gh:<owner>/<repo>, npm:<package>, psg:<packageId>.
tools=(
  'shellcheck|ShellCheck|gh:koalaman/shellcheck|.github/workflows/ci-bash.yml::SHELLCHECK_VERSION:\s*\K[0-9.]+|.github/workflows/ci-bash.yml (version + SHA256 checksum),scripts/Invoke-CIChecks.sh'
  'actionlint|actionlint|gh:rhysd/actionlint|.github/workflows/ci-actions.yml::ACTIONLINT_VERSION:\s*\K[0-9.]+|.github/workflows/ci-actions.yml,scripts/Invoke-CIChecks.sh'
  'gitleaks|gitleaks|gh:gitleaks/gitleaks|.github/workflows/ci-secrets.yml::GITLEAKS_VERSION:\s*\K[0-9.]+|.github/workflows/ci-secrets.yml,scripts/Invoke-CIChecks.sh'
  'psscriptanalyzer|PSScriptAnalyzer|psg:PSScriptAnalyzer|.github/workflows/ci-powershell.yml::-RequiredVersion\s*\K[0-9.]+|.github/workflows/ci-powershell.yml,scripts/Invoke-CIChecks.sh'
  'markdownlint-cli2|markdownlint-cli2|npm:markdownlint-cli2|.github/workflows/ci-docs.yml::markdownlint-cli2@\K[0-9.]+|.github/workflows/ci-docs.yml,scripts/Invoke-CIChecks.sh,CONTRIBUTING.md'
  'tflint|tflint|gh:terraform-linters/tflint|.github/workflows/ci-terraform.yml::tflint_version:\s*v?\K[0-9.]+|.github/workflows/ci-terraform.yml,scripts/Invoke-CIChecks.sh'
  'tflint-azurerm|tflint azurerm ruleset|gh:terraform-linters/tflint-ruleset-azurerm|.tflint.hcl::version\s*=\s*"\K[0-9.]+|.tflint.hcl'
  'terraform|Terraform CLI|gh:hashicorp/terraform|.github/workflows/ci-terraform.yml::terraform_version:\s*\K[0-9.]+|.github/workflows/ci-terraform.yml (fmt + validate jobs),terraform.tf (required_version)'
)

# Return the version pinned in the given file, matched by a perl regex whose \K
# drops everything before the version. Empty string if no match.
extract_pin() {
  local spec="$1" file regex
  file="${spec%%::*}"
  regex="${spec#*::}"
  [ -f "$file" ] || { echo ''; return; }
  grep -oP -m1 "$regex" "$file" 2> /dev/null || echo ''
}

gh_api() {
  local url="$1"
  if [ -n "$token" ]; then
    curl -fsSL -H "Authorization: Bearer $token" -H 'X-GitHub-Api-Version: 2022-11-28' "$url"
  else
    curl -fsSL "$url"
  fi
}

# Echo the upstream latest stable version (leading "v" stripped) for a source
# spec, or empty string on failure.
fetch_latest() {
  local source="$1" kind ref latest
  kind="${source%%:*}"
  ref="${source#*:}"
  case "$kind" in
    gh)
      latest="$(gh_api "https://api.github.com/repos/${ref}/releases/latest" 2> /dev/null | jq -r '.tag_name // empty' 2> /dev/null)"
      ;;
    npm)
      latest="$(curl -fsSL "https://registry.npmjs.org/${ref}/latest" 2> /dev/null | jq -r '.version // empty' 2> /dev/null)"
      ;;
    psg)
      latest="$(curl -fsSL "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='${ref}'&\$filter=IsLatestVersion" 2> /dev/null | grep -oP '<d:Version>\K[0-9.]+' | head -1)"
      ;;
    *)
      latest=''
      ;;
  esac
  echo "${latest#v}"
}

# Return 0 when $2 (latest) is strictly newer than $1 (current) by version sort.
is_newer() {
  local current="$1" latest="$2" top
  [ "$current" = "$latest" ] && return 1
  top="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)"
  [ "$top" = "$latest" ]
}

drift_count=0
error_count=0
table_rows=()
detail_blocks=()

for entry in "${tools[@]}"; do
  IFS='|' read -r _ display source pin_spec files <<< "$entry"
  current="$(extract_pin "$pin_spec")"
  latest="$(fetch_latest "$source")"

  if [ -z "$current" ]; then
    status='⚠️ pin not found'
    error_count=$((error_count + 1))
  elif [ -z "$latest" ]; then
    status='⚠️ lookup failed'
    error_count=$((error_count + 1))
  elif is_newer "$current" "$latest"; then
    status='🔴 **DRIFT**'
    drift_count=$((drift_count + 1))
    files_md="${files//,/$'\n'    - }"
    detail_blocks+=("- **${display}**: \`${current:-?}\` → \`${latest:-?}\`
  - Files to update:
    - ${files_md}")
  else
    status='✅ up to date'
  fi

  table_rows+=("| ${display} | \`${current:-?}\` | \`${latest:-?}\` | ${status} |")
done

{
  echo '## CI tool-version drift report'
  echo
  echo 'Pinned CI linter/scanner tool versions that Dependabot does not track, compared against their upstream latest stable releases. Generated by `scripts/Check-ToolVersionDrift.sh` (see [ci-tool-versions.yml](../workflows/ci-tool-versions.yml)).'
  echo
  echo '| Tool | Pinned | Latest | Status |'
  echo '| --- | --- | --- | --- |'
  for row in "${table_rows[@]}"; do echo "$row"; done
  echo
  if [ "$drift_count" -gt 0 ]; then
    echo "### ${drift_count} tool(s) behind — files to update"
    echo
    for block in "${detail_blocks[@]}"; do echo "$block"; done
    echo
    echo 'After bumping each version, keep the pinned copies in sync across every file listed above, then run `./scripts/Invoke-CIChecks.sh` locally before pushing.'
  else
    echo '✅ All pinned CI tool versions are up to date.'
  fi
  if [ "$error_count" -gt 0 ]; then
    echo
    echo "> ⚠️ ${error_count} tool(s) could not be evaluated (pin not found or upstream lookup failed). Investigate before trusting this report."
  fi
} > "$report_file"

cat "$report_file"

echo
echo "drift_count=${drift_count}"
echo "error_count=${error_count}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "drift_count=${drift_count}"
    echo "error_count=${error_count}"
    echo "report_file=${report_file}"
  } >> "$GITHUB_OUTPUT"
fi

exit 0
