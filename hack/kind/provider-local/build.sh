#!/usr/bin/env bash

set -o errexit
set -o pipefail

workDir="$1"
gardenerComponentBaseDir="${workDir}/test-landscape/base/components/gardener"
devDir="$1/.."

ensure_gardener_repo_cloned() {
  gardenerVersion=$(yq ".spec.ref.tag" "${gardenerComponentBaseDir}/operator/oci-repository.yaml")

  cd "${devDir}"
  existingVersion=""
  if [ -f gardener/local/VERSION ]; then
    existingVersion=$(cat gardener/local/VERSION || echo "")
  fi

  if [ "$existingVersion" == "$gardenerVersion" ]; then
    echo "✅ Gardener repository already at version: ${gardenerVersion}, skipping clone"
  else
    rm -rf gardener
    echo "🚀 Cloning Gardener version: ${gardenerVersion}"
    git clone https://github.com/gardener/gardener.git -b "$gardenerVersion" --single-branch --depth 1
    mkdir gardener/local
    echo "$gardenerVersion" > gardener/local/VERSION
  fi
}

skaffold_build_and_push_provider_local() {
  cd "${devDir}/gardener"
  BUILD_DATE=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)$$/:\1/g')
  export LD_FLAGS=$("${devDir}/gardener/hack/get-build-ld-flags.sh" k8s.io/component-base ${devDir}/gardener/VERSION Gardener $BUILD_DATE)
  # speed-up skaffold deployments by building all images concurrently
  export SKAFFOLD_BUILD_CONCURRENCY=0
  # build the images for the platform matching the nodes of the active kubernetes cluster, even in `skaffold build`, which doesn't enable this by default
  export SKAFFOLD_CHECK_CLUSTER_NODE_PLATFORMS=true
  export SKAFFOLD_DEFAULT_REPO=registry.local.gardener.cloud:5001
  export SKAFFOLD_PUSH=true
  export SOURCE_DATE_EPOCH=$(date -d $BUILD_DATE +%s)
  export GARDENER_VERSION=$(cat VERSION)

  skaffold build -f skaffold-operator.yaml -m provider-local --file-output=local/build-output.json
}

generate_extension_yaml() {
  tmpDir="${devDir}/gardener/local/provider-local"
  rm -rf "${tmpDir}"
  mkdir -p "${tmpDir}"
  cp -r "${devDir}/gardener/dev-setup/extensions/provider-local/components/extension/" "${tmpDir}"
  patch_file="${tmpDir}/extension/patch-extension-prow.yaml"
  cat <<EOF > "$patch_file"
  apiVersion: operator.gardener.cloud/v1alpha1
  kind: Extension
  metadata:
    name: provider-local
  spec:
    deployment:
      extension:
        values: {}
EOF
  kubectl kustomize "${tmpDir}/extension" > ${tmpDir}/extension.yaml

  declare -A dict
  dict["local-skaffold/gardener-extension-provider-local/charts/extension"]=":v0.0.0"
  dict["local-skaffold/gardener-extension-admission-local/charts/runtime"]=":v0.0.0"
  dict["local-skaffold/gardener-extension-admission-local/charts/application"]=":v0.0.0"
  dict["local-skaffold/machine-controller-manager-provider-local"]=""

  for v in "${!dict[@]}"
  do
    suffix=${dict[$v]}
    ref=$(yq -r ".builds[] | select(.imageName == \"$v\") | .tag" "${devDir}/gardener/local/build-output.json")
    yq eval --inplace "(.. | select(. == \"$v$suffix\")) = \"$ref\"" ${tmpDir}/extension.yaml
  done

  echo "✅ Generated extension.yaml for provider-local"
}

update_component() {
  componentDir="${devDir}/e2e/test-landscape/components/provider-local"
  mkdir -p "${componentDir}"
  cp "${devDir}/gardener/local/provider-local/extension.yaml" "${componentDir}"

  cat <<EOF > "${componentDir}/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- extension.yaml
EOF

  cat <<EOF > "${componentDir}/flux-kustomization.yaml"
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: provider-local
  namespace: garden
spec:
  interval: 30m
  path: components/provider-local
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  dependsOn:
    - name: gardener-operator
      namespace: garden
EOF

  cd "${devDir}/e2e/test-landscape"
  yq eval --inplace '.resources |= (. + ["provider-local/flux-kustomization.yaml"] | unique)' components/kustomization.yaml

  git add components/provider-local components/kustomization.yaml
  git commit -m "Update provider-local" || echo "No changes to commit"
  git push
  echo "✅ Updated component provider-local"
}

ensure_gardener_repo_cloned
skaffold_build_and_push_provider_local
generate_extension_yaml
update_component
