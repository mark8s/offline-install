
CACHE_DIR=".cache"
CLUSTER_NAME_PREFIX="cluster"
HUB="registry.cn-shenzhen.aliyuncs.com/solarmesh"
ISTIO_TAG="1.11.5"
SOLAR_TAG="v1.11.4"
IP=$(ip a | grep -v kube | grep -v 127.0.0.1 | grep -v docker | grep -v 'br\-' | grep inet | grep -v inet6 | grep -v lo:0 | sed 's/\//\ /g' | awk '{print $2}')


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
  
  local CLUSTER_CTX=`kubectl config current-context`
  echo "cluster_ctx: ${CLUSTER_CTX}"
 
  echo "${ISTIO_CONF}" | kubectl apply -f - > /dev/null
  ::kubectlwait ${CLUSTER_CTX} istio-system

  kubectl apply -f ${CACHE_DIR}/prometheus.yaml --validate=false  > /dev/null
  kubectl apply -f ${CACHE_DIR}/kiali.yaml --validate=false > /dev/null
}

function ::install_solarmesh(){
  echo "Ready to install solarmesh. Wait a moment ..."
  
  local CLUSTER_CTX=`kubectl config current-context` 
   
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


function ::solarmesh(){
  ::install_istio   
  ::install_solarmesh 
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
}


function ::main() {
  case $1 in
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
