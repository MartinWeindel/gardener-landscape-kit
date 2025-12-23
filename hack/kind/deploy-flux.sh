#!/usr/bin/env bash

set -o errexit
set -o pipefail

source $(dirname ${0})/common.sh ''

workDir=$1
fluxSystemDir="${workDir}/test-landscape/flux/flux-system"

ensure_flux_secret() {
  echo "🔐 Ensuring Flux secret updated"

  secret_yaml="${workDir}/test-landscape/flux/flux-system/git-sync-secret.yaml"

  cat > "${secret_yaml}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: flux-system
  namespace: flux-system
stringData:
  password: testtest
  username: test
EOF
}

ensure_flux_deployment() {
  echo "🚀 Ensuring Flux is deployed"
  kubectl_glk_apply -f "${fluxSystemDir}/gotk-components.yaml"
  kubectl_glk_apply -f "${fluxSystemDir}/git-sync-secret.yaml"
  kubectl_glk_apply -k "${fluxSystemDir}"
}

ensure_flux_secret
ensure_flux_deployment
