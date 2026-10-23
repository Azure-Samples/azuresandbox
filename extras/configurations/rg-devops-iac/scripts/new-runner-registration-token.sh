#!/usr/bin/env bash
# Creates a GitHub Actions runner registration token for the optional self-hosted runner
# (enable_github_runner = true) and exports it as TF_VAR_github_runner_token. Not needed otherwise.
#
# Usage, from extras/configurations/rg-devops-iac, in the bash shell that will run terraform:
#   source ./scripts/new-runner-registration-token.sh [runner_url]
#
# The script must be sourced, so it can set the variable in the current shell. Run directly, it
# refuses to print the token to a terminal; its output can only be captured, e.g.
#   export TF_VAR_github_runner_token="$(./scripts/new-runner-registration-token.sh)"
#
# runner_url defaults to github_runner_url in ../terraform.tfvars. A repository URL mints a
# repository runner token, an organization URL an organization runner token.
#
# Requires the GitHub CLI (gh) signed in as a repository admin, or with the admin:org scope for an
# organization runner. The token is never displayed. It expires after 1 hour, so run terraform plan
# and terraform apply right away, in the same shell.

# The body runs in a subshell, so set -e and exit never affect a shell that sources this script.
_new_runner_registration_token() (
    set -euo pipefail

    die() {
        echo "new-runner-registration-token: $*" >&2
        exit 1
    }

    tfvars="$(cd "$(dirname "$1")/.." && pwd)/terraform.tfvars"
    shift
    runner_url="${1:-}"

    if [ -z "$runner_url" ]; then
        [ -f "$tfvars" ] || die "$tfvars not found. Pass the runner URL as an argument."
        runner_url=$(sed -nE 's/^[[:space:]]*github_runner_url[[:space:]]*=[[:space:]]*"([^"]*)".*$/\1/p' "$tfvars" | tail -n 1)
        [ -n "$runner_url" ] || die "github_runner_url is not set in $tfvars. Pass the runner URL as an argument."
    fi

    if ! [[ "$runner_url" =~ ^https://github\.com/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$ ]]; then
        die "'$runner_url' is not a GitHub organization or repository URL, e.g. 'https://github.com/myorg/myrepo'."
    fi

    command -v gh > /dev/null 2>&1 || die "the GitHub CLI (gh) is not installed. See https://cli.github.com."

    api_path=${runner_url#https://github.com/}

    if [[ "$api_path" == */* ]]; then
        endpoint="repos/$api_path/actions/runners/registration-token"
    else
        endpoint="orgs/$api_path/actions/runners/registration-token"
    fi

    token=$(gh api --method POST "$endpoint" --jq '.token') ||
        die "could not create a registration token for $runner_url. Sign in with 'gh auth login' as a repository admin (or with the admin:org scope for an organization)."

    [ -n "$token" ] || die "the GitHub API returned an empty registration token for $runner_url."

    printf '%s\n' "$token"

)

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    # Sourced: export the token in the current shell without displaying it.
    if _nrrt_token=$(_new_runner_registration_token "${BASH_SOURCE[0]}" "$@"); then
        export TF_VAR_github_runner_token="$_nrrt_token"
        echo "TF_VAR_github_runner_token is set. The token expires in 1 hour: run terraform plan and terraform apply in this shell." >&2
        unset _nrrt_token
        unset -f _new_runner_registration_token
    else
        unset _nrrt_token
        unset -f _new_runner_registration_token
        return 1
    fi
else
    if [ -t 1 ]; then
        echo "new-runner-registration-token: refusing to display the token. Run: source $0" >&2
        exit 1
    fi
    _new_runner_registration_token "${BASH_SOURCE[0]}" "$@"
fi
