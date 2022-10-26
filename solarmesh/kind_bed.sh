#!/bin/bash

CLUSTER_NAME_PREFIX="cluster"
CACHE_DIR=".cache"
API_SERVER_ADDR=172.31.0.1
ISTIO_VERSION=release-1.15

function ::name() {
  local CLUSTER_ID=$1
  echo "${CLUSTER_NAME_PREFIX}${CLUSTER_ID}"
}

function ::find_next_cluster_id() {
  local LAST_CLUSTER=`kind get clusters | grep cluster | tail -1`
  if [[ "${LAST_CLUSTER}" = "" ]]; then
    echo "1"
  else
    echo $((${LAST_CLUSTER#"$CLUSTER_NAME_PREFIX"} + 1))
  fi
}

function ::context() {
  local CLUSTER_ID=$1
  echo "kind-`::name ${CLUSTER_ID}`"
}

function ::network() {
  local CLUSTER_ID=$1
  echo "network${CLUSTER_ID}"
}

function ::calc_network() {
  local CLUSTER_ID=$1
  docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' kind | awk \
    -v clusterID="$CLUSTER_ID" \
    -F"." 'BEGIN { OFS = "." } { print $1,$2,255-clusterID,"0/24" }'
}

function ::wait() {
  local out=$($@)
  while [ "$out" == "" ]; do
    sleep 1
    out=$($@)
  done
}

# kubectlwait context namespace pod-selector(can be name, -l label selector, or --all)
function ::kubectlwait_once() {
  local CLUSTER_CTX=$1
  shift
  ::wait kubectl --context="${CLUSTER_CTX}" get po -n $@ -o=custom-columns=:metadata.name --no-headers
  local pods=`kubectl --context="${CLUSTER_CTX}" get po -n $@ -o=custom-columns=:metadata.name,:metadata.deletionTimestamp --no-headers | grep '<none>' | awk '{ print $1 }'`
  while IFS= read -r pod; do
    kubectl --context="${CLUSTER_CTX}" wait -n $1 --timeout=10m --for=condition=ready po $pod
  done <<< "$pods"
}

function ::kubectlwait() {
  ::kubectlwait_once $@
  ::kubectlwait_once $@
}

function ::create_cluster_with_mounts() {
  local CLUSTER_ID=$1
	local CLUSTER_NAME=`::name $CLUSTER_ID`
  local CLUSTER_CTX=`::context $CLUSTER_ID`
	local API_SERVER_ADDR=$2
	local CLUSTER_CONF=`cat <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "${API_SERVER_ADDR}"
nodes:
- role: control-plane
  extraMounts:
    - hostPath: /home/ctg/solarmesh/grafana
      containerPath: /grafana   
EOF
`

	echo "${CLUSTER_CONF}" | HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= kind create cluster -n "${CLUSTER_NAME}" --image kindest/node:v1.25.0 --config - > /dev/null
  echo "🚅Installing LoadBalancer"
  kubectl apply --wait -f ${CACHE_DIR}/metallb-native.yaml >/dev/null
  ::kubectlwait ${CLUSTER_CTX} metallb-system
  
  local LB_IP_SUBNET=`::calc_network $CLUSTER_ID`
  local LB_CONF=`cat <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - ${LB_IP_SUBNET}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
`
  echo "${LB_CONF}" | kubectl apply --wait -f - >/dev/null
}

function ::create_cluster() {
  local CLUSTER_ID=$1
	local CLUSTER_NAME=`::name $CLUSTER_ID`
  local CLUSTER_CTX=`::context $CLUSTER_ID`
	local API_SERVER_ADDR=$2
	local CLUSTER_CONF=`cat <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "${API_SERVER_ADDR}"
EOF
`

	echo "${CLUSTER_CONF}" | HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= kind create cluster -n "${CLUSTER_NAME}" --image kindest/node:v1.25.0 --config - > /dev/null
  echo "������Installing LoadBalancer"
  kubectl apply --wait -f ${CACHE_DIR}/metallb-native.yaml >/dev/null
  ::kubectlwait ${CLUSTER_CTX} metallb-system
  
  local LB_IP_SUBNET=`::calc_network $CLUSTER_ID`
  local LB_CONF=`cat <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - ${LB_IP_SUBNET}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
`
  echo "${LB_CONF}" | kubectl apply --wait -f - >/dev/null
}

function ::install_mesh() {
  local CLUSTER_ID=$1
  local CLUSTER_NAME=`::name $CLUSTER_ID`
  local CLUSTER_CTX=`::context $CLUSTER_ID`
  local NETWORK_ID=`::network $CLUSTER_ID`
	local MESH_ID=$2
	local OPERATOR_MESH=`cat <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
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
      - name: istio-eastwestgateway
        label:
          istio: eastwestgateway
          app: istio-eastwestgateway
          topology.istio.io/network: ${NETWORK_ID}
        enabled: true
        k8s:
          env:
            # traffic through this gateway should be routed inside the network
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
              value: ${NETWORK_ID}
          service:
            ports:
              - name: status-port
                port: 15021
                targetPort: 15021
              - name: tls
                port: 15443
                targetPort: 15443
              - name: tls-istiod
                port: 15012
                targetPort: 15012
              - name: tls-webhook
                port: 15017
                targetPort: 15017
  values:
    gateways:
      istio-ingressgateway:
        injectionTemplate: gateway
    global:
      meshID: ${MESH_ID}
      multiCluster:
        clusterName: ${CLUSTER_NAME}
      network: ${NETWORK_ID}
EOF
`
  echo "🚅Installing Istio"
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
  kubectl --context="${CLUSTER_CTX}" apply -f ${CACHE_DIR}/prometheus.yaml > /dev/null
 # kubectl --context="${CLUSTER_CTX}" apply -f ${CACHE_DIR}/grafana.yaml > /dev/null
  kubectl --context="${CLUSTER_CTX}" apply -f ${CACHE_DIR}/kiali.yaml > /dev/null
}

function ::gen_mesh_certs() {
  local NEXT_CLUSTER_ID=$1
  local LAST_CLUSTER_ID=$2

  echo "🚅Generating mesh certificates"
  mkdir -p certs
  pushd certs > /dev/null
  make -f ../${CACHE_DIR}/Makefile.selfsigned.mk root-ca >/dev/null
  
  for CLUSTER_ID in `seq ${NEXT_CLUSTER_ID} ${LAST_CLUSTER_ID}`; do
    local CLUSTER_NAME=`::name $CLUSTER_ID`
    local CLUSTER_CTX=`::context $CLUSTER_ID`
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

function ::bind_apiserver_address_linux() {
  local API_SERVER_ADDR=$1
  if [[ `ifconfig | grep ${API_SERVER_ADDR}` == "" ]]; then
    ifconfig lo add "${API_SERVER_ADDR}"
  fi
}

function ::bind_apiserver_address_macos() {
  local API_SERVER_ADDR=$1
  if [[ `ifconfig | grep ${API_SERVER_ADDR}` == "" ]]; then
    ifconfig lo0 alias "${API_SERVER_ADDR}"
  fi
}

function ::bind_apiserver_address() {
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ::bind_apiserver_address_linux $1
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    ::bind_apiserver_address_macos $1
  fi
}

function ::sample_validate() {
  local COUNTER=0
  local HAS_V1=""
  local HAS_V2=""

  while [[ ( "${HAS_V1}" == "" || "${HAS_V2}" == "" ) && $COUNTER -lt 10 ]]; do
    local OUT=`$@`
    if [[ "${HAS_V1}" == "" ]]; then
      HAS_V1=`echo "${OUT}" | grep v1 || true`
    fi

    if [[ "${HAS_V2}" == "" ]]; then
      HAS_V2=`echo "${OUT}" | grep v2 || true`
    fi
    
    COUNTER=$(( ${COUNTER} + 1 ))
  done

  if [[ "${HAS_V1}" == "" || "${HAS_V2}" == "" ]]; then
    echo "Multi primary cluster test failed!"
    exit 1
  fi
}

function ::multi_primary_sample() {
  echo "🚅Installing test programs for multi primary clusters"
  CTX_CLUSTER1=`::context $1`
  CTX_CLUSTER2=`::context $2`
  pushd "${CACHE_DIR}" > /dev/null
  kubectl create --context="${CTX_CLUSTER1}" namespace sample > /dev/null
  kubectl create --context="${CTX_CLUSTER2}" namespace sample > /dev/null
  kubectl label --context="${CTX_CLUSTER1}" namespace sample \
      istio-injection=enabled > /dev/null
  kubectl label --context="${CTX_CLUSTER2}" namespace sample \
      istio-injection=enabled > /dev/null
  kubectl apply --context="${CTX_CLUSTER1}" \
      -f samples/helloworld/helloworld.yaml \
      -l service=helloworld -n sample > /dev/null
  kubectl apply --context="${CTX_CLUSTER2}" \
      -f samples/helloworld/helloworld.yaml \
      -l service=helloworld -n sample > /dev/null
  kubectl apply --context="${CTX_CLUSTER1}" \
      -f samples/helloworld/helloworld.yaml \
      -l version=v1 -n sample > /dev/null
  kubectl apply --context="${CTX_CLUSTER2}" \
      -f samples/helloworld/helloworld.yaml \
      -l version=v2 -n sample > /dev/null
  kubectl apply --context="${CTX_CLUSTER1}" \
      -f samples/sleep/sleep.yaml -n sample > /dev/null
  kubectl apply --context="${CTX_CLUSTER2}" \
      -f samples/sleep/sleep.yaml -n sample > /dev/null
  popd > /dev/null

  ::kubectlwait ${CTX_CLUSTER1} sample
  ::kubectlwait ${CTX_CLUSTER2} sample

  ::sample_validate kubectl exec --context="${CTX_CLUSTER1}" -n sample -c sleep \
      "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sample -l \
      app=sleep -o jsonpath='{.items[0].metadata.name}')" \
      -- curl -sS helloworld.sample:5000/hello
  
  ::sample_validate kubectl exec --context="${CTX_CLUSTER2}" -n sample -c sleep \
      "$(kubectl get pod --context="${CTX_CLUSTER2}" -n sample -l \
      app=sleep -o jsonpath='{.items[0].metadata.name}')" \
      -- curl -sS helloworld.sample:5000/hello

  kubectl --context="${CTX_CLUSTER1}" delete ns sample > /dev/null
  kubectl --context="${CTX_CLUSTER2}" delete ns sample > /dev/null
}

function ::install_solarmesh(){
  local CLUSTER_ID=$1
  local CLUSTER_NAME=`::name $CLUSTER_ID`
  local CLUSTER_CTX=`::context $CLUSTER_ID`     
  
  if [ -n "$2" ] ;then
    CLUSTER_CTX=$2  
  fi

  kubectl config use-context ${CLUSTER_CTX}
  
  echo "Installing SolarMesh"
  
  solarctl install solar-mesh 

  ::kubectlwait ${CLUSTER_CTX} service-mesh
  ::kubectlwait ${CLUSTER_CTX} solar-operator
  
  kubectl create secret generic admin --from-literal=username=admin --from-literal=password=admin -n service-mesh
  kubectl label secret admin app=solar-controller -n service-mesh  
   
 echo "Installing SolarMesh Bussiness"

  export ISTIOD_REMOTE_EP=$(kubectl get nodes|awk '{print $1}' |awk 'NR==2'|xargs -n 1 kubectl get nodes  -o jsonpath='{.status.addresses[0].address}')
  solarctl operator init --external-ip $ISTIOD_REMOTE_EP --eastwest-external-ip $ISTIOD_REMOTE_EP 
  
  kubectl create ns service-mesh || true
  
  local SOLAR_CONF=`cat <<EOF
apiVersion: install.solar.io/v1alpha1
kind: SolarOperator
metadata:
  name: ${CLUSTER_NAME}
  namespace: solar-operator
spec:
  istioVersion: "1.15"  ## 对应您Istio的安装版本
  profile: default
EOF
`

  echo "${SOLAR_CONF}" | kubectl apply --wait -f - >/dev/null
  
  ::kubectlwait ${CLUSTER_CTX} service-mesh
  ::kubectlwait ${CLUSTER_CTX} solar-operator 

  echo  "Register"
  solarctl register --name ${CLUSTER_NAME}
  
  echo "Installing grafana"
  solarctl install grafana --name ${CLUSTER_NAME}

  echo "Installing bookinfo demo"
  kubectl create ns bookinfo || true
  solarctl install bookinfo -n bookinfo
  kubectl label ns bookinfo "istio-injection=enabled" --overwrite
  kubectl rollout restart deploy -n bookinfo	 
 
  echo "Installing wasm"
  ::wasm ${CLUSTER_CTX}

  echo "Try to access SolarMesh through port forwarding. Such as: kubectl --context=${CLUSTER_CTX}  port-forward --address 0.0.0.0 service/solar-controller -n service-mesh 30880:8080"
  echo "Try to access Bookinfo through port forwarding. Such as: kubectl --context=${CLUSTER_CTX} port-forward --address 0.0.0.0 service/productpage -n bookinfo 9080:9080"
  echo "Try to access Grafana through port forwarding. Such as: kubectl --context=${CLUSTER_CTX} port-forward --address 0.0.0.0 service/grafana -n solarmesh-monitoring 3000:3000"
  
}

function ::wasm(){
 
 kubectl config use-context $1
   
  local LOCAL_CONF=`cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: mesher-config
  namespace: service-mesh
data:
  application.yml: |
    config:
      name: "mesher"
      version: "v1.0.0"
      istiod_name: "discovery"
      in_cluster: true
      web_hook_url: http://mesh.apps.cloud2go.cn/service-mesh/mesher/traffic/alarm/hook
      mesh_namespace: service-mesh
      limit: 20
      addonComponents:
        prometheus:
          enabled: true
      istio_namespace: "istio-system"
      prometheus:
        auth:
          custom_metrics_url: "http://prometheus.istio-system:9090"
          url: "http://prometheus.istio-system:9090"
      mail_client:
        host: 
        from_email_address: 
        port: 
        ssl: 
        username: 
        password: 
      api:
        api_namespaces_config:
          exclude:
            - "istio-operator"
            - "kube.*"
            - "openshift.*"
            - "prometheus-operator"
            - "ibm.*"
            - "kial-operator"
            - "istio-system"
            - "kong"
      certificate:
        home_dir: /etc
      wasmPlugins:
      - name: dataclean
        nickname: 数据脱敏
        description: 脱敏手机号
        uri: http://release.solarmesh.cn/wasm/data-cleaning.wasm
        type: 0
      - name: notice
        nickname: 通知公告
        description: 版本更新公告
        uri: http://release.solarmesh.cn/wasm/notice.wasm
        type: 0
EOF
`

  echo "${LOCAL_CONF}" | kubectl apply --wait -f - >/dev/null
  
  kubectl rollout restart deploy solar-controller  -n service-mesh 

} 

function ::read() {
  local URL=$1
  local FILE=`basename "${URL}"`
  [[ -d "${CACHE_DIR}" ]] || mkdir -p "${CACHE_DIR}"
  pushd "${CACHE_DIR}" > /dev/null
  [[ -f "${FILE}" ]] || curl -skLO ${URL} > /dev/null
  cat ${FILE}
  popd > /dev/null
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

function ::simple_prepare() {
  command -v docker >/dev/null || (echo "Install docker first." && exit 1)
  command -v make >/dev/null || (echo "Install make first." && exit 1)
  command -v ifconfig >/dev/null || (echo "Install ifconfig first." && exit 1)
  command -v kubectl >/dev/null || (echo "Install kubectl from https://github.com/kubernetes/kubernetes/releases ." && exit 1)
  command -v istioctl >/dev/null || (echo "Install istioctl from https://gcsweb.istio.io/gcs/istio-release/releases/1.15.0/" && exit 1)
  command -v solarctl >/dev/null || (echo "Install istioctl from http://release.solarmesh.cn/solar/v1.11/" && exit 1)

  ::download . https://ghproxy.com/https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml
  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/prometheus.yaml
  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/kiali.yaml
  ::download samples/helloworld https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/helloworld/helloworld.yaml
  ::download samples/sleep https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/sleep/sleep.yaml

  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/tools/certs/Makefile.selfsigned.mk
  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/tools/certs/common.mk
  
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ::download . https://ghproxy.com/https://github.com/warm-metal/ms-demo-gen/releases/download/v0.1.6/msdgen-linux msdgen
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    ::download . https://ghproxy.com/https://github.com/warm-metal/ms-demo-gen/releases/download/v0.1.6/msdgen-macos msdgen
  fi

  systemctl stop firewalld || true
}


function ::prepare() {
  command -v docker >/dev/null || (echo "Install docker first." && exit 1)
  command -v make >/dev/null || (echo "Install make first." && exit 1)
  command -v ifconfig >/dev/null || (echo "Install ifconfig first." && exit 1)
  command -v kind >/dev/null || (echo "Install kind from https://kind.sigs.k8s.io/docs/user/quick-start/ ." && exit 1)
  command -v kubectl >/dev/null || (echo "Install kubectl from https://github.com/kubernetes/kubernetes/releases ." && exit 1)
  command -v istioctl >/dev/null || (echo "Install istioctl from https://gcsweb.istio.io/gcs/istio-release/releases/1.15.0/" && exit 1)
  command -v solarctl >/dev/null || (echo "Install istioctl from http://release.solarmesh.cn/solar/v1.11/" && exit 1)
  
  ::bind_apiserver_address "${API_SERVER_ADDR}"
  
  ::download . https://ghproxy.com/https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml
  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/prometheus.yaml
  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/kiali.yaml
 #::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/release-1.15/samples/addons/grafana.yaml

  ::download samples/helloworld https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/helloworld/helloworld.yaml
  ::download samples/sleep https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/sleep/sleep.yaml

  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/tools/certs/Makefile.selfsigned.mk
  ::download . https://ghproxy.com/https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/tools/certs/common.mk
  
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ::download . https://ghproxy.com/https://github.com/warm-metal/ms-demo-gen/releases/download/v0.1.6/msdgen-linux msdgen
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    ::download . https://ghproxy.com/https://github.com/warm-metal/ms-demo-gen/releases/download/v0.1.6/msdgen-macos msdgen
  fi

  systemctl stop firewalld || true
}

function ::multi_primary() {
  local NUM_CLUSTERS=2
  local MESH_ID=mesh1

  local NEXT_CLUSTER_ID=`::find_next_cluster_id`
  local LAST_CLUSTER_ID=$((${NEXT_CLUSTER_ID} + ${NUM_CLUSTERS} - 1))

  for CLUSTER_ID in `seq ${NEXT_CLUSTER_ID} ${LAST_CLUSTER_ID}`; do
      ::create_cluster ${CLUSTER_ID} ${API_SERVER_ADDR}
  done

  ::gen_mesh_certs ${NEXT_CLUSTER_ID} ${LAST_CLUSTER_ID}

  for CLUSTER_ID in `seq ${NEXT_CLUSTER_ID} ${LAST_CLUSTER_ID}`; do
      ::install_mesh ${CLUSTER_ID} ${MESH_ID}
  done

  istioctl x create-remote-secret \
      --context=`::context ${LAST_CLUSTER_ID}` \
      --name=`::name ${LAST_CLUSTER_ID}` | \
      kubectl apply --context=`::context ${NEXT_CLUSTER_ID}` -f - >/dev/null

  istioctl x create-remote-secret \
      --context=`::context ${NEXT_CLUSTER_ID}` \
      --name=`::name ${NEXT_CLUSTER_ID}` | \
      kubectl apply --context=`::context ${LAST_CLUSTER_ID}` -f - >/dev/null

  ::multi_primary_sample ${NEXT_CLUSTER_ID} ${LAST_CLUSTER_ID}

  ::install_solarmesh ${NEXT_CLUSTER_ID}
  ::install_solarmesh ${LAST_CLUSTER_ID}

  echo "🚅The context for `::name ${NEXT_CLUSTER_ID}` and `::name ${LAST_CLUSTER_ID}` are `::context ${NEXT_CLUSTER_ID}` and `::context ${LAST_CLUSTER_ID}` respectively."
  echo "🚅Try to access Kiali through port forwarding. Such as: kubectl --context=`::context ${NEXT_CLUSTER_ID}` port-forward -n istio-system --address  0.0.0.0 service/kiali 20001:20001"
}

function ::single_cluster() {
  local CLUSTER_ID=`::find_next_cluster_id`
  local MESH_ID=mesh1
  ::create_cluster ${CLUSTER_ID} ${API_SERVER_ADDR}
  ::install_mesh ${CLUSTER_ID} ${MESH_ID}
  echo "🚅The context for `::name ${CLUSTER_ID}` is `::context ${CLUSTER_ID}`."
  echo "🚅Try to access Kiali through port forwarding. Such as: kubectl --context=`::context ${CLUSTER_ID}` port-forward -n istio-system --address l0.0.0.0 service/kiali 20001:20001"
}

function ::single_cluster_solarmesh() {
  local CLUSTER_ID=`::find_next_cluster_id`
  local MESH_ID=mesh1
  ::create_cluster ${CLUSTER_ID} ${API_SERVER_ADDR}
  ::install_mesh ${CLUSTER_ID} ${MESH_ID}
  ::install_solarmesh ${CLUSTER_ID} 
  echo "The context for `::name ${CLUSTER_ID}` is `::context ${CLUSTER_ID}`."
  echo "Try to access Kiali through port forwarding. Such as: kubectl --context=`::context ${CLUSTER_ID}` port-forward -n istio-system --address l0.0.0.0 service/kiali 20001:20001"
}

function ::istio(){
  local CLUSTER_NAME=cluster1
  local NETWORK_ID=network1
  local MESH_ID=mesh1
  local OPERATOR_MESH=`cat <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
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
      - name: istio-eastwestgateway
        label:
          istio: eastwestgateway
          app: istio-eastwestgateway
          topology.istio.io/network: ${NETWORK_ID}
        enabled: true
        k8s:
          env:
            # traffic through this gateway should be routed inside the network
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
              value: ${NETWORK_ID}
          service:
            ports:
              - name: status-port
                port: 15021
                targetPort: 15021
              - name: tls
                port: 15443
                targetPort: 15443
              - name: tls-istiod
                port: 15012
                targetPort: 15012
              - name: tls-webhook
                port: 15017
                targetPort: 15017
  values:
    gateways:
      istio-ingressgateway:
        injectionTemplate: gateway
    global:
      meshID: ${MESH_ID}
      multiCluster:
        clusterName: ${CLUSTER_NAME}
      network: ${NETWORK_ID}
EOF
`
  echo "������Installing Istio"
  echo "${OPERATOR_MESH}" | istioctl install -y -f- > /dev/null

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
  echo "${GATEWAY}" | kubectl apply -n istio-system -f - > /dev/null
  kubectl apply -f ${CACHE_DIR}/prometheus.yaml > /dev/null
  kubectl apply -f ${CACHE_DIR}/kiali.yaml > /dev/null
}

function ::k8s(){
  local CLUSTER_ID=`::find_next_cluster_id`
  local MESH_ID=mesh1
  ::create_cluster  ${CLUSTER_ID} ${API_SERVER_ADDR}  
}

function ::k8s_with_mounts(){
  local CLUSTER_ID=`::find_next_cluster_id`
  local MESH_ID=mesh1
  ::create_cluster_with_mounts ${CLUSTER_ID} ${API_SERVER_ADDR}
}

function ::standard_solarmesh(){
  ::istio
  ::install_solarmesh 1 "kubernetes-admin@kubernetes"

  kubectl --context="kubernetes-admin@kubernetes" patch svc solar-controller -n service-mesh -p '{
   "spec": {
        "ports":  [{
            "name": "http-8080",
            "nodePort": 30880,
            "port": 8080,
            "protocol": "TCP",
            "targetPort": 8080}],
        "type": "NodePort"
    }
  }'

  kubectl --context="kubernetes-admin@kubernetes"  patch svc -n bookinfo productpage -p '{
   "spec": {
        "ports": [{
            "name": "http",
            "nodePort": 30201,
            "port": 9080,
            "protocol": "TCP",
            "targetPort": 9080}],
        "type": "NodePort"
    }
  }'
}

function ::solarmesh(){
  local LAST_CLUSTER=`kind get clusters | grep cluster | tail -1`
  local MESH_ID=mesh1
  ::install_solarmesh ${LAST_CLUSTER}
  echo "The context for `::name ${CLUSTER_ID}` is `::context ${CLUSTER_ID}`."
  echo "Try to access SolarMesh through port forwarding. Such as: kubectl --context=`::context ${CLUSTER_ID}` port-forward --address 0.0.0.0 service/solar-controller -n service-mesh 30880:8080"
  echo "Try to access Bookinfo through port forwarding. Such as: kubectl --context=`::context ${CLUSTER_ID}` port-forward --address 0.0.0.0 service/productpage -n bookinfo 9080:9080"
  echo "Try to access Grafana through port forwarding. Such as: kubectl --context=`::context ${CLUSTER_ID}` port-forward --address 0.0.0.0 service/grafana -n solarmesh-monitoring 3000:3000"
}

function ::usage() {
  echo "This utility is used to build Istio mesh clusters on KinD. Both Linux Docker and Docker Desktop for MacOS are supported."
  echo ""
  echo "Usage $0 [arguments]"
  echo "Arguments:"
  echo "  multi-primary: Build a multi-cluster mesh is composed of 2 KinD clusters."
  echo "  single: Build a KindD cluster with Istio installed"
  echo "  single-solarmesh: Build a KindD cluster with Istio and SolarMesh installed"
  echo "  solarmesh: Install solarmesh"
  echo "  msd: Generate microservice demo manifests. One more argument is given as the number of services."
  echo "  k8s: Build a KindD cluster with Kubernetes installed"
  echo "  k8s-mount: Build a KindD k8s cluster with local storage volumes"
  echo "  istio: Install istio on standard k8s cluster"
  echo "  standard-solarmesh: Install solarmesh on standard k8s cluster"
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
      "single-solarmesh")
        ::prepare
        ::single_cluster_solarmesh
        ;; 
      "msd")
        ::prepare
        shift
        ./${CACHE_DIR}/msdgen $@
        ;;
      "k8s")
        ::prepare
        ::k8s
        ;;
      "k8s-mount")
        ::prepare
        ::k8s_k8s_with_mounts
        ;;
      "solarmesh")
        ::prepare
        ::solarmesh
        ;;
      "istio")
        ::simple_prepare
        ::istio
        ;;
      "standard-solarmesh")
        ::simple_prepare
        ::standard_solarmesh
        ;;    
      *)
        ::usage
        ;;
  esac
}

set -e

::main $@

set +e
