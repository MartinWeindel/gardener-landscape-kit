#!/usr/bin/env bash

# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR=$(dirname $0)
PROJECT_ROOT=$SCRIPT_DIR/../../..

BUILD_DIR=$PROJECT_ROOT/dev/plain-git-ssh

cd "$BUILD_DIR"
docker compose down
