#!/usr/bin/env bash

set -o errexit
set -o pipefail

SCRIPT_DIR=$(dirname ${0})
source $(dirname ${0})/common.sh ''

workDir=$1
mkdir -p "${workDir}"

glk() {
  go run $SOURCE_PATH/cmd/gardener-landscape-kit "$@"
}

ensure_main_as_default_branch() {
  # Ensure git default branch is 'main' (not 'master')
  git config --global init.defaultBranch main
}

ensure_glk_configuration() {
  echo "⚙️  Ensuring GLK configuration"
  git_ssh_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' git-ssh)
  sed -e "s|127.0.0.1:2222|${git_ssh_ip}:22|g" "$SCRIPT_DIR/landscapekitconfiguration-local.yaml" > "${workDir}/landscapekitconfiguration.yaml"
}


clone_or_update_repo() {
  repoName=$1
  destSubDir=$2

  repoUrl=ssh://git@127.0.0.1:2222/srv/git/${repoName}.git
  destDir="${workDir}/${destSubDir}"

  if [ -d "${destDir}/.git" ]; then
    git -C ${destDir} pull
  else
    git clone ${repoUrl} "${destDir}"
  fi
}

generate_base() {
  echo "🌱 Generating base"
  clone_or_update_repo base base

  glk generate base -c "${workDir}/landscapekitconfiguration.yaml" "${workDir}/base"

  cd "${workDir}/base"
  git add .
  git commit -m "Generate base" || echo "No changes to commit"
  git push
}

generate_landscape() {
  echo "🌱 Generating test landscape"
  clone_or_update_repo test-landscape test-landscape

  glk generate landscape -c "${workDir}/landscapekitconfiguration.yaml" "${workDir}/test-landscape"

  cd "${workDir}/test-landscape"
  git add .
  git commit -m "Generate test landscape" || echo "No changes to commit"
  git push
}

ensure_base_as_submodule() {
  echo "🔗 Ensuring base is a submodule of test-landscape"
  cd "${workDir}/test-landscape"

  if [ ! -f .gitmodules ] || ! grep -q "\[submodule \"base\"\]" .gitmodules; then
    git submodule add ../base base
    git add .gitmodules base
    git commit -m "Add base as submodule"
    git push
  else
    echo "Base is already a submodule"
    git submodule update --remote --rebase base
    git add base
    git commit -m "Update base submodule" || echo "No changes to commit"
    git push
  fi
  git submodule update --init
}

ensure_gotk_sync_updated() {
  echo "🔄 Ensuring GOTK sync updated"

  cd "${workDir}/test-landscape"
  sync_yaml="flux/flux-system/gotk-sync.yaml"

  yq eval -i 'select(.metadata.name=="flux-system" and .kind == "GitRepository") |= .spec.include = [{"repository": {"name": "base-repo"}, "fromPath": "components", "toPath": "base/components"}]' "${sync_yaml}"

  # Keep everything except the base-repo GitRepository
  yq eval -i 'select(.metadata.name != "base-repo" or .kind != "GitRepository")' "${sync_yaml}"

  # append base-repo GitRepository
  git_ssh_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' git-ssh)
  cat >> "${sync_yaml}" <<EOF
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: base-repo
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  secretRef:
    name: flux-system
  url: ssh://git@${git_ssh_ip}:22/srv/git/base.git
EOF

  git add "${sync_yaml}"
  git commit -m "Updated GitRepositories" || echo "No changes to commit"
  git push
}

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
  identity: |
$(cat "$workDir/../plain-git-ssh/id_ed25519_flux" | sed 's/^/    /')
  identity.pub: |
$(cat "$workDir/../plain-git-ssh/id_ed25519_flux.pub" | sed 's/^/    /')
  known_hosts: |
$(cat "$workDir/../plain-git-ssh/ssh_known_hosts" | sed 's/^/    /')
EOF
}

ensure_main_as_default_branch

ensure_glk_configuration

generate_base

generate_landscape

ensure_base_as_submodule

ensure_gotk_sync_updated

ensure_flux_secret
