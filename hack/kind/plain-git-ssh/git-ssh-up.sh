#!/usr/bin/env bash

# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR=$(dirname $0)
PROJECT_ROOT=$SCRIPT_DIR/../../..

BUILD_DIR=$PROJECT_ROOT/dev/plain-git-ssh

REPOS_DIR="$BUILD_DIR/repos"
mkdir -p "$REPOS_DIR"

cp "$SCRIPT_DIR"/container/* "$BUILD_DIR"

$SCRIPT_DIR/generate-authorized-keys.sh "$BUILD_DIR"

cd "$BUILD_DIR"
docker compose up -d --build

for i in {1..150}; do
  if ssh-keyscan -p 2222 127.0.0.1 > /dev/null 2>/dev/null; then
    break
  fi
  if [ $i -eq 15 ]; then
    echo "Failed to scan SSH keys after 15 attempts"
    exit 1
  fi
  sleep 0.1
done
echo "🚀 plain-git-ssh kind cluster is up and running"

# Generate SSH known hosts file for access from inside of kind network
git_ssh_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' git-ssh)
ssh-keyscan -p 2222 127.0.0.1 | sed -e "s|127.0.0.1:2222|${git_ssh_ip}:22|g" | sed -e "s|\[127\.0\.0\.1\]:2222|${git_ssh_ip}|g" > "$BUILD_DIR/ssh_known_hosts"

echo "🔐 Generated SSH known hosts at '$BUILD_DIR/ssh_known_hosts'"

