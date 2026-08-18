#!/bin/bash

# Builds the Application Insights-instrumented Petstore image on jumplinux1 (the
# in-VNet Docker host from the vm-jumpbox-linux module) and pushes it to the
# network-isolated Azure Container Registry.
#
# The registry has public network access disabled, so the build must run on a
# host inside the virtual network. jumplinux1 authenticates to the registry using
# its system-assigned managed identity (granted AcrPush), which keeps the registry
# private and avoids putting the deployment service principal on the VM.
#
# This script is invoked by azurerm_virtual_machine_run_command, which prepends a
# preamble that exports the variables below and injects the base64-encoded
# Dockerfile. It runs as root; docker and the Azure CLI are installed by the
# jumplinux1 cloud-init configuration.

set -euo pipefail

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') : $*"; }

: "${LOGIN_SERVER:?}" "${REGISTRY_NAME:?}" "${IMAGE_REPOSITORY:?}" "${IMAGE_TAG:?}"
: "${SOURCE_IMAGE:?}" "${APPINSIGHTS_VERSION:?}" "${DOCKERFILE_B64:?}"

target="${LOGIN_SERVER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"

# On a freshly provisioned VM the cloud-init package installation may still be in
# progress, so wait for docker and the Azure CLI to become available.
log "Waiting for docker and the Azure CLI to become available..."
for _ in $(seq 1 60); do
    if command -v az >/dev/null 2>&1 && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        break
    fi
    sleep 10
done

if ! (command -v az >/dev/null 2>&1 && docker info >/dev/null 2>&1); then
    log "ERROR: docker and/or the Azure CLI are not available after the timeout."
    exit 1
fi

# Authenticate to Azure and the registry using the VM's system-assigned managed identity.
log "Logging into Azure with the system-assigned managed identity..."
az login --identity 1>/dev/null

log "Logging into container registry '${REGISTRY_NAME}'..."
az acr login --name "${REGISTRY_NAME}" 1>/dev/null

# Idempotency: skip the build if this tag already exists in the registry.
if az acr repository show-tags --name "${REGISTRY_NAME}" --repository "${IMAGE_REPOSITORY}" --output tsv 2>/dev/null | grep -qx "${IMAGE_TAG}"; then
    log "Image '${target}' already present in the registry; nothing to do."
    exit 0
fi

workdir="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${workdir}'" EXIT
printf '%s' "${DOCKERFILE_B64}" | base64 -d >"${workdir}/Dockerfile"

log "Building '${target}' (Application Insights Java agent ${APPINSIGHTS_VERSION})..."
docker build \
    --pull \
    --build-arg "SOURCE_IMAGE=${SOURCE_IMAGE}" \
    --build-arg "APPINSIGHTS_VERSION=${APPINSIGHTS_VERSION}" \
    --tag "${target}" \
    "${workdir}"

log "Pushing '${target}'..."
docker push "${target}"

log "Successfully built and pushed '${target}'."
