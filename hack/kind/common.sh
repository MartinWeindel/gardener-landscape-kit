#!/usr/bin/env bash

# For the check step concourse will set the following environment variables:
# SOURCE_PATH - path to component repository root directory.
if [[ -z "${SOURCE_PATH}" ]]; then
  export SOURCE_PATH="$(readlink -f "$(dirname ${0})/../..${1}")"
else
  export SOURCE_PATH="$(readlink -f ${SOURCE_PATH})"
fi

if [ -z "$GLK_KIND_CLUSTER_PREFIX" ]; then
  export GLK_KIND_CLUSTER_PREFIX=glk
  export GLK_KIND_CLASS_C=255
fi

if kind get clusters | grep $GLK_KIND_CLUSTER_PREFIX-single; then
  export GLK_CLUSTER_NAME=$GLK_KIND_CLUSTER_PREFIX-single
  export GLK_KUBECONFIG=${SOURCE_PATH}/dev/kind-$GLK_CLUSTER_NAME-kubeconfig.yaml

  export RUNTIME_CLUSTER_NAME=$GLK_KIND_CLUSTER_PREFIX-single
  export RUNTIME_KUBECONFIG=${SOURCE_PATH}/dev/kind-$RUNTIME_CLUSTER_NAME-kubeconfig.yaml
else
  export GLK_CLUSTER_NAME=$GLK_KIND_CLUSTER_PREFIX-glk
  export GLK_KUBECONFIG=${SOURCE_PATH}/dev/kind-$GLK_CLUSTER_NAME-kubeconfig.yaml

  export RUNTIME_CLUSTER_NAME=$GLK_KIND_CLUSTER_PREFIX-runtime
  export RUNTIME_KUBECONFIG=${SOURCE_PATH}/dev/kind-$RUNTIME_CLUSTER_NAME-kubeconfig.yaml
fi
