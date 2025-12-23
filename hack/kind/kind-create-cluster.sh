#!/usr/bin/env bash

set -o errexit
set -o pipefail

source $(dirname ${0})/common.sh ''

clusterNameSuffix=$1
lbStart=$2
lbEnd=$3
pathClusterValues=""

glkSuffix="glk"
if [[ $clusterNameSuffix == "single" ]]; then
  glkSuffix="single"
fi

case $clusterNameSuffix in
  $glkSuffix)
    pathClusterValues="$SOURCE_PATH/hack/kind/clusters/glk/values.yaml"
    ;;
  runtime)
    pathClusterValues="$SOURCE_PATH/hack/kind/clusters/runtime/values.yaml"
    ;;
esac

clusterName="$GLK_KIND_CLUSTER_PREFIX-$clusterNameSuffix"

install_metallb() {
  # install metal loadbalancer (see https://kind.sigs.k8s.io/docs/user/loadbalancer/)
  kubectl apply -k "$SOURCE_PATH/hack/kind/metallb" --server-side
  kubectl wait --namespace metallb-system --for=condition=available deployment --selector=app=metallb --timeout=90s

  kindIPAM=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' kind)
  if [[ "$kindIPAM" =~ ([0-9]+\.[0-9]+)(".0.0/24 ") ]]; then
    cidrPrefix=${BASH_REMATCH[1]}
    cidr="$cidrPrefix.0.0/24"
    echo "kind network cidr: $cidr"
  else
    echo "cannot extract IPv4 CIDR from '$kindIPAM'"
  fi

  # Example: 172.18.255.100
  start_range=$cidrPrefix.$GLK_KIND_CLASS_C.$lbStart
  # Example: 172.18.255.200
  end_range=$cidrPrefix.$GLK_KIND_CLASS_C.$lbEnd

  sed -e "s/#range_start/$start_range/g" -e "s/#range_end/$end_range/g" "$SOURCE_PATH/hack/kind/metallb/ipaddresspool.yaml.template" | \
    kubectl apply -f -
}

# setup_kind_network is similar to kind's network creation logic, ref https://github.com/kubernetes-sigs/kind/blob/23d2ac0e9c41028fa252dd1340411d70d46e2fd4/pkg/cluster/internal/providers/docker/network.go#L50
# In addition to kind's logic, we ensure stable CIDRs that we can rely on in our local setup manifests and code.
setup_kind_network() {
  # check if network already exists
  local existing_network_id
  existing_network_id="$(docker network list --filter=name=^kind$ --format='{{.ID}}')"

  if [ -n "$existing_network_id" ] ; then
    # ensure the network is configured correctly
    local network network_options network_ipam expected_network_ipam
    network="$(docker network inspect $existing_network_id | yq '.[]')"
    network_options="$(echo "$network" | yq '.EnableIPv6 + "," + .Options["com.docker.network.bridge.enable_ip_masquerade"]')"
    network_ipam="$(echo "$network" | yq '.IPAM.Config' -o=json -I=0 | sed -E 's/"IPRange":"",//g')"
    expected_network_ipam='[{"Subnet":"172.18.0.0/24","Gateway":"172.18.0.1"},{"Subnet":"fd00:10::/64","Gateway":"fd00:10::1"}]'

    if [ "$network_options" = 'true,true' ] && [ "$network_ipam" = "$expected_network_ipam" ] ; then
      # kind network is already configured correctly, nothing to do
      return 0
    else
      echo "kind network is not configured correctly for local gardener setup, recreating network with correct configuration..."
      docker network rm $existing_network_id
    fi
  fi

  # (re-)create kind network with expected settings
  docker network create kind --driver=bridge \
    --subnet 172.18.0.0/24 --gateway 172.18.0.1 \
    --ipv6 --subnet fd00:10::/64 --gateway fd00:10::1 \
    --opt com.docker.network.bridge.enable_ip_masquerade=true
}

# setup_containerd_registry_mirror sets up a given contained registry mirror.
setup_containerd_registry_mirror() {
  NODE=$1
  UPSTREAM_HOST=$2
  UPSTREAM_SERVER=$3
  MIRROR_HOST=$4

  echo "[${NODE}] Setting up containerd registry mirror for host ${UPSTREAM_HOST}.";
  REGISTRY_DIR="/etc/containerd/certs.d/${UPSTREAM_HOST}"
  docker exec "${NODE}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | docker exec -i "${NODE}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
server = "${UPSTREAM_SERVER}"

[host."${MIRROR_HOST}"]
  capabilities = ["pull", "resolve"]
EOF
}

echo "### creating/updating kind cluster $clusterName"

setup_kind_network

mkdir -p ${SOURCE_PATH}/dev
export KUBECONFIG=${SOURCE_PATH}/dev/kind-$clusterName-kubeconfig.yaml
# only create cluster if not existing
kind get clusters | grep $clusterName &> /dev/null || \
  kind create cluster \
    --name $clusterName \
    --config <(helm template "$SOURCE_PATH/hack/kind/clusters/base" --values "$pathClusterValues" --set "installer.repositoryRoot"="$SOURCE_PATH")

# Deploy registry caches in installer cluster
if [[ $clusterNameSuffix == $glkSuffix ]]; then
  kubectl apply -k "$SOURCE_PATH/hack/kind/registry" --server-side
  kubectl wait --for=condition=available deployment -l app=registry -n registry --timeout 5m
fi

registryHostname=${GLK_KIND_CLUSTER_PREFIX}-${glkSuffix}-control-plane
# Configure containerd to pull images from registry caches
for node in $(kind get nodes --name="$clusterName"); do
  setup_containerd_registry_mirror $node "gcr.io" "https://gcr.io" "http://${registryHostname}:5003"
  setup_containerd_registry_mirror $node "eu.gcr.io" "https://eu.gcr.io" "http://${registryHostname}:5004"
  setup_containerd_registry_mirror $node "ghcr.io" "https://ghcr.io" "http://${registryHostname}:5005"
  setup_containerd_registry_mirror $node "registry.k8s.io" "https://registry.k8s.io" "http://${registryHostname}:5006"
  setup_containerd_registry_mirror $node "quay.io" "https://quay.io" "http://${registryHostname}:5007"
  setup_containerd_registry_mirror $node "europe-docker.pkg.dev" "https://europe-docker.pkg.dev" "http://${registryHostname}:5008"
  setup_containerd_registry_mirror $node "docker.io" "http://docker.io" "http://${registryHostname}:5009"
done

if [[ "$lbStart" != "" ]]; then
  install_metallb
fi

echo "### To access $clusterName cluster, use:"
echo "export KUBECONFIG=$KUBECONFIG"
echo ""
