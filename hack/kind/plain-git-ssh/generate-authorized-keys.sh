#!/usr/bin/env bash

# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

BUILD_DIR=${1:-}
if [ -z "$BUILD_DIR" ]; then
  echo "Usage: $0 <build-dir>"
  exit 1
fi

FLUX_SSH_KEY_FILE="$BUILD_DIR/id_ed25519_flux"
AUTHORIZED_KEYS_FILE="$BUILD_DIR/authorized_keys"

if [ ! -f "$FLUX_SSH_KEY_FILE" ] || [ ! -f "$FLUX_SSH_KEY_FILE.pub" ]; then
  echo "🔐 Generating Flux SSH key pair"
  ssh-keygen -t ed25519 -C "flux@test.glk.gardener.cloud" -f "$FLUX_SSH_KEY_FILE" -q -N ""
fi

echo "🔐 Generating authorized_keys file at '$AUTHORIZED_KEYS_FILE'"
cat > "$AUTHORIZED_KEYS_FILE" <<EOF
# Authorized keys for plain-git-ssh kind cluster

# This file is auto-generated. Do not edit manually.
EOF

echo "🔑  Adding public key for flux from '$FLUX_SSH_KEY_FILE.pub'"
cat "$FLUX_SSH_KEY_FILE.pub" >> "$AUTHORIZED_KEYS_FILE"

echo "🔑  Adding public keys from '~/.ssh/'"
cat ~/.ssh/*.pub >> "$AUTHORIZED_KEYS_FILE"
