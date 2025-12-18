#!/bin/bash
# =============================================================================
# Bootstrap Flux on Talos Production Cluster
# =============================================================================
# Run this after Terraform recreates the Talos VMs.
#
# Prerequisites:
# 1. GITHUB_TOKEN environment variable set (with repo scope)
# 2. Terraform has completed and cluster is healthy
# 3. kubeconfig is available at tf/talos/kubeconfig
#
# Usage:
#   export GITHUB_TOKEN=ghp_xxxx
#   ./scripts/bootstrap-flux.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBECONFIG_PATH="$REPO_ROOT/tf/talos/kubeconfig"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Flux Bootstrap Script ===${NC}"

# Check prerequisites
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo -e "${RED}Error: GITHUB_TOKEN environment variable is not set${NC}"
    echo "Create a token at https://github.com/settings/tokens with 'repo' scope"
    echo "Then run: export GITHUB_TOKEN=ghp_xxxx"
    exit 1
fi

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    echo -e "${RED}Error: kubeconfig not found at $KUBECONFIG_PATH${NC}"
    echo "Run 'tofu apply' in tf/ directory first"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Wait for cluster to be ready
echo -e "${YELLOW}Waiting for Kubernetes cluster to be ready...${NC}"
until kubectl get nodes &>/dev/null; do
    echo "  Waiting for API server..."
    sleep 5
done

echo -e "${GREEN}Cluster is accessible${NC}"
kubectl get nodes

# Wait for all nodes to be Ready
echo -e "${YELLOW}Waiting for all nodes to be Ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Check if Flux is already installed
if kubectl get namespace flux-system &>/dev/null; then
    echo -e "${YELLOW}Flux namespace already exists. Checking status...${NC}"
    if flux check &>/dev/null; then
        echo -e "${GREEN}Flux is already installed and healthy${NC}"
        flux get all
        exit 0
    else
        echo -e "${YELLOW}Flux namespace exists but may need re-bootstrap${NC}"
    fi
fi

# Bootstrap Flux
echo -e "${GREEN}Bootstrapping Flux...${NC}"
flux bootstrap github \
    --owner=lewisjared \
    --repository=home-infra \
    --branch=main \
    --path=clusters/production \
    --personal \
    --token-auth

echo ""
echo -e "${GREEN}=== Flux Bootstrap Complete ===${NC}"
echo ""
echo "Monitor reconciliation with:"
echo "  flux get kustomizations -w"
echo "  kubectl get pods -A -w"
