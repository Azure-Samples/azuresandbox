#!/bin/bash

# Runs Azure VM Image Builder builds for the optional image gallery (enable_image_gallery = true), waits for them to
# finish, and tags each new image version for traceability:
#   * source_image_version  The resolved version of the source platform image (the template uses 'latest').
#   * build_time            When the build finished (UTC).
# The template already tags each version with source_image (publisher:offer:sku).
#
# Run as the operator with Azure CLI signed in, after 'terraform apply'. Template and resource group names come from
# this configuration's terraform outputs, so it works from any directory. Builds run in parallel and take from about
# 30 minutes (jumplinux) to a few hours (Windows images with several Windows Update passes).
#
# Usage: ./scripts/invoke-image-build.sh [options] [IMAGE...]
#   IMAGE                     One or more of adds, jumpwin, jumplinux, mssqlwin (default: all four).
#   -i, --interval SECONDS    How often to check build status (default 60).
#   -h, --help                Show this help.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

INTERVAL=60
IMAGES=()

usage() {
  sed -n '/^# Usage:/,/^#   -h, --help/p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interval) INTERVAL="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Error: unknown option '$1'."; usage; exit 1 ;;
    *) IMAGES+=("$1"); shift ;;
  esac
done

if ! [[ "${INTERVAL}" =~ ^[0-9]+$ ]] || (( INTERVAL < 10 )); then
  echo "Error: --interval must be a whole number of seconds, 10 or more."
  exit 1
fi

for tool in az jq terraform; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Error: '${tool}' is required but not installed."
    exit 1
  fi
done

if ! az account show >/dev/null 2>&1; then
  echo "Error: Azure CLI isn't signed in. Run 'az login' first."
  exit 1
fi

echo "Reading terraform outputs from ${TERRAFORM_DIR}..."
OUTPUTS=$(terraform -chdir="${TERRAFORM_DIR}" output -json) || {
  echo "Error: couldn't read terraform outputs. Run 'terraform apply' for this configuration first."
  exit 1
}

# Image template names, keyed by image name, from the image_template_<image> entries in resource_names.
TEMPLATE_NAMES=$(jq '.resource_names.value | with_entries(select(.key | startswith("image_template_")) | .key |= ltrimstr("image_template_"))' <<<"${OUTPUTS}")

if [[ "$(jq 'length' <<<"${TEMPLATE_NAMES}")" -eq 0 ]]; then
  echo "Error: no image templates found in the 'resource_names' output. Set enable_image_gallery = true and run 'terraform apply'."
  exit 1
fi

RESOURCE_GROUP=$(jq -r '.resource_names.value.resource_group' <<<"${OUTPUTS}")
SUBSCRIPTION_ID=$(jq -r '.resource_ids.value.resource_group' <<<"${OUTPUTS}" | cut -d/ -f3)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  mapfile -t IMAGES < <(jq -r 'keys[]' <<<"${TEMPLATE_NAMES}")
fi

declare -A TEMPLATES=()
for image in "${IMAGES[@]}"; do
  template=$(jq -r --arg image "${image}" '.[$image] // empty' <<<"${TEMPLATE_NAMES}")
  if [[ -z "${template}" ]]; then
    echo "Error: unknown image '${image}'. Valid images: $(jq -r 'keys | join(", ")' <<<"${TEMPLATE_NAMES}")."
    exit 1
  fi
  TEMPLATES["${image}"]="${template}"
done

for image in "${IMAGES[@]}"; do
  state=$(az image builder show --subscription "${SUBSCRIPTION_ID}" -g "${RESOURCE_GROUP}" -n "${TEMPLATES[${image}]}" \
    --query 'lastRunStatus.runState' -o tsv)
  if [[ "${state}" == "Running" ]]; then
    echo "Error: a build of '${image}' is already running. Wait for it to finish first."
    exit 1
  fi
done

for image in "${IMAGES[@]}"; do
  echo "Starting the '${image}' build (template '${TEMPLATES[${image}]}')..."
  az image builder run --subscription "${SUBSCRIPTION_ID}" -g "${RESOURCE_GROUP}" -n "${TEMPLATES[${image}]}" --no-wait
done

# Wait for every build to leave the Running state. 'az image builder run --no-wait' returns before the run starts, so
# an empty or stale state is treated as still starting.
declare -A RESULTS=()
started=$(date +%s)
while [[ ${#RESULTS[@]} -lt ${#IMAGES[@]} ]]; do
  sleep "${INTERVAL}"
  elapsed=$(( ($(date +%s) - started) / 60 ))
  for image in "${IMAGES[@]}"; do
    [[ -n "${RESULTS[${image}]:-}" ]] && continue
    status=$(az image builder show --subscription "${SUBSCRIPTION_ID}" -g "${RESOURCE_GROUP}" -n "${TEMPLATES[${image}]}" \
      --query 'lastRunStatus' -o json)
    state=$(jq -r '.runState // empty' <<<"${status}")
    start_time=$(jq -r '.startTime // empty' <<<"${status}")
    if [[ -z "${state}" || "${state}" == "Running" ]] || [[ -n "${start_time}" && "$(date -d "${start_time}" +%s)" -lt "${started}" ]]; then
      echo "[${elapsed}m] ${image}: ${state:-Starting} $(jq -r '.runSubState // empty' <<<"${status}")"
      continue
    fi
    RESULTS["${image}"]="${state}"
    echo "[${elapsed}m] ${image}: ${state} $(jq -r '.message // empty' <<<"${status}")"
  done
done

failed=0
for image in "${IMAGES[@]}"; do
  if [[ "${RESULTS[${image}]}" != "Succeeded" ]]; then
    echo "Build '${image}' ended with state '${RESULTS[${image}]}'. See customization.log in the template's staging resource group."
    failed=$((failed + 1))
    continue
  fi

  template_json=$(az image builder show --subscription "${SUBSCRIPTION_ID}" -g "${RESOURCE_GROUP}" -n "${TEMPLATES[${image}]}" -o json)
  source_version=$(jq -r '.source.exactVersion // empty' <<<"${template_json}")
  build_time=$(jq -r '.lastRunStatus.endTime // empty' <<<"${template_json}")
  version_id=$(az image builder show-runs --subscription "${SUBSCRIPTION_ID}" -g "${RESOURCE_GROUP}" -n "${TEMPLATES[${image}]}" \
    --output-name "${image}" --query artifactId -o tsv)

  if [[ -z "${version_id}" || -z "${source_version}" ]]; then
    echo "Warning: couldn't find the new '${image}' image version or its source version, so it wasn't tagged."
    failed=$((failed + 1))
    continue
  fi

  echo "Tagging '${version_id##*/images/}' with source_image_version=${source_version} build_time=${build_time}..."
  az tag update --resource-id "${version_id}" --operation Merge \
    --tags "source_image_version=${source_version}" "build_time=${build_time}" >/dev/null
done

if (( failed > 0 )); then
  echo "${failed} of ${#IMAGES[@]} build(s) failed or weren't tagged."
  exit 1
fi

echo "All ${#IMAGES[@]} build(s) succeeded."
