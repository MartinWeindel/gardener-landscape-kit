#!/usr/bin/env bash

set -o errexit
set -o pipefail

clusterNameSuffix=$1

source $(dirname ${0})/common.sh ''

clusterName="$GLK_KIND_CLUSTER_PREFIX-$clusterNameSuffix"

export KUBECONFIG=${SOURCE_PATH}/dev/kind-$clusterName-kubeconfig.yaml

kind delete cluster --name $clusterName

rm -f $KUBECONFIG
