#!/bin/bash

# Grants the Microsoft Graph application permissions required by root Azure Sandbox applies with
# arm_auth_mode = "msi" to the user-assigned managed identity created by this configuration
# (enable_user_assigned_identity = true). Group.ReadWrite.All is required by the mssql module.
#
# Must be run with Azure CLI signed in as a Microsoft Entra Privileged Role Administrator or Global
# Administrator. The service principal used to provision this configuration cannot grant it.
#
# Usage: ./scripts/grant-graph-permissions.sh [managed-identity-principal-id]
# The principal id defaults to the 'user_assigned_identity_principal_id' terraform output.
# The script is idempotent: permissions that are already granted are skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
GRAPH_PERMISSIONS=("Group.ReadWrite.All")

if [[ $# -ge 1 ]]; then
  MI_OBJECT_ID="$1"
else
  echo "Retrieving managed identity principal id from terraform output..."
  MI_OBJECT_ID=$(terraform -chdir="${TERRAFORM_DIR}" output -raw user_assigned_identity_principal_id 2>/dev/null) || MI_OBJECT_ID=""
  if [[ -z "${MI_OBJECT_ID}" || "${MI_OBJECT_ID}" == "null" ]]; then
    echo "Error: 'user_assigned_identity_principal_id' terraform output is empty."
    echo "Set enable_user_assigned_identity = true and run 'terraform apply', or pass the principal id."
    echo "Usage: $0 [managed-identity-principal-id]"
    exit 1
  fi
fi

if ! [[ "${MI_OBJECT_ID}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "Error: '${MI_OBJECT_ID}' is not a valid principal id."
  exit 1
fi

MI_NAME=$(az ad sp show --id "${MI_OBJECT_ID}" --query displayName -o tsv) || {
  echo "Error: Managed identity service principal '${MI_OBJECT_ID}' not found."
  exit 1
}
echo "Managed identity: ${MI_NAME} (${MI_OBJECT_ID})"

GRAPH_SP_ID=$(az ad sp show --id "${GRAPH_APP_ID}" --query id -o tsv)

EXISTING_ROLE_IDS=$(az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${MI_OBJECT_ID}/appRoleAssignments" \
  --query "value[?resourceId=='${GRAPH_SP_ID}'].appRoleId" -o tsv)

for permission in "${GRAPH_PERMISSIONS[@]}"; do
  role_id=$(az ad sp show --id "${GRAPH_APP_ID}" \
    --query "appRoles[?value=='${permission}' && contains(allowedMemberTypes, 'Application')].id | [0]" -o tsv)

  if [[ -z "${role_id}" ]]; then
    echo "Error: Microsoft Graph application permission '${permission}' not found."
    exit 1
  fi

  if grep -qx "${role_id}" <<<"${EXISTING_ROLE_IDS}"; then
    echo "  ${permission}: already granted."
    continue
  fi

  echo "  ${permission}: granting..."
  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${MI_OBJECT_ID}/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body "{\"principalId\": \"${MI_OBJECT_ID}\", \"resourceId\": \"${GRAPH_SP_ID}\", \"appRoleId\": \"${role_id}\"}" \
    --output none
  echo "  ${permission}: granted."
done

echo "Microsoft Graph permission grant complete."
