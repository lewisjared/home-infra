#!/usr/bin/env bash
# =============================================================================
# Create Proxmox PCI Resource Mapping for iGPU passthrough
#
# Creates a cluster-level PCI mapping named "igpu" that maps each compute
# node's AMD iGPU to a logical name Terraform can reference.
#
# Prerequisites:
#   - PROXMOX_API_TOKEN env var set (e.g., "root@pam!terraform=uuid-token")
#   - Hosts have been rebooted after gpu_passthrough ansible role
#
# Usage:
#   export PROXMOX_API_TOKEN="root@pam!terraform=your-token-here"
#   bash scripts/create-gpu-mapping.sh
# =============================================================================
set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-10.10.10.10}"
PROXMOX_PORT="${PROXMOX_PORT:-8006}"
BASE_URL="https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json"
MAPPING_NAME="igpu"

if [[ -z "${PROXMOX_API_TOKEN:-}" ]]; then
    echo "Error: PROXMOX_API_TOKEN must be set"
    echo "Example: export PROXMOX_API_TOKEN='root@pam!terraform=uuid-token'"
    exit 1
fi

AUTH_HEADER="Authorization: PVEAPIToken=${PROXMOX_API_TOKEN}"

# PCI addresses per node (discovered via lspci)
declare -A GPU_PCI_ADDRESSES=(
    ["churro"]="0000:c6:00.0"
    ["nacho"]="0000:01:00.0"
    ["tamale"]="0000:01:00.0"
)

declare -A GPU_DEVICE_IDS=(
    ["churro"]="1002:1900"
    ["nacho"]="1002:13c0"
    ["tamale"]="1002:13c0"
)

# Build map entries
MAP_ENTRIES=()
for node in churro nacho tamale; do
    MAP_ENTRIES+=("--data-urlencode" "map=node=${node},path=${GPU_PCI_ADDRESSES[$node]},id=${GPU_DEVICE_IDS[$node]}")
done

# Check if mapping already exists
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k \
    -H "${AUTH_HEADER}" \
    "${BASE_URL}/cluster/mapping/pci/${MAPPING_NAME}")

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo "Updating existing PCI mapping '${MAPPING_NAME}'..."
    curl -s -k \
        -H "${AUTH_HEADER}" \
        -X PUT \
        --data-urlencode "description=AMD iGPU for VM passthrough" \
        "${MAP_ENTRIES[@]}" \
        "${BASE_URL}/cluster/mapping/pci/${MAPPING_NAME}" | python3 -m json.tool
else
    echo "Creating PCI mapping '${MAPPING_NAME}'..."
    curl -s -k \
        -H "${AUTH_HEADER}" \
        -X POST \
        --data-urlencode "id=${MAPPING_NAME}" \
        --data-urlencode "description=AMD iGPU for VM passthrough" \
        "${MAP_ENTRIES[@]}" \
        "${BASE_URL}/cluster/mapping/pci/${MAPPING_NAME}" | python3 -m json.tool
fi

echo ""
echo "PCI mapping '${MAPPING_NAME}' configured. Verify in Proxmox UI:"
echo "  Datacenter -> Resource Mappings -> PCI Devices"
