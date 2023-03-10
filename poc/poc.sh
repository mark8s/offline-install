#!/bin/bash

CACHE_DIR=".cache"
CLUSTER_NAME_PREFIX="cluster"
HUB="registry.cn-shenzhen.aliyuncs.com/solarmesh"
ISTIO_TAG="1.11.5"
SOLAR_TAG="v1.11.4"
IP=$(ip a | grep -v kube | grep -v 127.0.0.1 | grep -v docker | grep -v 'br\-' | grep inet | grep -v inet6 | grep -v lo:0 | sed 's/\//\ /g' | awk '{print $2}')

function ::docker(){
  echo "Ready to install docker. Wait a moment ..."
  sudo yum update -y
  sudo yum install -y yum-utils
  sudo yum install -y device-mapper-persistent-data
  sudo yum install -y  lvm2 
  sudo yum install -y yum-utils device-mapper-persistent-data lvm2
  yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
  sudo yum install -y docker-ce 
  mkdir /etc/docker || true
  touch /etc/docker/daemon.json
  echo "{ \"registry-mirrors\":[\"https://u6gcz43x.mirror.aliyuncs.com\"] }" > /etc/docker/daemon.json
    
  systemctl daemon-reload
  systemctl start docker
  systemctl enable docker
}

function ::install_istio(){
  echo "Ready to install istio. Wait a moment ..."

  istioctl operator init --hub ${HUB} --tag ${ISTIO_TAG}
  
  local ISTIO_CONF=`cat <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: demo
  namespace: istio-system
spec:
  hub: ${HUB}
  tag: ${ISTIO_TAG}
  profile: demo
  meshConfig:
    accessLogFile: /dev/stdout
    enableTracing: true
    defaultConfig:
      proxyMetadata:
        ISTIO_META_DNS_CAPTURE: "true"
        ISTIO_META_DNS_AUTO_ALLOCATE: "true" 
      extraStatTags:
        - request_path
        - request_method 
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1
      tracer:
        zipkin:
          address: jaeger.service-mesh:9411
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
  local LAST_CLUSTER=`kind get clusters | grep cluster | tail -1`
  local CLUSTER_CTX="kind-"${LAST_CLUSTER}
   
  echo "${ISTIO_CONF}" | kubectl apply --context "${CLUSTER_CTX}" -f - > /dev/null
  ::kubectlwait ${CLUSTER_CTX} istio-system

  kubectl apply --context "${CLUSTER_CTX}" -f ${CACHE_DIR}/prometheus.yaml --validate=false  > /dev/null
  kubectl apply --context "${CLUSTER_CTX}" -f ${CACHE_DIR}/kiali.yaml --validate=false > /dev/null
}

function ::install_solarmesh(){
  echo "Ready to install solarmesh. Wait a moment ..."
  
  local LAST_CLUSTER=`kind get clusters | grep cluster | tail -1`
  local CLUSTER_CTX="kind-"${LAST_CLUSTER}
  
  kubectl config use-context ${CLUSTER_CTX}
  solarctl install solar-mesh

  ::kubectlwait ${CLUSTER_CTX} solar-operator
  ::kubectlwait ${CLUSTER_CTX} service-mesh
   
  kubectl create secret generic admin --from-literal=username=admin --from-literal=password=admin -n service-mesh
  kubectl label secret admin app=solar-controller -n service-mesh  

  export ISTIOD_REMOTE_EP=$(kubectl get nodes|awk '{print $1}' |awk 'NR==2'|xargs -n 1 kubectl get nodes  -o jsonpath='{.status.addresses[0].address}')
  solarctl operator init --external-ip $ISTIOD_REMOTE_EP --eastwest-external-ip $ISTIOD_REMOTE_EP
  
  ::kubectlwait ${CLUSTER_CTX} solar-operator
  kubectl create ns service-mesh || true

  local SOLAR_CONF=`cat <<EOF
apiVersion: install.solar.io/v1alpha1
kind: SolarOperator
metadata:
  name: cluster1
  namespace: solar-operator
spec:
  istioVersion: "1.11"  ## 对应您Istio的安装版本
  profile: default
EOF
`
  echo "${SOLAR_CONF}" | kubectl apply --wait -f -
  
  echo  "Ready to register cluster. Wait a moment ..."
  solarctl register --name cluster1
  
  solarctl install grafana --name cluster1 --extra-metric=true --istio-version "1.11"
  solarctl install jaeger --name cluster1  
  
  echo "Ready to install bookinfo. Wait a moment ..."
  kubectl create ns bookinfo || true
  kubectl label ns bookinfo "istio.io/rev=default" --overwrite
  solarctl install bookinfo -n bookinfo >/dev/null
  
  local WASM_CONF=`cat <<EOF
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

  kubectl patch svc solar-controller -n service-mesh -p '{
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


  kubectl rollout restart deploy solar-controller -n service-mesh

  echo "${WASM_CONF}" | kubectl apply -f - >/dev/null 
     
  kubectl create ns es | true
  kubectl apply -f ${CACHE_DIR}/es.yaml -n es  --validate=false   

  kubectl apply -f ${CACHE_DIR}/metrics-server.yaml --validate=false > /dev/null  

  kubectl patch svc -n bookinfo productpage -p '{
   "spec": {
        "ports": [{
            "name": "http",
            "nodePort": 30205,
            "port": 9080,
            "protocol": "TCP",
            "targetPort": 9080}],
        "type": "NodePort"
    }
  }'

  kubectl patch svc -n istio-system prometheus -p '{
   "spec": {
        "ports": [{
            "name": "http",
            "nodePort": 30203,
            "port": 9090,
            "protocol": "TCP",
            "targetPort": 9090}],
        "type": "NodePort"
    }
  }' 

  local GRPC_LOGGING_CONF=`cat <<EOF
apiVersion: v1
data:
  application.yaml: |-
    ds_driver: Elastic
    url: http://elasticsearch.es:9200
kind: ConfigMap
metadata:
  labels:
    app: grpc-logging
  name: grpc-logging
  namespace: service-mesh
EOF
`  
echo "${GRPC_LOGGING_CONF}" | kubectl apply -f - >/dev/null

kubectl rollout restart deploy networking-agent -n service-mesh 
 
echo "---------- ---------- ---------- ---------- ---------- ----------"
 
echo "solarmesh登录地址: http://${IP}:30880"

echo "---------- ---------- ---------- ---------- ---------- ----------"

echo "bookinfo访问地址: http://${IP}:30205/productpage"
 
}

function ::install_nginx(){
  sudo yum install -y epel-release
  sudo yum install -y nginx
  systemctl enable nginx
  systemctl start nginx 
}

function ::solarmesh(){
  ::install_k8s
  ::install_istio 
  ::install_solarmesh
}

function ::install_k8s(){
 echo "Ready to install k8s. Wait a moment ..." 
 sudo systemctl restart docker  
 local CLUSTER_CONF=`cat <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.cloud2go.cn"]
    endpoint = ["http://harbor.cloud2go.cn"]
networking:
  apiServerAddress: "${IP}"
  apiServerPort: 6443
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        authorization-mode: "AlwaysAllow"
  extraPortMappings:
  - containerPort: 80
    hostPort: 20080
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 7575
    hostPort: 7575
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 9090
    hostPort: 9090
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 20001
    hostPort: 20001
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 15443
    hostPort: 15443
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30080
    hostPort: 30080
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30066
    hostPort: 30066
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 35672
    hostPort: 35672
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30880
    hostPort: 30880
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30201
    hostPort: 30201
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30202
    hostPort: 30202
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30203
    hostPort: 30203
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30204
    hostPort: 30204
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30205
    hostPort: 30205
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
EOF
`
  
  local CLUSTER_ID=`::find_next_cluster_id` 
  local CLUSTER_NAME=`::name $CLUSTER_ID`   
  local CLUSTER_CTX=`::context $CLUSTER_ID`
  
  echo "${CLUSTER_CONF}" | kind create cluster --name ${CLUSTER_NAME} --image registry.cn-shenzhen.aliyuncs.com/solarmesh/node:v1.20.7 --config - > /dev/null 
  ::kubectlwait ${CLUSTER_CTX} kube-system  
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

function ::wait() {
  local out=$($@)
  while [ "$out" == "" ]; do
    sleep 1
    out=$($@)
  done
}

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

function ::prepare() {

  if ! command -v docker > /dev/null; then
    ::docker
  fi
  
  if ! command -v kind > /dev/null; then
    echo "Ready to install kind. Wait a moment ..." 
    ::download . https://ghproxy.com/https://github.com/kubernetes-sigs/kind/releases/download/v0.17.0/kind-linux-amd64 
    sudo mv ${CACHE_DIR}/kind-linux-amd64 /usr/local/bin/kind
  fi

  if ! command -v kubectl > /dev/null; then
    echo "Ready to install kubectl. Wait a moment ..."
    ::download . https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl 
    sudo mv ${CACHE_DIR}/kubectl /usr/local/bin/kubectl
  fi

  if ! command -v istioctl > /dev/null; then
    echo "Ready to install istioctl. Wait a moment ..."
    ::download . http://release.solarmesh.cn/istio/istioctl/istioctl-1.11.5.tar.gz
    tar zxvf ${CACHE_DIR}/istioctl-1.11.5.tar.gz > /dev/null
    mv istioctl /usr/local/bin/istioctl
  fi

  if ! command -v solarctl > /dev/null; then
    echo "Ready to install solarctl. Wait a moment ..."
    ::download . http://release.solarmesh.cn/solar/v1.11/solar-${SOLAR_TAG}-linux-amd64.tar.gz
    tar -xvf ${CACHE_DIR}/solar-${SOLAR_TAG}-linux-amd64.tar.gz -C ${CACHE_DIR}/  > /dev/null
    mv ${CACHE_DIR}/solar/bin/solarctl /usr/local/bin/solarctl
  fi
 
  if ! command -v nginx > /dev/null; then
    echo "Ready to install nginx. Wait a moment ..."
    ::install_nginx
  fi
  
  ::download . http://release.solarmesh.cn/istio/addon/prometheus.yaml
  ::download . http://release.solarmesh.cn/istio/addon/es.yaml
  ::download . http://release.solarmesh.cn/istio/addon/kiali.yaml 
  ::download . http://release.solarmesh.cn/istio/addon/metrics-server.yaml 

  systemctl stop firewalld || true
}

function ::usage() {
  echo "This utility is used to build Istio mesh clusters on KinD. Both Linux Docker and Docker Desktop for MacOS are supported."
  echo ""
  echo "Usage $0 [arguments]"
  echo "Arguments:"
  echo "  solarmesh: Install solarmesh"
  echo "  k8s: Build a KindD cluster with Kubernetes installed"
}


function ::main() {
  case $1 in
      "k8s")
        ::prepare
        ::install_k8s
        ;; 
      "solarmesh")
        ::prepare
        ::solarmesh 
        ;;
      *)
        ::usage
        ;;
  esac
}

set -e

::main $@

set +e
