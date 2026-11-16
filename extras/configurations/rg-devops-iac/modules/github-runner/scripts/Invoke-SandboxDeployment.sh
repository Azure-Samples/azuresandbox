#!/bin/bash
set -euo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Internal subprocess entrypoint: redirect native output without pipes or shell evaluation.
if [ "${1:-}" = "--command" ]; then
    if [ "$#" -lt 7 ] || [ "$6" != "--" ]; then
        printf 'Invalid private command invocation.\n' >&2
        exit 1
    fi
    working_directory="$2"
    log="$3"
    output="$4"
    input="$5"
    shift 6
    cd -- "$working_directory"
    exec "$@" < "$input" >> "$output" 2>> "$log"
fi

if [ "$#" -ne 1 ]; then
    printf 'Usage: bash Invoke-SandboxDeployment.sh {preflight|apply|unit-test|summary}\n' >&2
    exit 1
fi
case "$1" in
    preflight|apply|unit-test|summary) ;;
    *) printf 'Invalid deployment stage.\n' >&2; exit 1 ;;
esac
exec pwsh -NoLogo -NoProfile -File "$script_dir/Invoke-SandboxDeployment.ps1" -Stage "$1"
