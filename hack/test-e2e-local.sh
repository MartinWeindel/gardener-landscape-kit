#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

echo "> E2E Tests"

source "$(dirname "$0")/test-e2e-local.env"

ginkgo run --timeout=15m --v --show-node-events "$@"
