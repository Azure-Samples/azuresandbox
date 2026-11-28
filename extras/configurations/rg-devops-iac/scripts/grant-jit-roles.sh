#!/bin/bash

# Grants the deployment identity (deployment_identity = "managed_identity" or "oidc") its just-in-time deployment roles
# before an Azure Sandbox apply, either a Sandbox deployment workflow run or a manual apply on jumplinux2:
#   * Contributor                               time-bound active assignment on the subscription.
#   * Role Based Access Control Administrator   time-bound active assignment on the subscription, with a condition
#                                               that restricts the roles it can assign or remove to the roles file.
#
# Run as the operator with Azure CLI signed in. If your subscription Role Based Access Control Administrator
# assignment isn't active, the script activates your eligible assignment through Privileged Identity Management
# (PIM). If PIM requires approval or multifactor authentication that Azure CLI can't satisfy, activate the role in
# the portal and run the script again.
#
# The identity and subscription come from this configuration's terraform outputs, so run it after 'terraform apply'.
# The condition is built from the roles file (default: the Azure Sandbox scripts/deployment-identity-roles.yaml), so a
# role list change only needs this script run again with --force. It works from any directory.
#
# Usage: ./scripts/grant-jit-roles.sh [options]
#   -H, --hours N             Duration of the time-bound assignments in hours (default 8, range 1-24).
#   -j, --justification TEXT  Justification recorded with PIM requests (default "Azure Sandbox apply").
#   -f, --force               Replace assignments that are already active instead of keeping them.
#   -r, --revoke              Remove the identity's Contributor and Role Based Access Control Administrator
#                             assignments instead of granting them.
#   -R, --roles-file PATH     YAML mapping of each module to the built-in role names it assigns, e.g.
#                             'my_module: [AcrPull]'.
#                             Use it for a Terraform configuration other than Azure Sandbox.
#   -p, --print-condition     Print the condition for the Azure CLI subscription and exit, e.g. to grant the roles in
#                             the portal. Needs no terraform outputs.
#   -h, --help                Show this help.
#
# The grant must last at least SANDBOX_JOB_TIMEOUT_MINUTES (default 360), because the Sandbox deployment workflow
# preflight requires both assignments to outlast the job's timeout. Grant them shortly before approving a run. If the
# repository variable overrides the default, export the same value before running this script. For a terminal apply
# on jumplinux2, export a lower value (60 minimum) to allow a shorter grant.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

API_VERSION="2020-10-01"
# Built-in Azure role definition IDs are public, not secrets.
CONTRIBUTOR_ROLE_ID="b24988ac-6180-42a0-ab88-20f7382dd24c"
RBAC_ADMIN_ROLE_ID="f58310d9-a9f6-439a-9e8d-f62e7b41a168"
declare -A ROLE_NAMES=(
  ["${CONTRIBUTOR_ROLE_ID}"]="Contributor"
  ["${RBAC_ADMIN_ROLE_ID}"]="Role Based Access Control Administrator"
)
GRANT_ROLE_IDS=("${CONTRIBUTOR_ROLE_ID}" "${RBAC_ADMIN_ROLE_ID}")
MIN_REMAINING_MINUTES="${SANDBOX_JOB_TIMEOUT_MINUTES:-360}"

HOURS=8
JUSTIFICATION="Azure Sandbox apply"
FORCE=false
REVOKE=false
PRINT_CONDITION=false
ROLES_FILE="$(cd "${SCRIPT_DIR}/../../../.." && pwd)/scripts/deployment-identity-roles.yaml"

usage() {
  sed -n '/^# Usage:/,/^# on jumplinux2, export a lower value/p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--hours) HOURS="${2:-}"; shift 2 ;;
    -j|--justification) JUSTIFICATION="${2:-}"; shift 2 ;;
    -f|--force) FORCE=true; shift ;;
    -r|--revoke) REVOKE=true; shift ;;
    -R|--roles-file) ROLES_FILE="${2:-}"; shift 2 ;;
    -p|--print-condition) PRINT_CONDITION=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown option '$1'."; usage; exit 1 ;;
  esac
done

if ! [[ "${HOURS}" =~ ^[0-9]+$ ]] || (( HOURS < 1 || HOURS > 24 )); then
  echo "Error: --hours must be a whole number from 1 to 24."
  exit 1
fi
if [[ "${REVOKE}" != true ]]; then
  if ! [[ "${MIN_REMAINING_MINUTES}" =~ ^[0-9]{1,4}$ ]] || (( 10#${MIN_REMAINING_MINUTES} < 60 || 10#${MIN_REMAINING_MINUTES} > 1440 )); then
    echo "Error: SANDBOX_JOB_TIMEOUT_MINUTES must be a whole number of minutes from 60 to 1440."
    exit 1
  fi
  MIN_REMAINING_MINUTES=$((10#${MIN_REMAINING_MINUTES}))
  if (( HOURS * 60 < MIN_REMAINING_MINUTES )); then
    echo "Error: a ${HOURS}-hour grant can't outlast the ${MIN_REMAINING_MINUTES}-minute job timeout, so the workflow preflight would fail."
    exit 1
  fi
fi
if [[ -z "${JUSTIFICATION}" ]]; then
  echo "Error: --justification can't be empty."
  exit 1
fi

for tool in az jq yq $([[ "${PRINT_CONDITION}" == true ]] || echo terraform); do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Error: '${tool}' is required but not installed."
    exit 1
  fi
done
if yq --version 2>&1 | grep -qi mikefarah; then
  echo "Error: this script needs the jq-based yq ('sudo apt install yq' or 'pip3 install yq'), not mikefarah/yq."
  exit 1
fi

if [[ "${REVOKE}" != true || "${PRINT_CONDITION}" == true ]]; then
  if [[ ! -f "${ROLES_FILE}" ]]; then
    echo "Error: roles file '${ROLES_FILE}' not found. Use --roles-file to specify one."
    exit 1
  fi
  if ! yq -e 'type == "object" and all(.[]; type == "array" and all(.[]; type == "string"))' "${ROLES_FILE}" >/dev/null 2>&1; then
    echo "Error: roles file '${ROLES_FILE}' must map each module to a list of role names, e.g. 'my_module: [AcrPull]'."
    exit 1
  fi
  # Roles can be listed under several modules; keep the first occurrence of each.
  mapfile -t ASSIGNABLE_ROLES < <(yq -r '.[][]' "${ROLES_FILE}" | awk '!seen[$0]++')
  if (( ${#ASSIGNABLE_ROLES[@]} == 0 )); then
    echo "Error: roles file '${ROLES_FILE}' lists no roles."
    exit 1
  fi
fi

new_guid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen; else cat /proc/sys/kernel/random/uuid; fi
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

minutes_until() {
  echo $(( ($(date -u -d "$1" +%s) - $(date -u +%s)) / 60 ))
}

# Sets ROLE_DEFINITIONS (role id -> name, for every role in the subscription) and CONDITION, the version 2.0
# condition that restricts role assignment writes and deletes to the built-in roles in ASSIGNABLE_ROLES.
build_condition() {
  local definitions role_ids=() missing=() role role_id ids
  definitions=$(az rest --method GET --url "${ARM}/roleDefinitions?api-version=2022-04-01" -o json)
  ROLE_DEFINITIONS=$(jq -c '[.value[] | {key: (.name | ascii_downcase), value: .properties.roleName}] | from_entries' <<<"${definitions}")
  for role in "${ASSIGNABLE_ROLES[@]}"; do
    role_id=$(jq -r --arg role "${role}" '[.value[] | select(.properties.type == "BuiltInRole" and .properties.roleName == $role)
      | .name | ascii_downcase][0] // empty' <<<"${definitions}")
    if [[ -z "${role_id}" ]]; then missing+=("${role}"); else role_ids+=("${role_id}"); fi
  done
  if (( ${#missing[@]} > 0 )); then
    echo "Error: no built-in role named the following in '${ROLES_FILE}':" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi
  ids=$(printf '%s, ' "${role_ids[@]}")
  ids="${ids%, }"
  CONDITION="((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/write'}) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ids}}))"
  CONDITION+=" AND ((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ids}}))"
}

if [[ "${PRINT_CONDITION}" == true ]]; then
  if ! SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null); then
    echo "Error: Azure CLI isn't signed in. Run 'az login'."
    exit 1
  fi
  ARM="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization"
  build_condition
  echo "${CONDITION}"
  exit 0
fi

#region inputs
echo "Reading terraform outputs from ${TERRAFORM_DIR}..."
OUTPUTS=$(terraform -chdir="${TERRAFORM_DIR}" output -json) || {
  echo "Error: couldn't read terraform outputs. Run 'terraform apply' for this configuration first."
  exit 1
}

PRINCIPAL_ID=$(jq -r '.deployment_identity.value.principal_id // empty' <<<"${OUTPUTS}")
IDENTITY_NAME=$(jq -r '.resource_names.value.deployment_identity // empty' <<<"${OUTPUTS}")
RESOURCE_GROUP_ID=$(jq -r '.resource_ids.value.resource_group // empty' <<<"${OUTPUTS}")

if [[ -z "${PRINCIPAL_ID}" ]]; then
  echo "Error: the 'deployment_identity' output is empty."
  echo "Set deployment_identity = \"managed_identity\" or \"oidc\" and run 'terraform apply'."
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
if [[ "${REVOKE}" != true ]]; then
  build_condition
  echo "Assignable roles:    ${#ASSIGNABLE_ROLES[@]} from ${ROLES_FILE}"
fi
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
# propagation of a PIM activation made moments earlier. With retry_exists=true it also retries RoleAssignmentExists,
# which PIM returns for several minutes after it revokes an assignment that is being replaced.
submit_request() {
  local body="$1" retry_exists="${2:-false}" output attempt
  for attempt in $(seq 1 20); do
    if output=$(az rest --method PUT --body "${body}" \
      --url "${ARM}/roleAssignmentScheduleRequests/$(new_guid)?api-version=${API_VERSION}" \
      --query "properties.status" -o tsv 2>&1); then
      echo "${output}"
      return 0
    fi
    if { grep -q "AuthorizationFailed" <<<"${output}" ||
      { [[ "${retry_exists}" == true ]] && grep -q "RoleAssignmentExists" <<<"${output}"; }; } &&
      (( attempt < 20 )); then
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
if grep -qx "${RBAC_ADMIN_ROLE_ID}" <<<"${CALLER_ROLES}"; then
  echo "Operator access:     Role Based Access Control Administrator is active."
else
  ELIGIBILITY_ID=$(az rest --method GET \
    --url "${ARM}/roleEligibilityScheduleInstances?api-version=${API_VERSION}&\$filter=asTarget()" -o json |
    jq -r --arg scope "${SCOPE}" --arg role "${RBAC_ADMIN_ROLE_ID}" '[.value[].properties
      | select((.scope | ascii_downcase) == ($scope | ascii_downcase))
      | select((.roleDefinitionId | split("/") | last | ascii_downcase) == $role)
      | .roleEligibilityScheduleId][0] // empty')
  if [[ -z "${ELIGIBILITY_ID}" ]]; then
    echo "Error: you have no eligible Role Based Access Control Administrator assignment on the subscription."
    exit 1
  fi

  # Only PIM self-activation needs the operator's object ID, which comes from Microsoft Graph.
  if ! OPERATOR_ID=$(az ad signed-in-user show --query id -o tsv 2>&1) || [[ -z "${OPERATOR_ID}" ]]; then
    echo "Error: couldn't look up your user object ID in Microsoft Graph:"
    echo "${OPERATOR_ID}"
    echo "If Azure CLI asks you to sign in again, run 'az login' and run this script again."
    exit 1
  fi

  echo "Operator access:     activating your eligible Role Based Access Control Administrator assignment through PIM for 1 hour..."
  ACTIVATE_BODY=$(jq -n \
    --arg principal "${OPERATOR_ID}" \
    --arg role "${SCOPE}/providers/Microsoft.Authorization/roleDefinitions/${RBAC_ADMIN_ROLE_ID}" \
    --arg eligibility "${ELIGIBILITY_ID}" \
    --arg justification "${JUSTIFICATION}" \
    --arg start "$(utc_now)" \
    '{properties: {principalId: $principal, roleDefinitionId: $role, requestType: "SelfActivate",
      linkedRoleEligibilityScheduleId: $eligibility, justification: $justification,
      scheduleInfo: {startDateTime: $start, expiration: {type: "AfterDuration", duration: "PT1H"}}}}')
  if ! STATUS=$(submit_request "${ACTIVATE_BODY}" 2>&1); then
    # A fresh activation (e.g. from the portal) can take a few minutes to appear in asTarget() above.
    if grep -q "RoleAssignmentExists" <<<"${STATUS}"; then
      echo "Operator access:     Role Based Access Control Administrator is already active."
    else
      echo "${STATUS}"
      echo "Error: PIM activation failed. Activate Role Based Access Control Administrator in the portal, then run this script again."
      exit 1
    fi
  elif [[ "${STATUS}" != "Provisioned" ]]; then
    echo "Error: PIM activation status is '${STATUS}'. If it needs approval, wait for it, then run this script again."
    exit 1
  else
    echo "Operator access:     Role Based Access Control Administrator activated."
  fi
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

  replaced=false
  if [[ -n "${current}" ]]; then
    end=$(jq -r '.endDateTime // empty' <<<"${current}")
    if [[ "${FORCE}" != true ]]; then
      if [[ -z "${end}" ]]; then
        echo "  ${role_name}: already assigned permanently. Kept; use --force to replace it with a time-bound one."
      else
        echo "  ${role_name}: already active until ${end} ($(minutes_until "${end}") minutes). Kept; use --force to replace it."
      fi
      if [[ "${role_id}" == "${RBAC_ADMIN_ROLE_ID}" ]] && [[ "$(jq -r '.condition // empty' <<<"${current}")" != "${CONDITION}" ]]; then
        echo "  Warning: its condition doesn't match the roles file. Run again with --force to replace it."
      fi
      continue
    fi
    echo "  ${role_name}: removing the existing assignment..."
    remove_assignment "${role_id}"
    replaced=true
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
  if [[ "${replaced}" == true ]]; then
    echo "  ${role_name}: PIM can take a few minutes to finish removing the old assignment; retrying until it does..."
  fi
  if ! status=$(submit_request "${body}" "${replaced}"); then
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
  echo "Warning: less than ${MIN_REMAINING_MINUTES} minutes (the job timeout) remain on an assignment, so the workflow preflight will fail."
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
  echo "  Roles the identity can assign and remove (${#ALLOWED_ROLE_IDS[@]}):"
  for allowed_id in "${ALLOWED_ROLE_IDS[@]}"; do
    jq -r --arg id "${allowed_id}" '"    - \(.[$id] // "<unknown role>") (\($id))"' <<<"${ROLE_DEFINITIONS}"
  done | sort
  if [[ "${APPLIED_CONDITION}" == "${CONDITION}" ]]; then
    echo "  Matches the roles file."
  else
    echo "  Warning: doesn't match the roles file. Run again with --force to replace it."
  fi
fi

echo "Just-in-time role grant complete. Approve the workflow run or start the apply once both roles are listed with end times."
#endregion
