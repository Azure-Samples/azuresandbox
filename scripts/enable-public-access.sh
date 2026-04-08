#!/bin/bash

# Enables public network access on all key vaults and storage accounts
# in a given resource group.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Retrieving resource names from terraform output..."
RESOURCE_NAMES_JSON=$(terraform -chdir="${TERRAFORM_DIR}" output -json resource_names 2>&1) || {
  echo "Error: 'terraform output -json resource_names' failed."
  echo "${RESOURCE_NAMES_JSON}"
  echo "Run 'terraform apply' to update state."
  exit 1
}

if [[ $# -ge 1 ]]; then
  RESOURCE_GROUP="$1"
else
  RESOURCE_GROUP=$(echo "${RESOURCE_NAMES_JSON}" | grep -o '"resource_group":"[^"]*"' | sed 's/"resource_group":"//;s/"//')
  if [[ -z "${RESOURCE_GROUP}" ]]; then
    echo "Error: Failed to get resource group name from terraform output."
    echo "Usage: $0 [resource-group-name]"
    exit 1
  fi
  echo "Using resource group: ${RESOURCE_GROUP}"
fi

KV_NAME=$(echo "${RESOURCE_NAMES_JSON}" | grep -o '"key_vault":"[^"]*"' | sed 's/"key_vault":"//;s/"//')
SA_NAME=$(echo "${RESOURCE_NAMES_JSON}" | grep -o '"storage_account":"[^"]*"' | sed 's/"storage_account":"//;s/"//')

if [[ -z "${KV_NAME}" ]]; then
  echo "Error: Failed to get key vault name from terraform output."
  exit 1
fi

if [[ -z "${SA_NAME}" ]]; then
  echo "Error: Failed to get storage account name from terraform output."
  exit 1
fi

echo "Enabling public access for resources in resource group: ${RESOURCE_GROUP}"

# --- Key Vault ---
echo ""
echo "=== Key Vault ==="
echo "Enabling public access on key vault: ${KV_NAME}"
az keyvault update \
  --name "${KV_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --public-network-access Enabled \
  --output none
echo "  Done."

# --- Storage Account ---
echo ""
echo "=== Storage Account ==="
echo "Enabling public access on storage account: ${SA_NAME}"
az storage account update \
  --name "${SA_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --public-network-access Enabled \
  --output none
echo "  Done."

echo ""
echo "Public access enablement complete."
