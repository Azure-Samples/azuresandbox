#!/bin/bash

# Grants the Azure RBAC roles an Azure Sandbox deployment identity needs on the sandbox subscription:
#   * Contributor
#   * Role Based Access Control Administrator, with a condition that allows assigning and removing only
#     the roles listed in deployment-identity-roles.txt
#
# Use it for the service principal in client_secret mode. In managed_identity mode, rg-devops-iac
# creates the same two assignments for its deployment identity.
#
# Must be run with Azure CLI signed in as a user who can create role assignments on the subscription,
# for example an Owner or User Access Administrator.
#
# Usage: ./scripts/grant-deployment-identity-roles.sh <client-id-or-object-id> [subscription-id]
# The subscription id defaults to the current Azure CLI subscription.
# The script is idempotent: existing assignments are kept, and an outdated condition is updated in place.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES_FILE="${SCRIPT_DIR}/deployment-identity-roles.txt"
RBAC_ADMIN_ROLE="Role Based Access Control Administrator"

usage() {
  echo "Usage: $0 <client-id-or-object-id> [subscription-id]"
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

PRINCIPAL_ID=$(az ad sp show --id "$1" --query id -o tsv) || {
  echo "Error: Service principal '$1' not found."
  exit 1
}
PRINCIPAL_NAME=$(az ad sp show --id "${PRINCIPAL_ID}" --query displayName -o tsv)

SUBSCRIPTION_ID="${2:-$(az account show --query id -o tsv)}"
SCOPE="/subscriptions/${SUBSCRIPTION_ID}"

echo "Deployment identity: ${PRINCIPAL_NAME} (${PRINCIPAL_ID})"
echo "Scope: ${SCOPE}"

ROLE_IDS=""
while IFS= read -r ROLE; do
  [[ -z "${ROLE}" || "${ROLE}" == \#* ]] && continue
  ROLE_ID=$(az role definition list --name "${ROLE}" --query "[0].name" -o tsv)
  if [[ -z "${ROLE_ID}" ]]; then
    echo "Error: role '${ROLE}' in ${ROLES_FILE} not found."
    exit 1
  fi
  ROLE_IDS="${ROLE_IDS}, ${ROLE_ID}"
done <"${ROLES_FILE}"
ROLE_IDS="${ROLE_IDS#, }"

# The identity can create (write) or remove (delete) a role assignment only if the role is in ROLE_IDS.
# This prevents it from assigning highly privileged roles such as Owner, User Access Administrator or
# Role Based Access Control Administrator. Keep in sync with rg-devops-iac locals.tf.
CONDITION="((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/write'}) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ROLE_IDS}}))"
CONDITION+=" AND ((NOT ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${ROLE_IDS}}))"

assignment_query() {
  echo "[?principalId=='${PRINCIPAL_ID}' && scope=='${SCOPE}' && roleDefinitionName=='$1']"
}

# Contributor
if [[ -n $(az role assignment list --scope "${SCOPE}" --assignee "${PRINCIPAL_ID}" \
  --query "$(assignment_query Contributor).id" -o tsv) ]]; then
  echo "  Contributor: already assigned."
else
  echo "  Contributor: assigning..."
  az role assignment create --assignee-object-id "${PRINCIPAL_ID}" --assignee-principal-type ServicePrincipal \
    --role Contributor --scope "${SCOPE}" --output none
  echo "  Contributor: assigned."
fi

# Role Based Access Control Administrator, constrained by the condition
EXISTING=$(az role assignment list --scope "${SCOPE}" --assignee "${PRINCIPAL_ID}" \
  --query "$(assignment_query "${RBAC_ADMIN_ROLE}") | [0].[id, roleDefinitionId, condition]" -o tsv)

if [[ -z "${EXISTING}" ]]; then
  echo "  ${RBAC_ADMIN_ROLE}: assigning..."
  az role assignment create --assignee-object-id "${PRINCIPAL_ID}" --assignee-principal-type ServicePrincipal \
    --role "${RBAC_ADMIN_ROLE}" --scope "${SCOPE}" \
    --condition "${CONDITION}" --condition-version "2.0" --output none
  echo "  ${RBAC_ADMIN_ROLE}: assigned."
else
  IFS=$'\t' read -r ASSIGNMENT_ID ROLE_DEFINITION_ID EXISTING_CONDITION <<<"${EXISTING}"
  if [[ "${EXISTING_CONDITION}" == "${CONDITION}" ]]; then
    echo "  ${RBAC_ADMIN_ROLE}: already assigned."
  else
    echo "  ${RBAC_ADMIN_ROLE}: updating condition..."
    az role assignment update --output none --role-assignment "{
      \"id\": \"${ASSIGNMENT_ID}\",
      \"principalId\": \"${PRINCIPAL_ID}\",
      \"principalType\": \"ServicePrincipal\",
      \"roleDefinitionId\": \"${ROLE_DEFINITION_ID}\",
      \"scope\": \"${SCOPE}\",
      \"condition\": \"${CONDITION}\",
      \"conditionVersion\": \"2.0\"
    }"
    echo "  ${RBAC_ADMIN_ROLE}: condition updated."
  fi
fi

for role in "Owner" "User Access Administrator"; do
  if [[ -n $(az role assignment list --scope "${SCOPE}" --assignee "${PRINCIPAL_ID}" \
    --query "$(assignment_query "${role}").id" -o tsv) ]]; then
    echo "Warning: the deployment identity still has '${role}' on ${SCOPE}. It is no longer required. Remove it with:"
    echo "  az role assignment delete --assignee \"${PRINCIPAL_ID}\" --role \"${role}\" --scope \"${SCOPE}\""
  fi
done

echo "Deployment identity role assignment complete."
