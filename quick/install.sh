#!/bin/bash

set +e

function ::prepare() {
  command -v docker >/dev/null || (echo "Install docker first." && exit 1)
  command -v make >/dev/null || (echo "Install make first." && exit 1)
  command -v ifconfig >/dev/null || (echo "Install ifconfig first." && exit 1)
  command -v kind >/dev/null || (echo "Install kind from https://kind.sigs.k8s.io/docs/user/quick-start/ ." && exit 1)
  command -v kubectl >/dev/null || (echo "Install kubectl from https://github.com/kubernetes/kubernetes/releases ." && exit 1)
  command -v istioctl >/dev/null || (echo "Install istioctl from https://github.com/istio/istio/releases/download/1.11.5/" && exit 1)

  ::download .  https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/tools/certs/Makefile.selfsigned.mk
  ::download .  https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/tools/certs/common.mk
}

function ::usage() {
  echo "This utility is used to build Istio mesh clusters on KinD. Both Linux Docker and Docker Desktop for MacOS are supported."
  echo ""
  echo "Usage $0 [arguments]"
  echo "Arguments:"
  echo "  multi-primary: Build a multi-cluster mesh is composed of 2 KinD clusters."
  echo "  single: Build a KindD cluster with Istio installed"
  echo "  msd: Generate microservice demo manifests. One more argument is given as the number of services."
}

function ::main() {
  case $1 in
      "multi-primary")
        ::prepare  
        ::multi_primary
        ;;
      "single")
        ::prepare
        ::single_cluster
        ;;
      *)
        ::usage
        ;;
  esac
}

API_SERVER_ADDR=$(ip a | grep -v kube | grep -v 127.0.0.1 | grep -v docker | grep -v 'br\-' | grep inet | grep -v inet6 | sed 's/\//\ /g' | awk '{print $2}')

CACHE_DIR=".cache"
ISTIO_VERSION=release-1.11
CONFIG_DIR="config"


CLUSTER1=cluster1
CLUSTER2=cluster2
CLUSTER1_CTX=kind-cluster1
CLUSTER2_CTX=kind-cluster2
NETWORK1=network1
NETWORK2=network2
MESH_ID=mesh1

function ::multi_primary() {

echo "Installing " $CLUSTER1  
  
  cat <<EOF | kind create cluster --name $CLUSTER1 --image registry.cn-shenzhen.aliyuncs.com/solarmesh/node:v1.20.7 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
#containerdConfigPatches:
#- |-
#  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
#    endpoint = ["http://${reg_name}:${reg_port}"]
networking:
  apiServerAddress: $API_SERVER_ADDR
  apiServerPort: 6443
nodes:
- role: control-plane   
- role: worker      
EOF 
     
echo "í ½íº… Installing LoadBalancer"

  kubectl apply --wait -f ./config/metallb.yaml >/dev/null
  ::kubectlwait kind-$CLUSTER1 metallb-system

  kubectl apply -f ./config/metallv-cm-${CLUSTER1}.yaml --context ${CLUSTER1_CTX}


echo "Installing " $CLUSTER2  

cat <<EOF | kind create cluster --name $CLUSTER2 --image registry.cn-shenzhen.aliyuncs.com/solarmesh/node:v1.20.7  --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.cloud2go.cn"]
    endpoint = ["http://harbor.cloud2go.cn"]
networking:
  apiServerAddress: ${API_SERVER_ADDR}
  apiServerPort: 6444
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        authorization-mode: "AlwaysAllow"
EOF

  ::gen_mesh_certs ${CLUSTER1} ${CLUSTER2} 
  
  for CLUSTER_ID in `seq ${CLUSTER1} ${CLUSTER2}`; do
    ::install_mesh ${CLUSTER_Id} ${MESH_ID}
  done 

  istioctl x create-remote-secret \
      --context=`${CLUSTER1_CTX}` \
      --name=`${CLUSTER1}` | \
      kubectl apply --context=`${CLUSTER2_CTX}` -f - >/dev/null

  istioctl x create-remote-secret \
      --context=`${CLUSTER2_CTX}` \
      --name=`${CLUSTER2}` | \
      kubectl apply --context=`${CLUSTER1_CTX}` -f - >/dev/null


 ## ::multi_primary_sample ${NEXT_CLUSTER_ID} ${LAST_CLUSTER_ID}
  echo "í ½íº…The context for `::name ${NEXT_CLUSTER_ID}` and `::name ${LAST_CLUSTER_ID}` are `::context ${NEXT_CLUSTER_ID}` and `::context ${LAST_CLUSTER_ID}` respectively."
  echo "í ½íº…Try to access Kiali through port forwarding. Such as: kubectl --context=`::context ${NEXT_CLUSTER_ID}` port-forward -n istio-system --address 0.0.0.0 service/kiali 20001:20001"
}

function ::install_mesh() {
  local CLUSTER_ID=$1
  local CLUSTER_NAME=`$CLUSTER_ID`
  local CLUSTER_CTX=`kind- $CLUSTER_ID`
  local NETWORK_ID=`network $CLUSTER_ID`
  local MESH_ID=$2
  local OPERATOR_MESH=`cat <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  hub: registry.cn-shenzhen.aliyuncs.com/solarmesh
  tag: 1.11.5
  profile: demo
  meshConfig:
    accessLogFile: /dev/stdout
    enableTracing: true
    defaultConfig:
      proxyMetadata:
        ISTIO_META_DNS_CAPTURE: "true"
        ISTIO_META_DNS_AUTO_ALLOCATE: "true"  
  values:
    global:
      meshID: ${MESH_ID}
      multiCluster:
        clusterName: ${CLUSTER_ID}
      network: ${NETWORK_ID}
  components:
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
        k8s: 
          service:
            ports:
              - name: promethues
                port: 9090
                protocol: TCP
                targetPort: 9090
              - name: kiali
                port: 20001
                protocol: TCP
                targetPort: 20001
              - name: networking-agent
                port: 7575
                protocol: TCP
                targetPort: 7575
              - name: bookinfo
                port: 9080
                protocol: TCP
                targetPort: 9080
              - name: grafana
                port: 3000
                protocol: TCP
                targetPort: 3000
              - name: jaeger
                port: 16686
                protocol: TCP
                targetPort: 16686
              - name: status-port
                port: 15021
                protocol: TCP
                targetPort: 15021
              - name: http2
                port: 80
                protocol: TCP
                targetPort: 8080
              - name: https
                port: 443
                protocol: TCP
                targetPort: 8443
              - name: tcp
                port: 31400
                protocol: TCP
                targetPort: 31400
              - name: tls
                port: 15443
                protocol: TCP
                targetPort: 15443
EOF
`
  echo "í ½íº…Installing Istio"
	echo "${OPERATOR_MESH}" | istioctl install --context=${CLUSTER_CTX} -y -f- > /dev/null

	local GATEWAY=`cat <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: cross-network-gateway
spec:
  selector:
    istio: eastwestgateway
  servers:
    - port:
        number: 15443
        name: tls
        protocol: TLS
      tls:
        mode: AUTO_PASSTHROUGH
      hosts:
        - "*.local"
EOF
`
	echo "${GATEWAY}" | kubectl --context="${CLUSTER_CTX}" apply -n istio-system -f - > /dev/null
  kubectl --context="${CLUSTER_CTX}" apply -f ${CONFIG_DIR}/prometheus.yaml > /dev/null
  kubectl --context="${CLUSTER_CTX}" apply -f ${CONFIG_DIR}/grafana.yaml > /dev/null
  kubectl --context="${CLUSTER_CTX}" apply -f ${CONFIG_DIR}/kiali.yaml > /dev/null
}


function ::gen_mesh_certs() {
  local NEXT_CLUSTER_ID=$1
  local LAST_CLUSTER_ID=$2

  echo "í ½íº…Generating mesh certificates"
  mkdir -p certs
  pushd certs > /dev/null
  make -f ../${CACHE_DIR}/Makefile.selfsigned.mk root-ca >/dev/null
  
  for CLUSTER_ID in `seq ${NEXT_CLUSTER_ID} ${LAST_CLUSTER_ID}`; do
    local CLUSTER_NAME=`$CLUSTER_ID`
    local CLUSTER_CTX=kind-`$CLUSTER_ID`
    make -f ../${CACHE_DIR}/Makefile.selfsigned.mk  "${CLUSTER_NAME}"-cacerts >/dev/null
    kubectl --context="${CLUSTER_CTX}" create namespace istio-system
    kubectl --context="${CLUSTER_CTX}" create secret generic cacerts -n istio-system \
      --from-file=${CLUSTER_NAME}/ca-cert.pem \
      --from-file=${CLUSTER_NAME}/ca-key.pem \
      --from-file=${CLUSTER_NAME}/root-cert.pem \
      --from-file=${CLUSTER_NAME}/cert-chain.pem
  done
  popd > /dev/null
}

# kubectlwait context namespace pod-selector(can be name, -l label selector, or --all)
function ::kubectlwait() {
  local CLUSTER_CTX=$1
  shift
  ::wait kubectl --context="${CLUSTER_CTX}" get po -n $@ -o=custom-columns=:metadata.name --no-headers
  local pods=`kubectl --context="${CLUSTER_CTX}" get po -n $@ -o=custom-columns=:metadata.name,:metadata.deletionTimestamp --no-headers | grep '<none>' | awk '{ print $1 }'`
  while IFS= read -r pod; do
    kubectl --context="${CLUSTER_CTX}" wait -n $1 --timeout=10m --for=condition=ready po $pod
  done <<< "$pods"
}

function ::download() {
  local DIR="${CACHE_DIR}/$1"
  local URL=$2
  local LINK_NAME=$3
  local FILE=`basename "${URL}"`
  local FILE_EXT="${FILE##*.}"

  [[ -d "${DIR}" ]] || mkdir -p "${DIR}"
  pushd "${DIR}" > /dev/null
  [[ -f "${FILE}" ]] || (echo "Downloading ${URL}" && curl -skLO "${URL}")
  if [[ "${FILE_EXT}" == "sh" || "${FILE_EXT}" == "${FILE}" ]]; then
    chmod +x ${FILE}
  fi
  if [[ "${LINK_NAME}" != "" && ! -f ${LINK_NAME} ]]; then
    ln -s ${FILE} ${LINK_NAME}
  fi
  popd > /dev/null
}

set -e

::main $@

set +e
