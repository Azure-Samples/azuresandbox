#!/bin/bash
set -euo pipefail
umask 077
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec pwsh -NoLogo -NoProfile -File "$script_dir/Watch-SandboxRunner.ps1" "$@"
