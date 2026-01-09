#!/usr/bin/env bash

set -o errexit
set -o pipefail

source $(dirname ${0})/common.sh '' > /dev/null

cat <<EOF
{
   "glk": "$GLK_KUBECONFIG",
   "runtime": "$RUNTIME_KUBECONFIG"
}
EOF
