#!/bin/bash

# Local bash linting pre-check.
#
# Runs the exact same ShellCheck command the ci-bash GitHub Actions workflow runs,
# so developers can reproduce the CI gate locally before pushing. Configuration
# (severity, etc.) is read from the repository-root .shellcheckrc, which both this
# script and CI share as the single source of truth.
#
# Usage:
#   ./scripts/Invoke-ShellCheck.sh
#
# Requires ShellCheck on PATH:
#   sudo apt-get install -y shellcheck   # Debian/Ubuntu
#   brew install shellcheck              # macOS
#   # or download a pinned release from https://github.com/koalaman/shellcheck/releases
#
# Exit code: 0 when no warning/error findings, non-zero otherwise (CI-friendly).

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v shellcheck > /dev/null 2>&1; then
    printf "ERROR: 'shellcheck' not found on PATH.\n" >&2
    printf "Install it with 'sudo apt-get install -y shellcheck', 'brew install shellcheck',\n" >&2
    printf "or download a release from https://github.com/koalaman/shellcheck/releases.\n" >&2
    exit 127
fi

printf "Running ShellCheck (%s)...\n" "$(shellcheck --version | awk '/version:/ {print $2}')"

# Discover every tracked shell script (excluding the .git directory) so newly
# added scripts are covered automatically. The warning+error gate is set via the
# --severity flag (ShellCheck ignores a severity directive in .shellcheckrc);
# other shared config (external-sources, per-rule excludes) comes from .shellcheckrc.
if find "$repo_root" -name '*.sh' -not -path '*/.git/*' -print0 \
    | xargs -0 -r shellcheck --severity=warning; then
    printf "ShellCheck: no warning/error findings.\n"
else
    status=$?
    printf "ShellCheck found issues (exit %d).\n" "$status" >&2
    exit "$status"
fi
