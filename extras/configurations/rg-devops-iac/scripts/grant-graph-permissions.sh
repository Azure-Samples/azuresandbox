#!/bin/bash

# Grants the Microsoft Graph application permissions an Azure Sandbox deployment identity needs when the mssql
# module is enabled. The module creates a security group whose members are the operator (a user) and a
# user-assigned managed identity (a service principal):
#   * Group.Create          creates the group. The deployment identity becomes the group's owner.
#   * GroupMember.Read.All  reads the group's owners and members after it is created.
#   * User.Read.All         reads the user added as a member.
#   * Application.Read.All  reads the service principal added as a member.
#
# Works for any deployment identity: the service principal used with auth_mode = "client_secret", or the
# user-assigned managed identity this configuration creates (deployment_identity = "managed_identity").
#
# Must be run with Azure CLI signed in as a Microsoft Entra Privileged Role Administrator, the least privileged
# role that can grant Microsoft Graph application permissions (Global Administrator also works). Azure RBAC
# roles, including subscription Owner, cannot grant application permissions.
#
# Usage: ./scripts/grant-graph-permissions.sh [client-id-or-object-id]
# The identity defaults to 'principal_id' in the 'deployment_identity' terraform output, which requires jq.
# The script is idempotent: permissions that are already granted are skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
GRAPH_PERMISSIONS=("Group.Create" "GroupMember.Read.All" "User.Read.All" "Application.Read.All")

if [[ $# -ge 1 ]]; then
  IDENTITY="$1"
else
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to read the 'deployment_identity' terraform output. Install jq, or pass the identity."
    echo "Usage: $0 [client-id-or-object-id]"
    exit 1
  fi
  echo "Retrieving deployment identity principal id from terraform output..."
  IDENTITY=$(terraform -chdir="${TERRAFORM_DIR}" output -json deployment_identity 2>/dev/null | jq -r '.principal_id // empty') || IDENTITY=""
  if [[ -z "${IDENTITY}" ]]; then
    echo "Error: 'principal_id' in the 'deployment_identity' terraform output is empty."
    echo "Set deployment_identity = \"managed_identity\" and run 'terraform apply', or pass the identity."
    echo "Usage: $0 [client-id-or-object-id]"
    exit 1
  fi
fi

if ! [[ "${IDENTITY}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "Error: '${IDENTITY}' is not a valid client id or object id."
  exit 1
fi

read -r SP_OBJECT_ID SP_NAME < <(az ad sp show --id "${IDENTITY}" --query "[id, displayName]" -o tsv | paste -sd' ' -) || true
if [[ -z "${SP_OBJECT_ID:-}" ]]; then
  echo "Error: Service principal '${IDENTITY}' not found."
  exit 1
fi
echo "Deployment identity: ${SP_NAME} (${SP_OBJECT_ID})"

GRAPH_SP_ID=$(az ad sp show --id "${GRAPH_APP_ID}" --query id -o tsv)

EXISTING_ROLE_IDS=$(az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SP_OBJECT_ID}/appRoleAssignments" \
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
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SP_OBJECT_ID}/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body "{\"principalId\": \"${SP_OBJECT_ID}\", \"resourceId\": \"${GRAPH_SP_ID}\", \"appRoleId\": \"${role_id}\"}" \
    --output none
  echo "  ${permission}: granted."
done

LEGACY_ASSIGNMENT_ID=$(az rest --method GET \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SP_OBJECT_ID}/appRoleAssignments" \
  --query "value[?resourceId=='${GRAPH_SP_ID}' && appRoleId=='62a82d76-70ea-41e2-9197-370581804d09'].id | [0]" -o tsv)
if [[ -n "${LEGACY_ASSIGNMENT_ID}" ]]; then
  echo "Warning: the deployment identity still has Group.ReadWrite.All. It is no longer required. Remove it with:"
  echo "  az rest --method DELETE --uri \"https://graph.microsoft.com/v1.0/servicePrincipals/${SP_OBJECT_ID}/appRoleAssignments/${LEGACY_ASSIGNMENT_ID}\""
fi

echo "Microsoft Graph permission grant complete."
