#!/bin/bash

# Enables public network access on all key vaults and storage accounts
# in a given resource group.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <resource-group-name>"
  exit 1
fi

RESOURCE_GROUP="$1"

echo "Enabling public access for resources in resource group: ${RESOURCE_GROUP}"

# --- Key Vaults ---
echo ""
echo "=== Key Vaults ==="

KV_NAMES=$(az keyvault list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || true)

if [[ -z "${KV_NAMES}" ]]; then
  echo "No key vaults found."
else
  for KV in ${KV_NAMES}; do
    echo "Enabling public access on key vault: ${KV}"
    az keyvault update \
      --name "${KV}" \
      --resource-group "${RESOURCE_GROUP}" \
      --public-network-access Enabled \
      --output none
    echo "  Done."
  done
fi

# --- Storage Accounts ---
echo ""
echo "=== Storage Accounts ==="

SA_NAMES=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || true)

if [[ -z "${SA_NAMES}" ]]; then
  echo "No storage accounts found."
else
  for SA in ${SA_NAMES}; do
    echo "Enabling public access on storage account: ${SA}"
    az storage account update \
      --name "${SA}" \
      --resource-group "${RESOURCE_GROUP}" \
      --public-network-access Enabled \
      --output none
    echo "  Done."
  done
fi

echo ""
echo "Public access enablement complete."
