#!/bin/bash

# Starts or stops (and deallocates) all virtual machines in a given resource group.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <start|stop> <resource-group-name>"
  exit 1
fi

ACTION="$1"
RESOURCE_GROUP="$2"

if [[ "${ACTION}" != "start" && "${ACTION}" != "stop" ]]; then
  echo "Error: Action must be 'start' or 'stop'."
  echo "Usage: $0 <start|stop> <resource-group-name>"
  exit 1
fi

echo "${ACTION^}ing all VMs in resource group: ${RESOURCE_GROUP}"

VM_NAMES=$(az vm list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || true)

if [[ -z "${VM_NAMES}" ]]; then
  echo "No virtual machines found."
  exit 0
fi

if [[ "${ACTION}" == "start" ]]; then
  # Start adds1 first if it exists and is not running
  if echo "${VM_NAMES}" | grep -qw "adds1"; then
    ADDS1_STATE=$(az vm get-instance-view --name "adds1" --resource-group "${RESOURCE_GROUP}" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
    if [[ "${ADDS1_STATE}" != "VM running" ]]; then
      echo "Starting VM: adds1 (domain controller first)"
      az vm start \
        --name "adds1" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
      echo "  adds1 is now running."
    else
      echo "VM adds1 is already running."
    fi
  fi

  # Start all other VMs that are not running
  for VM in ${VM_NAMES}; do
    [[ "${VM}" == "adds1" ]] && continue
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
    [[ "${VM}" == "adds1" ]] && continue
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
    [[ "${VM}" == "adds1" ]] && continue
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
  if echo "${VM_NAMES}" | grep -qw "adds1"; then
    ADDS1_STATE=$(az vm get-instance-view --name "adds1" --resource-group "${RESOURCE_GROUP}" --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>/dev/null || true)
    if [[ "${ADDS1_STATE}" != "VM deallocated" ]]; then
      echo "Deallocating VM: adds1 (domain controller last)"
      az vm deallocate \
        --name "adds1" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
      echo "  adds1 is now deallocated."
    else
      echo "VM adds1 is already deallocated."
    fi
  fi
fi

echo ""
echo "All VM ${ACTION} operations complete. Use 'az vm list -g ${RESOURCE_GROUP} -d --query \"[].{Name:name, PowerState:powerState}\" -o table' to check status."
