#!/usr/bin/env bash
# Starts and deallocates the self-hosted runner VM (jumplinux2) for one run of
# .github/workflows/sandbox-deployment.yml (#501). Runs only in the GitHub-hosted
# start_runner and stop_runner jobs, from the trusted workflow commit, and signs in
# with GitHub OIDC as the runner power state identity, which can only read, start
# and deallocate that VM.
#
# Usage: Invoke-RunnerPowerState.sh wait-approval|start|wait-pickup|stop
#   wait-approval  Wait for the sandbox job's approval. Writes approved=true|false to
#                  $GITHUB_OUTPUT. Cancels the run if no decision arrives in time.
#   start          Start the VM unless it's already running. Writes started=true|false.
#                  Skipped (started=false) when RUNNER_POWER_STATE_CLIENT_ID isn't set: the power state
#                  identity exists only with deployment_identity = "oidc", so with "managed_identity"
#                  the VM must already be running.
#   wait-pickup    Wait for a runner to pick up the sandbox job; cancel the run on timeout.
#   stop           Deallocate the VM.
#
# Environment:
#   GH_TOKEN, GITHUB_API_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT,
#   GITHUB_OUTPUT                        wait-approval, wait-pickup
#   SANDBOX_JOB_NAME                     wait-approval, wait-pickup (the sandbox job's name)
#   ACTIONS_ID_TOKEN_REQUEST_URL/_TOKEN  start, stop (job needs id-token: write)
#   RUNNER_POWER_STATE_CLIENT_ID, AZURE_TENANT_ID, RUNNER_VM_ID   start, stop (environment secrets)
#   APPROVAL_TIMEOUT_MINUTES (60), PICKUP_TIMEOUT_MINUTES (20), POLL_SECONDS (20)
set -euo pipefail

approval_timeout=$((${APPROVAL_TIMEOUT_MINUTES:-60} * 60))
pickup_timeout=$((${PICKUP_TIMEOUT_MINUTES:-20} * 60))
poll=${POLL_SECONDS:-20}

die() { echo "::error::$*"; exit 1; }
summary() { printf '%s\n' "$*" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; }
require() { local v; for v in "$@"; do [[ -n "${!v:-}" ]] || die "$v is not set."; done; }

# Prints "<status> <conclusion>" for this run attempt's sandbox job, or "missing".
sandbox_job_state() {
    gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT/jobs?per_page=100" \
        --jq ".jobs | map(select(.name == \"$SANDBOX_JOB_NAME\")) | if length == 0 then \"missing\" else (.[0] | \"\\(.status) \\(.conclusion // \"none\")\") end"
}

cancel_run() {
    gh api --method POST "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/cancel" --silent ||
        echo "::warning::Could not cancel the run."
}

wait_approval() {
    require GH_TOKEN GITHUB_REPOSITORY GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_OUTPUT SANDBOX_JOB_NAME
    local deadline=$((SECONDS + approval_timeout)) state
    while :; do
        state="$(sandbox_job_state)"
        case "$state" in
            queued\ *|in_progress\ *)
                echo "approved=true" >> "$GITHUB_OUTPUT"
                echo "The sandbox job was approved."
                return 0
                ;;
            completed\ *)
                # Rejected, skipped or cancelled before it reached a runner.
                echo "approved=false" >> "$GITHUB_OUTPUT"
                echo "The sandbox job ended without running (${state#* }). The runner VM was not started."
                summary "Runner VM not started: the deployment was not approved (${state#* })."
                return 0
                ;;
        esac
        # missing, waiting, pending, requested: no decision yet.
        if ((SECONDS >= deadline)); then
            echo "approved=false" >> "$GITHUB_OUTPUT"
            summary "Runner VM not started: no approval within ${APPROVAL_TIMEOUT_MINUTES:-60} minutes. The run was cancelled."
            cancel_run
            die "No approval within ${APPROVAL_TIMEOUT_MINUTES:-60} minutes; the run was cancelled without starting the runner VM."
        fi
        sleep "$poll"
    done
}

azure_login() {
    require ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN RUNNER_POWER_STATE_CLIENT_ID AZURE_TENANT_ID RUNNER_VM_ID
    local token
    token="$(curl -fsS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
        "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -er '.value')" ||
        die "Could not get a GitHub OIDC token."
    echo "::add-mask::$token"
    az login --service-principal --username "$RUNNER_POWER_STATE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" \
        --federated-token "$token" --allow-no-subscriptions --only-show-errors --output none ||
        die "Azure sign-in as the runner power state identity failed."
}

power_state() {
    az vm get-instance-view --ids "$RUNNER_VM_ID" --only-show-errors \
        --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" --output tsv
}

start_vm() {
    require GITHUB_OUTPUT
    if [[ -z "${RUNNER_POWER_STATE_CLIENT_ID:-}" ]]; then
        echo "started=false" >> "$GITHUB_OUTPUT"
        echo "RUNNER_POWER_STATE_CLIENT_ID isn't set, so this run won't start or deallocate the runner VM."
        summary "Runner power state identity not configured; the runner VM must already be running."
        return 0
    fi
    azure_login
    local state deadline=$((SECONDS + 600))
    state="$(power_state)"
    # Let a transition finish before deciding.
    while [[ "$state" == PowerState/starting || "$state" == PowerState/stopping || "$state" == PowerState/deallocating ]]; do
        ((SECONDS < deadline)) || die "The runner VM stayed in $state for 10 minutes."
        sleep "$poll"
        state="$(power_state)"
    done
    case "$state" in
        PowerState/running)
            echo "started=false" >> "$GITHUB_OUTPUT"
            echo "The runner VM is already running; this run won't deallocate it."
            summary "Runner VM was already running; left running after the run."
            ;;
        PowerState/deallocated|PowerState/stopped)
            # Record ownership first so stop_runner deallocates even if the start fails part-way.
            echo "started=true" >> "$GITHUB_OUTPUT"
            echo "Starting the runner VM ($state)."
            az vm start --ids "$RUNNER_VM_ID" --only-show-errors --output none || die "Could not start the runner VM."
            summary "Runner VM started by this run; it is deallocated when the run ends."
            ;;
        *)
            die "Unexpected runner VM power state '${state:-unknown}'."
            ;;
    esac
}

wait_pickup() {
    require GH_TOKEN GITHUB_REPOSITORY GITHUB_RUN_ID GITHUB_RUN_ATTEMPT SANDBOX_JOB_NAME
    local deadline=$((SECONDS + pickup_timeout)) state
    while :; do
        state="$(sandbox_job_state)"
        case "$state" in
            in_progress\ *|completed\ *)
                echo "A runner picked up the sandbox job."
                return 0
                ;;
        esac
        if ((SECONDS >= deadline)); then
            summary "No runner picked up the sandbox job within ${PICKUP_TIMEOUT_MINUTES:-20} minutes. The run was cancelled."
            cancel_run
            die "No runner picked up the sandbox job within ${PICKUP_TIMEOUT_MINUTES:-20} minutes; the run was cancelled."
        fi
        sleep "$poll"
    done
}

stop_vm() {
    azure_login
    echo "Deallocating the runner VM."
    az vm deallocate --ids "$RUNNER_VM_ID" --only-show-errors --output none || die "Could not deallocate the runner VM."
    summary "Runner VM deallocated."
}

case "${1:-}" in
    wait-approval) wait_approval ;;
    start) start_vm ;;
    wait-pickup) wait_pickup ;;
    stop) stop_vm ;;
    *) echo "Usage: $0 wait-approval|start|wait-pickup|stop" >&2; exit 2 ;;
esac
