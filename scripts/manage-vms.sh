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

for VM in ${VM_NAMES}; do
  if [[ "${ACTION}" == "stop" ]]; then
    echo "Deallocating VM: ${VM}"
    az vm deallocate \
      --name "${VM}" \
      --resource-group "${RESOURCE_GROUP}" \
      --no-wait \
      --output none
  else
    echo "Starting VM: ${VM}"
    az vm start \
      --name "${VM}" \
      --resource-group "${RESOURCE_GROUP}" \
      --no-wait \
      --output none
  fi
  echo "  ${ACTION^} command issued."
done

echo ""
echo "All VM ${ACTION} commands have been issued (--no-wait). Use 'az vm list -g ${RESOURCE_GROUP} -d --query \"[].{Name:name, PowerState:powerState}\" -o table' to check status."
