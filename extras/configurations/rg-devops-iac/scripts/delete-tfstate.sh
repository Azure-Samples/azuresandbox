#!/bin/bash

# Deletes Terraform state blob(s) from the tfstate container in the
# rg-devops-iac storage account, used as a remote state backend for other
# Terraform configurations (e.g. the root azuresandbox module running from
# jumplinux2).
#
# This does NOT use 'terraform output' because the state being deleted here
# is not the state of the rg-devops-iac configuration itself -- it's other
# Terraform state stored in that account's blob container.
#
# Authentication is via Azure CLI / Microsoft Entra ID only (the storage
# account has shared_access_key_enabled = false), using '--auth-mode login'
# for every 'az storage blob' call. This relies on the caller's identity
# (typically jumplinux2's managed identity, or a signed-in user/SPN) having
# a data-plane role assignment on the storage account, such as
# 'Storage Blob Data Contributor' (see azurerm_role_assignment.storage_roles
# in storage.tf).
#
# The storage account's blob service is only reachable over its private
# endpoint. This script assumes it is being run from a host on the same
# virtual network as that private endpoint (e.g. jumplinux2) -- it does NOT
# enable public network access, and will fail if run from a host without
# private network connectivity and public access is disabled.

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

CONTAINER_NAME="tfstate"
RESOURCE_GROUP=""
STORAGE_ACCOUNT=""
BLOB_NAME=""
ASSUME_YES=false

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [blob-name] [options]

Deletes Terraform state blob(s) from the tfstate container in the
rg-devops-iac storage account.

Arguments:
  blob-name                    Name of a specific blob to delete (e.g.
                                azuresandbox.tfstate). If omitted, the script
                                lists all blobs in the container and prompts
                                for a selection.

Options:
  --resource-group <name>      Resource group containing the storage account.
                                Default: auto-discovered (first resource
                                group whose name starts with 'rg-devops-').
  --storage-account <name>     Storage account name. Default: auto-discovered
                                (first storage account found in the resource
                                group).
  --container <name>           Blob container name. Default: tfstate.
  -y, --yes                    Skip the interactive confirmation prompt.
  -h, --help                   Show this help message and exit.

Examples:
  ${SCRIPT_NAME} azuresandbox.tfstate
  ${SCRIPT_NAME} --yes azuresandbox.tfstate
  ${SCRIPT_NAME}
EOF
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --storage-account)
      STORAGE_ACCOUNT="$2"
      shift 2
      ;;
    --container)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "${BLOB_NAME}" ]]; then
        echo "Error: Multiple blob names specified ('${BLOB_NAME}' and '$1')." >&2
        exit 1
      fi
      BLOB_NAME="$1"
      shift
      ;;
  esac
done

# --- Verify Azure CLI authentication ---
if ! az account show >/dev/null 2>&1; then
  echo "Error: Not signed in to Azure CLI. Run 'az login' (or ensure MSI is configured) and try again." >&2
  exit 1
fi

# --- Discover resource group ---
if [[ -z "${RESOURCE_GROUP}" ]]; then
  RESOURCE_GROUP=$(az group list --query "[?starts_with(name, 'rg-devops-')].name" -o tsv | head -1)
  if [[ -z "${RESOURCE_GROUP}" ]]; then
    echo "Error: Failed to auto-discover a resource group starting with 'rg-devops-'." >&2
    echo "Specify one explicitly with --resource-group <name>." >&2
    exit 1
  fi
  echo "Using resource group: ${RESOURCE_GROUP}"
fi

# --- Discover storage account ---
if [[ -z "${STORAGE_ACCOUNT}" ]]; then
  STORAGE_ACCOUNT=$(az storage account list -g "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
  if [[ -z "${STORAGE_ACCOUNT}" ]]; then
    echo "Error: Failed to auto-discover a storage account in resource group '${RESOURCE_GROUP}'." >&2
    echo "Specify one explicitly with --storage-account <name>." >&2
    exit 1
  fi
  echo "Using storage account: ${STORAGE_ACCOUNT}"
fi

echo "Using container: ${CONTAINER_NAME}"
echo ""

confirm() {
  local prompt="$1"
  if [[ "${ASSUME_YES}" == true ]]; then
    return 0
  fi
  read -r -p "${prompt} [y/N] " REPLY
  [[ "${REPLY}" =~ ^[Yy]$ ]]
}

delete_blob() {
  local blob="$1"
  echo "Deleting blob '${blob}' from container '${CONTAINER_NAME}'..."
  az storage blob delete \
    --account-name "${STORAGE_ACCOUNT}" \
    --container-name "${CONTAINER_NAME}" \
    --name "${blob}" \
    --auth-mode login \
    --output none
  echo "  Deleted."
}

if [[ -n "${BLOB_NAME}" ]]; then
  # --- Single named blob mode ---
  if ! az storage blob show \
    --account-name "${STORAGE_ACCOUNT}" \
    --container-name "${CONTAINER_NAME}" \
    --name "${BLOB_NAME}" \
    --auth-mode login \
    --output none 2>/dev/null; then
    echo "Error: Blob '${BLOB_NAME}' not found in container '${CONTAINER_NAME}'." >&2
    exit 1
  fi

  if confirm "Delete blob '${BLOB_NAME}' from '${STORAGE_ACCOUNT}/${CONTAINER_NAME}'? This cannot be undone."; then
    delete_blob "${BLOB_NAME}"
  else
    echo "Aborted. No blobs were deleted."
    exit 0
  fi
else
  # --- Interactive list-and-select mode ---
  echo "Listing blobs in '${STORAGE_ACCOUNT}/${CONTAINER_NAME}'..."
  mapfile -t BLOBS < <(az storage blob list \
    --account-name "${STORAGE_ACCOUNT}" \
    --container-name "${CONTAINER_NAME}" \
    --auth-mode login \
    --query "[].name" -o tsv)

  if [[ ${#BLOBS[@]} -eq 0 ]]; then
    echo "No blobs found in container '${CONTAINER_NAME}'. Nothing to delete."
    exit 0
  fi

  echo ""
  echo "Blobs found:"
  for i in "${!BLOBS[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${BLOBS[$i]}"
  done
  echo "  a) All blobs"
  echo "  q) Cancel"
  echo ""

  read -r -p "Select a blob to delete by number, 'a' for all, or 'q' to cancel: " SELECTION

  case "${SELECTION}" in
    q|Q)
      echo "Cancelled. No blobs were deleted."
      exit 0
      ;;
    a|A)
      if confirm "Delete ALL ${#BLOBS[@]} blob(s) from '${STORAGE_ACCOUNT}/${CONTAINER_NAME}'? This cannot be undone."; then
        for blob in "${BLOBS[@]}"; do
          delete_blob "${blob}"
        done
      else
        echo "Aborted. No blobs were deleted."
        exit 0
      fi
      ;;
    ''|*[!0-9]*)
      echo "Error: Invalid selection '${SELECTION}'." >&2
      exit 1
      ;;
    *)
      INDEX=$((SELECTION - 1))
      if [[ ${INDEX} -lt 0 || ${INDEX} -ge ${#BLOBS[@]} ]]; then
        echo "Error: Selection '${SELECTION}' is out of range." >&2
        exit 1
      fi
      SELECTED_BLOB="${BLOBS[$INDEX]}"
      if confirm "Delete blob '${SELECTED_BLOB}' from '${STORAGE_ACCOUNT}/${CONTAINER_NAME}'? This cannot be undone."; then
        delete_blob "${SELECTED_BLOB}"
      else
        echo "Aborted. No blobs were deleted."
        exit 0
      fi
      ;;
  esac
fi

echo ""
echo "Done."
