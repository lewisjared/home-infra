#!/bin/bash
# Apply Talos machine configs one node at a time
# This script applies the updated talos configuration to each node

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/tf/output"
TALOSCONFIG="${OUTPUT_DIR}/talosconfig"

echo "=========================================="
echo "Talos Configuration Application Script"
echo "=========================================="
echo ""
echo "This script will apply machine configs to nodes one at a time."
echo "You will be prompted before each node."
echo ""
echo "Using talosconfig: ${TALOSCONFIG}"
echo ""

# Check talosconfig exists
if [[ ! -f "${TALOSCONFIG}" ]]; then
    echo "ERROR: talosconfig not found at ${TALOSCONFIG}"
    exit 1
fi

apply_config() {
    local config_file="$1"
    local node_ip="$2"
    local node_name="$3"

    # Check config file exists
    if [[ ! -f "${OUTPUT_DIR}/${config_file}" ]]; then
        echo "ERROR: Config file not found: ${OUTPUT_DIR}/${config_file}"
        return 1
    fi

    echo "----------------------------------------"
    echo "Node: ${node_name} (${node_ip})"
    echo "Config: ${config_file}"
    echo "----------------------------------------"

    read -p "Apply config to ${node_name}? [y/N/s(skip)/q(quit)] " -n 1 -r
    echo ""

    case "${REPLY}" in
        y|Y)
            echo "Applying config to ${node_name}..."
            talosctl --talosconfig="${TALOSCONFIG}" \
                apply-config \
                --nodes="${node_ip}" \
                --file="${OUTPUT_DIR}/${config_file}"

            echo ""
            echo "Config applied to ${node_name}."
            echo ""

            # Ask if user wants to wait for node to be ready
            read -p "Wait for node health check? [y/N] " -n 1 -r
            echo ""
            if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
                echo "Checking node health (this may take a minute)..."
                sleep 5
                talosctl --talosconfig="${TALOSCONFIG}" \
                    --nodes="${node_ip}" \
                    health --wait-timeout=5m || true
            fi
            ;;
        s|S)
            echo "Skipping ${node_name}..."
            ;;
        q|Q)
            echo "Quitting."
            exit 0
            ;;
        *)
            echo "Skipping ${node_name}..."
            ;;
    esac

    echo ""
}

# Apply configs in order: masters first, then workers
apply_config "machineconfig-talos-master-1.yaml" "10.10.20.51" "talos-master-1"
apply_config "machineconfig-talos-master-2.yaml" "10.10.20.52" "talos-master-2"
apply_config "machineconfig-talos-master-3.yaml" "10.10.20.53" "talos-master-3"
apply_config "machineconfig-talos-worker-1.yaml" "10.10.20.61" "talos-worker-1"
apply_config "machineconfig-talos-worker-2.yaml" "10.10.20.62" "talos-worker-2"

echo "=========================================="
echo "All nodes processed."
echo "=========================================="
