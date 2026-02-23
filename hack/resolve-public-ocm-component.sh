#!/usr/bin/env bash

# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
#
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

componentName="$1"
componentVersion="$2"

# make temp dir for the resolved components
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cat <<EOF > "$tmp_dir/landscapekitconfiguration.yaml"
apiVersion: landscape.config.gardener.cloud/v1alpha1
kind: LandscapeKitConfiguration
ocm:
  repositories:
    - oci://europe-docker.pkg.dev/gardener-project/releases
  rootComponent:
    name: $componentName
    version: $componentVersion
versionConfig:
  componentsVectorFile: $tmp_dir/ocm-components.yaml
EOF

# Fake component as custom OCM component, to be resolved by the landscapekit and written to the components vector file.
echo $componentName > "$tmp_dir/ocm-component-name"

go run ./cmd/gardener-landscape-kit resolve-ocm-components -c "$tmp_dir/landscapekitconfiguration.yaml" -l "$tmp_dir" --ignore-missing-components > /dev/null

cat "$tmp_dir/ocm-components.yaml"
