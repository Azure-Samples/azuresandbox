#!/bin/bash

# Starts or stops (and deallocates) all virtual machines in a given resource group.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <start|stop> [resource-group-name]"
  exit 1
fi

ACTION="$1"

if [[ "${ACTION}" != "start" && "${ACTION}" != "stop" ]]; then
  echo "Error: Action must be 'start' or 'stop'."
  echo "Usage: $0 <start|stop> [resource-group-name]"
  exit 1
fi

echo "Retrieving resource names from terraform output..."
RESOURCE_NAMES_JSON=$(terraform -chdir="${TERRAFORM_DIR}" output -json resource_names 2>/dev/null)

if [[ $# -ge 2 ]]; then
  RESOURCE_GROUP="$2"
else
  RESOURCE_GROUP=$(echo "${RESOURCE_NAMES_JSON}" | grep -o '"resource_group":"[^"]*"' | sed 's/"resource_group":"//;s/"//')
  if [[ -z "${RESOURCE_GROUP}" ]]; then
    echo "Error: Failed to get resource group name from terraform output."
    echo "Usage: $0 <start|stop> [resource-group-name]"
    exit 1
  fi
  echo "Using resource group: ${RESOURCE_GROUP}"
fi

# Extract VM names from terraform output (all keys starting with "virtual_machine_")
VM_NAMES=$(echo "${RESOURCE_NAMES_JSON}" | grep -o '"virtual_machine_[^"]*":"[^"]*"' | sed 's/"virtual_machine_[^"]*":"//;s/"//' || true)

# Extract the domain controller VM name (virtual_machine_adds1 key)
ADDS1_VM=$(echo "${RESOURCE_NAMES_JSON}" | grep -o '"virtual_machine_adds1":"[^"]*"' | sed 's/"virtual_machine_adds1":"//;s/"//' || true)

if [[ -z "${VM_NAMES}" ]]; then
  echo "No virtual machines found in terraform output."
  exit 0
fi

echo "${ACTION^}ing all VMs in resource group: ${RESOURCE_GROUP}"

if [[ "${ACTION}" == "start" ]]; then
  # Start adds1 first if it exists and is not running
  if [[ -n "${ADDS1_VM}" ]]; then
    ADDS1_STATE=$(az vm get-instance-view --name "${ADDS1_VM}" --resource-group "${RESOURCE_GROUP}" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
    if [[ "${ADDS1_STATE}" != "VM running" ]]; then
      echo "Starting VM: ${ADDS1_VM} (domain controller first)"
      az vm start \
        --name "${ADDS1_VM}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
      echo "  ${ADDS1_VM} is now running."
    else
      echo "VM ${ADDS1_VM} is already running."
    fi
  fi

  # Start all other VMs that are not running
  for VM in ${VM_NAMES}; do
    [[ -n "${ADDS1_VM}" && "${VM}" == "${ADDS1_VM}" ]] && continue
    VM_STATE=$(az vm get-instance-view --name "${VM}" --resource-group "${RESOURCE_GROUP}" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
    if [[ "${VM_STATE}" != "VM running" ]]; then
      echo "Starting VM: ${VM}"
      az vm start \
        --name "${VM}" \
        --resource-group "${RESOURCE_GROUP}" \
        --no-wait \
        --output none
      echo "  Start command issued."
    else
      echo "VM ${VM} is already running."
    fi
  done
else
  # Stop all VMs other than adds1 first
  for VM in ${VM_NAMES}; do
    [[ -n "${ADDS1_VM}" && "${VM}" == "${ADDS1_VM}" ]] && continue
    VM_STATE=$(az vm get-instance-view --name "${VM}" --resource-group "${RESOURCE_GROUP}" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
    if [[ "${VM_STATE}" != "VM deallocated" ]]; then
      echo "Deallocating VM: ${VM}"
      az vm deallocate \
        --name "${VM}" \
        --resource-group "${RESOURCE_GROUP}" \
        --no-wait \
        --output none
      echo "  Stop command issued."
    else
      echo "VM ${VM} is already deallocated."
    fi
  done

  # Wait for all other VMs to be deallocated before stopping adds1
  echo "Waiting for all other VMs to be deallocated..."
  for VM in ${VM_NAMES}; do
    [[ -n "${ADDS1_VM}" && "${VM}" == "${ADDS1_VM}" ]] && continue
    while true; do
      STATE=$(az vm get-instance-view --name "${VM}" --resource-group "${RESOURCE_GROUP}" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
      if [[ "${STATE}" == "VM deallocated" ]]; then
        echo "  ${VM} is deallocated."
        break
      fi
      sleep 10
    done
  done

  # Stop adds1 last if it exists and is not already stopped
  if [[ -n "${ADDS1_VM}" ]]; then
    ADDS1_STATE=$(az vm get-instance-view --name "${ADDS1_VM}" --resource-group "${RESOURCE_GROUP}" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
    if [[ "${ADDS1_STATE}" != "VM deallocated" ]]; then
      echo "Deallocating VM: ${ADDS1_VM} (domain controller last)"
      az vm deallocate \
        --name "${ADDS1_VM}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
      echo "  ${ADDS1_VM} is now deallocated."
    else
      echo "VM ${ADDS1_VM} is already deallocated."
    fi
  fi
fi

echo ""
echo "All VM ${ACTION} operations complete. Use 'az vm list -g ${RESOURCE_GROUP} -d --query \"[].{Name:name, PowerState:powerState}\" -o table' to check status."
