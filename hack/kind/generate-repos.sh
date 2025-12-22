#!/usr/bin/env bash

set -o errexit
set -o pipefail

SCRIPT_DIR=$(dirname ${0})
source $(dirname ${0})/common.sh ''

workDir=$(realpath "$1")
mkdir -p "${workDir}"

GIT_SERVER_BASE_URL="http://test:testtest@git.local.gardener.cloud:6080"

glk() {
  go run $SOURCE_PATH/cmd/gardener-landscape-kit "$@"
}

ensure_glk_configuration() {
  echo "⚙️  Ensuring GLK configuration"
  cp "$SCRIPT_DIR/landscapekitconfiguration.yaml" "${workDir}/landscapekitconfiguration.yaml"
}

clone_or_update_repo() {
  repoName=$1
  destSubDir=$2

  repoUrl=$GIT_SERVER_BASE_URL/test/${repoName}.git
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
    git submodule add $GIT_SERVER_BASE_URL/test/base.git base
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

ensure_glk_configuration
generate_base
generate_landscape
ensure_base_as_submodule
