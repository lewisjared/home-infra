#!/usr/bin/env bash

# This script downloads the Flux OpenAPI schemas, then it validates the
# Flux custom resources and the kustomize overlays using kubeconform.
# It also validates all Helm charts by rendering templates.
# This script is meant to be run locally and in CI before the changes
# are merged on the main branch that's synced by Flux.

# Copyright 2023 The Flux authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prerequisites
# - yq v4.34
# - kustomize v5.3
# - kubeconform v0.6
# - helm v3

set -o errexit
set -o pipefail

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="${REPO_DIR}/validation-results"
HELM_TEMPLATES_DIR="${RESULTS_DIR}/helm-templates"
HELM_ERRORS_DIR="${RESULTS_DIR}/helm-errors"

# Counters
HELM_ERRORS=0
KUSTOMIZE_ERRORS=0
YAML_ERRORS=0

# Colors (disabled if not a terminal or NO_COLOR is set)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m' # No Color
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

info()    { echo -e "${BLUE}INFO${NC} - $*"; }
success() { echo -e "${GREEN}SUCCESS${NC} - $*"; }
warn()    { echo -e "${YELLOW}WARNING${NC} - $*"; }
error()   { echo -e "${RED}ERROR${NC} - $*"; }

# mirror kustomize-controller build options
kustomize_flags=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"

# skip Kubernetes Secrets due to SOPS fields failing validation
kubeconform_flags=("-skip=Secret")
kubeconform_config=("-strict" "-ignore-missing-schemas" "-schema-location" "default" "-schema-location" "/tmp/flux-crd-schemas" "-verbose")

# Cleanup and create results directory
rm -rf "$RESULTS_DIR"
mkdir -p "$HELM_TEMPLATES_DIR" "$HELM_ERRORS_DIR"

info "Downloading Flux OpenAPI schemas"
mkdir -p /tmp/flux-crd-schemas/master-standalone-strict
curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | tar zxf - -C /tmp/flux-crd-schemas/master-standalone-strict

info "Validating YAML syntax"
find . -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    echo -e "  ${CYAN}Validating${NC} $file"
    if ! yq e 'true' "$file" > /dev/null; then
      error "YAML validation failed: $file"
      exit 1
    fi
done

info "Validating clusters"
find ./clusters -maxdepth 2 -type f -name '*.yaml' -print0 | while IFS= read -r -d $'\0' file;
  do
    kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}" "${file}"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
      exit 1
    fi
done

info "Validating kustomize overlays"
find . -type f -name $kustomize_config -print0 | while IFS= read -r -d $'\0' file;
  do
    echo -e "  ${CYAN}Validating${NC} kustomization ${file/%$kustomize_config}"
    kustomize build "${file/%$kustomize_config}" "${kustomize_flags[@]}" | \
      kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}"
    if [[ ${PIPESTATUS[0]} != 0 ]]; then
      exit 1
    fi
done

info "Validating Helm charts"

# Add all Helm repositories from helmfile.yaml
info "Adding Helm repositories from helmfile.yaml"
if [[ -f "${REPO_DIR}/helmfile.yaml" ]]; then
  yq '.repositories[] | .name + " " + .url' "${REPO_DIR}/helmfile.yaml" | while read -r name url; do
    helm repo add "$name" "$url" --force-update 2>/dev/null || true
  done
  helm repo update 2>/dev/null || true
else
  warn "helmfile.yaml not found, Helm validation may fail"
fi

# Process each HelmRelease file
helm_release_files=$(find . -type f -name '*.yaml' -exec grep -l "kind: HelmRelease" {} \;)

for helm_file in $helm_release_files; do
  # Extract values only from HelmRelease documents (skip HelmRepository, etc.)
  chart_name=$(yq 'select(.kind == "HelmRelease") | .spec.chart.spec.chart' "$helm_file" 2>/dev/null)
  chart_version=$(yq 'select(.kind == "HelmRelease") | .spec.chart.spec.version' "$helm_file" 2>/dev/null)
  repo_name=$(yq 'select(.kind == "HelmRelease") | .spec.chart.spec.sourceRef.name' "$helm_file" 2>/dev/null)
  release_name=$(yq 'select(.kind == "HelmRelease") | .metadata.name' "$helm_file" 2>/dev/null)
  release_namespace=$(yq 'select(.kind == "HelmRelease") | .metadata.namespace' "$helm_file" 2>/dev/null)

  # Skip if not a valid HelmRelease with chart spec
  if [[ -z "$chart_name" || "$chart_name" == "null" ]]; then
    continue
  fi

  echo -e "${CYAN}Processing${NC} HelmRelease: ${BOLD}$helm_file${NC}"
  echo -e "  Chart: ${CYAN}$chart_name${NC}@$chart_version"
  echo -e "  Release: $release_name (namespace: $release_namespace)"

  # Extract values section to temp file
  values_file="/tmp/helm-values-$$.yaml"
  values_content=$(yq 'select(.kind == "HelmRelease") | .spec.values' "$helm_file" 2>/dev/null)
  if [[ -n "$values_content" && "$values_content" != "null" ]]; then
    echo "$values_content" > "$values_file"
  else
    echo "{}" > "$values_file"
  fi

  # Construct full chart reference
  chart_reference="$chart_name"
  if [[ -n "$repo_name" && "$repo_name" != "null" ]]; then
    chart_reference="$repo_name/$chart_name"
  fi

  # Validate Helm template
  safe_name="${release_namespace}-${release_name}"
  safe_name="${safe_name//:/-}"
  output_file="${HELM_TEMPLATES_DIR}/${safe_name}.yaml"
  error_file="${HELM_ERRORS_DIR}/${safe_name}.err"

  if helm template "$release_name" "$chart_reference" --version "$chart_version" -n "$release_namespace" -f "$values_file" > "$output_file" 2> "$error_file"; then
    echo -e "  ${GREEN}✓${NC} Helm template validation passed"
    line_count=$(wc -l < "$output_file")
    echo -e "  Generated ${CYAN}$line_count${NC} lines of manifest"
    rm -f "$error_file"
  else
    echo -e "  ${RED}✗${NC} Helm template validation ${RED}FAILED${NC}"
    ((HELM_ERRORS++))
  fi

  rm -f "$values_file"
done

# Generate summary report
{
  echo -e "${BOLD}===============================================${NC}"
  echo -e "${BOLD}Validation Results Summary${NC}"
  echo -e "${BOLD}===============================================${NC}"
  echo ""
  echo "Generated: $(date)"
  echo ""
  echo -e "Helm Charts Validated: ${CYAN}$(find "$HELM_TEMPLATES_DIR" -type f | wc -l)${NC}"
  if [[ $HELM_ERRORS -gt 0 ]]; then
    echo -e "Helm Errors: ${RED}$HELM_ERRORS${NC}"
    echo ""
    echo -e "${RED}Error Details:${NC}"
    find "$HELM_ERRORS_DIR" -type f -exec echo "--- {} ---" \; -exec cat {} \;
  else
    echo -e "Helm Errors: ${GREEN}0 ✓${NC}"
  fi
  echo ""
  echo "Output Files:"
  echo "  Rendered templates: $HELM_TEMPLATES_DIR"
  if [[ $HELM_ERRORS -gt 0 ]]; then
    echo "  Error logs: $HELM_ERRORS_DIR"
  fi
  echo ""
} | tee "${RESULTS_DIR}/summary.txt"

echo ""
if [[ $HELM_ERRORS -gt 0 ]]; then
  error "$HELM_ERRORS Helm chart(s) failed validation"
  exit 1
else
  success "Validation complete"
  info "Results saved to: $RESULTS_DIR"
fi

exit 0
