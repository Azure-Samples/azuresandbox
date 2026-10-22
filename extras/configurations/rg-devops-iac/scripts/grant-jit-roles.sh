#!/bin/bash

# Grants the OIDC deployment identity (deployment_identity = "oidc") its just-in-time deployment roles before an
# operator approves a Sandbox deployment workflow run:
#   * Contributor                               time-bound active assignment on the subscription.
#   * Role Based Access Control Administrator   time-bound active assignment on the subscription, constrained by
#                                               'jit_condition' in the 'deployment_identity' terraform output.
#
# Run as the operator with Azure CLI signed in. Creating role assignments requires an active subscription Owner
# or User Access Administrator assignment. If neither is active, the script activates your eligible Owner
# assignment through Privileged Identity Management (PIM). If PIM requires approval or multifactor
# authentication that Azure CLI can't satisfy, activate Owner in the portal and run the script again.
#
# The identity, subscription and condition come from this configuration's terraform outputs, so run it after
# 'terraform apply'. It works from any directory.
#
# Usage: ./scripts/grant-jit-roles.sh [options]
#   -H, --hours N             Duration of the time-bound assignments in hours (default 8, range 1-24).
#   -j, --justification TEXT  Justification recorded with PIM requests (default "Sandbox deployment workflow run").
#   -f, --force               Replace assignments that are already active instead of keeping them.
#   -r, --revoke              Remove the identity's Contributor and Role Based Access Control Administrator
#                             assignments instead of granting them.
#   -h, --help                Show this help.
#
# The workflow preflight requires at least SANDBOX_JIT_MIN_REMAINING_MINUTES (default 150) remaining on both
# assignments, so grant them shortly before approving the run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

API_VERSION="2020-10-01"
OWNER_ROLE_ID="8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
# Built-in Azure role definition IDs are public, not secrets.
USER_ACCESS_ADMIN_ROLE_ID="18d7d88d-d35e-4fb5-a5c3-7773c20a72d9" # gitleaks:allow
CONTRIBUTOR_ROLE_ID="b24988ac-6180-42a0-ab88-20f7382dd24c"
RBAC_ADMIN_ROLE_ID="f58310d9-a9f6-439a-9e8d-f62e7b41a168"
declare -A ROLE_NAMES=(
  ["${CONTRIBUTOR_ROLE_ID}"]="Contributor"
  ["${RBAC_ADMIN_ROLE_ID}"]="Role Based Access Control Administrator"
)
GRANT_ROLE_IDS=("${CONTRIBUTOR_ROLE_ID}" "${RBAC_ADMIN_ROLE_ID}")
MIN_REMAINING_MINUTES="${SANDBOX_JIT_MIN_REMAINING_MINUTES:-150}"

HOURS=8
JUSTIFICATION="Sandbox deployment workflow run"
FORCE=false
REVOKE=false

usage() {
  sed -n '/^# Usage:/,/^# assignments, so/p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--hours) HOURS="${2:-}"; shift 2 ;;
    -j|--justification) JUSTIFICATION="${2:-}"; shift 2 ;;
    -f|--force) FORCE=true; shift ;;
    -r|--revoke) REVOKE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown option '$1'."; usage; exit 1 ;;
  esac
done

if ! [[ "${HOURS}" =~ ^[0-9]+$ ]] || (( HOURS < 1 || HOURS > 24 )); then
  echo "Error: --hours must be a whole number from 1 to 24."
  exit 1
fi
if [[ -z "${JUSTIFICATION}" ]]; then
  echo "Error: --justification can't be empty."
  exit 1
fi

for tool in az jq terraform; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Error: '${tool}' is required but not installed."
    exit 1
  fi
done

new_guid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen; else cat /proc/sys/kernel/random/uuid; fi
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

minutes_until() {
  echo $(( ($(date -u -d "$1" +%s) - $(date -u +%s)) / 60 ))
}

#region inputs
echo "Reading terraform outputs from ${TERRAFORM_DIR}..."
OUTPUTS=$(terraform -chdir="${TERRAFORM_DIR}" output -json) || {
  echo "Error: couldn't read terraform outputs. Run 'terraform apply' for this configuration first."
  exit 1
}

PRINCIPAL_ID=$(jq -r '.deployment_identity.value.principal_id // empty' <<<"${OUTPUTS}")
CONDITION=$(jq -r '.deployment_identity.value.jit_condition // empty' <<<"${OUTPUTS}")
IDENTITY_NAME=$(jq -r '.resource_names.value.deployment_identity // empty' <<<"${OUTPUTS}")
RESOURCE_GROUP_ID=$(jq -r '.resource_ids.value.resource_group // empty' <<<"${OUTPUTS}")

if [[ -z "${PRINCIPAL_ID}" || -z "${CONDITION}" ]]; then
  echo "Error: 'principal_id' or 'jit_condition' in the 'deployment_identity' output is empty."
  echo "Set deployment_identity = \"oidc\" and run 'terraform apply'."
  exit 1
fi

SUBSCRIPTION_ID=$(sed -n 's|^/subscriptions/\([^/]*\)/.*|\1|p' <<<"${RESOURCE_GROUP_ID}")
if [[ -z "${SUBSCRIPTION_ID}" ]]; then
  echo "Error: couldn't determine the subscription from the 'resource_ids' output."
  exit 1
fi
SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
ARM="https://management.azure.com${SCOPE}/providers/Microsoft.Authorization"

if ! ACCOUNT_TYPE=$(az account show --query user.type -o tsv 2>/dev/null); then
  echo "Error: Azure CLI isn't signed in. Run 'az login' as the operator."
  exit 1
fi
if [[ "${ACCOUNT_TYPE}" != "user" ]]; then
  echo "Error: Azure CLI must be signed in as a user (the operator), not a service principal or managed identity."
  exit 1
fi

echo "Subscription:        ${SUBSCRIPTION_ID}"
echo "Deployment identity: ${IDENTITY_NAME:-<unknown>} (${PRINCIPAL_ID})"
#endregion

#region functions
# Active subscription-scope assignments of the given principal, as JSON lines: {roleId, endDateTime, condition}.
active_assignments() {
  local filter="$1"
  az rest --method GET \
    --url "${ARM}/roleAssignmentScheduleInstances?api-version=${API_VERSION}&\$filter=${filter}" \
    -o json |
    jq -c --arg scope "${SCOPE}" '.value[].properties
      | select((.scope | ascii_downcase) == ($scope | ascii_downcase))
      | {roleId: (.roleDefinitionId | split("/") | last | ascii_downcase),
         endDateTime, condition, assignmentType, memberType}'
}

# Submits a roleAssignmentScheduleRequest. Retries authorization failures for up to 5 minutes, which covers
# propagation of a PIM activation made moments earlier.
submit_request() {
  local body="$1" output attempt
  for attempt in $(seq 1 20); do
    if output=$(az rest --method PUT --body "${body}" \
      --url "${ARM}/roleAssignmentScheduleRequests/$(new_guid)?api-version=${API_VERSION}" \
      --query "properties.status" -o tsv 2>&1); then
      echo "${output}"
      return 0
    fi
    if grep -q "AuthorizationFailed" <<<"${output}" && (( attempt < 20 )); then
      sleep 15
      continue
    fi
    echo "${output}" >&2
    return 1
  done
}

remove_assignment() {
  local role_id="$1" body
  body=$(jq -n \
    --arg principal "${PRINCIPAL_ID}" \
    --arg role "${SCOPE}/providers/Microsoft.Authorization/roleDefinitions/${role_id}" \
    --arg justification "${JUSTIFICATION}" \
    '{properties: {principalId: $principal, roleDefinitionId: $role, requestType: "AdminRemove",
      justification: $justification}}')
  submit_request "${body}" >/dev/null
}
#endregion

#region operator-access
CALLER_ROLES=$(active_assignments "asTarget()" | jq -r '.roleId')
if grep -qx -e "${OWNER_ROLE_ID}" -e "${USER_ACCESS_ADMIN_ROLE_ID}" <<<"${CALLER_ROLES}"; then
  echo "Operator access:     Owner or User Access Administrator is active."
else
  ELIGIBILITY_ID=$(az rest --method GET \
    --url "${ARM}/roleEligibilityScheduleInstances?api-version=${API_VERSION}&\$filter=asTarget()" -o json |
    jq -r --arg scope "${SCOPE}" --arg role "${OWNER_ROLE_ID}" '[.value[].properties
      | select((.scope | ascii_downcase) == ($scope | ascii_downcase))
      | select((.roleDefinitionId | split("/") | last | ascii_downcase) == $role)
      | .roleEligibilityScheduleId][0] // empty')
  if [[ -z "${ELIGIBILITY_ID}" ]]; then
    echo "Error: you have no active or eligible Owner assignment on the subscription."
    exit 1
  fi

  # Only PIM self-activation needs the operator's object ID, which comes from Microsoft Graph.
  if ! OPERATOR_ID=$(az ad signed-in-user show --query id -o tsv 2>&1) || [[ -z "${OPERATOR_ID}" ]]; then
    echo "Error: couldn't look up your user object ID in Microsoft Graph:"
    echo "${OPERATOR_ID}"
    echo "If Azure CLI asks you to sign in again, run 'az login' and run this script again."
    exit 1
  fi

  echo "Operator access:     activating your eligible Owner assignment through PIM for 1 hour..."
  ACTIVATE_BODY=$(jq -n \
    --arg principal "${OPERATOR_ID}" \
    --arg role "${SCOPE}/providers/Microsoft.Authorization/roleDefinitions/${OWNER_ROLE_ID}" \
    --arg eligibility "${ELIGIBILITY_ID}" \
    --arg justification "${JUSTIFICATION}" \
    --arg start "$(utc_now)" \
    '{properties: {principalId: $principal, roleDefinitionId: $role, requestType: "SelfActivate",
      linkedRoleEligibilityScheduleId: $eligibility, justification: $justification,
      scheduleInfo: {startDateTime: $start, expiration: {type: "AfterDuration", duration: "PT1H"}}}}')
  if ! STATUS=$(submit_request "${ACTIVATE_BODY}"); then
    echo "Error: PIM activation failed. Activate Owner in the portal, then run this script again."
    exit 1
  fi
  if [[ "${STATUS}" != "Provisioned" ]]; then
    echo "Error: PIM activation status is '${STATUS}'. If it needs approval, wait for it, then run this script again."
    exit 1
  fi
  echo "Operator access:     Owner activated."
fi
#endregion

#region revoke
if [[ "${REVOKE}" == true ]]; then
  EXISTING=$(active_assignments "principalId+eq+'${PRINCIPAL_ID}'")
  for role_id in "${GRANT_ROLE_IDS[@]}"; do
    if jq -e --arg role "${role_id}" 'select(.roleId == $role)' <<<"${EXISTING}" >/dev/null; then
      remove_assignment "${role_id}"
      echo "  ${ROLE_NAMES[${role_id}]}: removed."
    else
      echo "  ${ROLE_NAMES[${role_id}]}: not assigned."
    fi
  done
  echo "Just-in-time role removal complete."
  exit 0
fi
#endregion

#region grant
EXISTING=$(active_assignments "principalId+eq+'${PRINCIPAL_ID}'")
for role_id in "${GRANT_ROLE_IDS[@]}"; do
  role_name="${ROLE_NAMES[${role_id}]}"
  current=$(jq -c --arg role "${role_id}" 'select(.roleId == $role)' <<<"${EXISTING}" | head -n 1)

  if [[ -n "${current}" ]]; then
    end=$(jq -r '.endDateTime // empty' <<<"${current}")
    if [[ "${FORCE}" != true ]]; then
      if [[ -z "${end}" ]]; then
        echo "  ${role_name}: already assigned permanently. Kept; use --force to replace it with a time-bound one."
      else
        echo "  ${role_name}: already active until ${end} ($(minutes_until "${end}") minutes). Kept; use --force to replace it."
      fi
      if [[ "${role_id}" == "${RBAC_ADMIN_ROLE_ID}" ]] && [[ "$(jq -r '.condition // empty' <<<"${current}")" != "${CONDITION}" ]]; then
        echo "  Warning: its condition doesn't match the 'deployment_identity' output's 'jit_condition'. Run again with --force to replace it."
      fi
      continue
    fi
    echo "  ${role_name}: removing the existing assignment..."
    remove_assignment "${role_id}"
  fi

  body=$(jq -n \
    --arg principal "${PRINCIPAL_ID}" \
    --arg role "${SCOPE}/providers/Microsoft.Authorization/roleDefinitions/${role_id}" \
    --arg justification "${JUSTIFICATION}" \
    --arg start "$(utc_now)" \
    --arg duration "PT${HOURS}H" \
    '{properties: {principalId: $principal, roleDefinitionId: $role, requestType: "AdminAssign",
      justification: $justification,
      scheduleInfo: {startDateTime: $start, expiration: {type: "AfterDuration", duration: $duration}}}}')
  if [[ "${role_id}" == "${RBAC_ADMIN_ROLE_ID}" ]]; then
    body=$(jq --arg condition "${CONDITION}" \
      '.properties += {condition: $condition, conditionVersion: "2.0"}' <<<"${body}")
  fi

  echo "  ${role_name}: assigning for ${HOURS} hours..."
  if ! status=$(submit_request "${body}"); then
    echo "Error: assigning ${role_name} failed."
    exit 1
  fi
  echo "  ${role_name}: ${status}."
done

echo "Active assignments for the deployment identity:"
SHORT=false
EXISTING=$(active_assignments "principalId+eq+'${PRINCIPAL_ID}'")
for role_id in "${GRANT_ROLE_IDS[@]}"; do
  end=$(jq -r --arg role "${role_id}" 'select(.roleId == $role) | .endDateTime // "permanent"' <<<"${EXISTING}" | head -n 1)
  if [[ -z "${end}" ]]; then
    echo "  ${ROLE_NAMES[${role_id}]}: not yet listed. It can take about 5 minutes to appear."
    continue
  fi
  if [[ "${end}" == "permanent" ]]; then
    echo "  ${ROLE_NAMES[${role_id}]}: permanent."
    continue
  fi
  remaining=$(minutes_until "${end}")
  echo "  ${ROLE_NAMES[${role_id}]}: until ${end} (${remaining} minutes)."
  if (( remaining < MIN_REMAINING_MINUTES )); then
    SHORT=true
  fi
done
if [[ "${SHORT}" == true ]]; then
  echo "Warning: less than ${MIN_REMAINING_MINUTES} minutes remain on an assignment, so the workflow preflight will fail."
  echo "Run again with --force to replace it."
fi

# Role assignments list conditions immediately, unlike the PIM schedule instances above.
APPLIED_CONDITION=$(az rest --method GET \
  --url "${ARM}/roleAssignments?api-version=2022-04-01&\$filter=principalId+eq+'${PRINCIPAL_ID}'" -o json |
  jq -r --arg scope "${SCOPE}" --arg role "${RBAC_ADMIN_ROLE_ID}" '[.value[].properties
    | select((.scope | ascii_downcase) == ($scope | ascii_downcase))
    | select((.roleDefinitionId | split("/") | last | ascii_downcase) == $role)
    | .condition // ""][0] // empty')
echo "Condition on ${ROLE_NAMES[${RBAC_ADMIN_ROLE_ID}]}:"
if [[ -z "${APPLIED_CONDITION}" ]]; then
  echo "  Warning: no condition is applied. The identity can assign any role, including Owner."
  echo "  Run again with --force to replace the assignment."
else
  echo "  Restricted actions:"
  grep -oE "ActionMatches\{'[^']+'\}" <<<"${APPLIED_CONDITION}" | sed -E "s/ActionMatches\{'([^']+)'\}/    - \1/" | sort -u
  mapfile -t ALLOWED_ROLE_IDS < <(grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"${APPLIED_CONDITION}" |
    tr '[:upper:]' '[:lower:]' | sort -u)
  ROLE_DEFINITIONS=$(az rest --method GET \
    --url "${ARM}/roleDefinitions?api-version=2022-04-01" -o json |
    jq -c '[.value[] | {key: (.name | ascii_downcase), value: .properties.roleName}] | from_entries')
  echo "  Roles the identity can assign and remove (${#ALLOWED_ROLE_IDS[@]}):"
  for allowed_id in "${ALLOWED_ROLE_IDS[@]}"; do
    jq -r --arg id "${allowed_id}" '"    - \(.[$id] // "<unknown role>") (\($id))"' <<<"${ROLE_DEFINITIONS}"
  done | sort
  if [[ "${APPLIED_CONDITION}" == "${CONDITION}" ]]; then
    echo "  Matches the the 'deployment_identity' output's 'jit_condition' output."
  else
    echo "  Warning: doesn't match the the 'deployment_identity' output's 'jit_condition' output. Run again with --force to replace it."
  fi
fi

echo "Just-in-time role grant complete. Approve the workflow run once both roles are listed with end times."
#endregion
