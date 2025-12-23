#!/usr/bin/env bash

set -o errexit
set -o pipefail

SCRIPT_DIR=$(dirname ${0})
source $(dirname ${0})/common.sh ''

workDir=$1
fluxSystemDir="${workDir}/test-landscape/flux/flux-system"

ensure_flux_deployment() {
  echo "🚀 Ensuring Flux is deployed"
  kubectl_glk_apply -f "${fluxSystemDir}/gotk-components.yaml"
  kubectl_glk_apply -f "${fluxSystemDir}/git-sync-secret.yaml"
  kubectl_glk_apply -k "${fluxSystemDir}"
}

ensure_flux_deployment