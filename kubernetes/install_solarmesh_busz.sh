#!/bin/bash

set -e

func(){
    echo "Usage:"
    echo "$0"
    echo "Description:"
    echo "-c     Set ClusterName (default "cluster1")"
    echo "-t     Set SolarMesh Release Tag  (default "v1.11.1")" 
    echo "-m     Set MeshId (default "mesh01")"
    echo "-n     Set Network (default "network1")"
    echo "-p     Set Profile (default "default")"
    echo "-i     Set SolarMesh Hub (default "registry.cn-shenzhen.aliyuncs.com/solarmesh")"
    echo "-v     Set Install Istio version, support 1.9、1.10、1.11、1.12、1.13、1.14 (default 1.11)"
    echo "-d     CleanUp solarmesh、istio"
    echo "-r     CleanUp bookinfo, support -b detele bookinfo"
    echo "-b     Set BookInfo install namespace (default default)"
    echo "-k     Set KubeConfig path (default /home/ctg/.kube/config)"
    echo "-w     Patch istio-ingressgateway externalIPs (default 10.10.13.87)"
    exit -1
}

DELETE=false

while getopts 'c:t:m:n:p:i:v:b:k:w:r:d' OPT; do
    case $OPT in
        c) CLUSTER="$OPTARG";;
        t) TAG="$OPTARG";;
        m) MESHID="$OPTARG";;
        n) NETWORK="$OPTARG";;
        p) PROFILE="$OPTARG";;
        i) IMAGE="$OPTARG";;
        v) VERSION="$OPTARG";;       
        b) NS="$OPTARG";;
        k) KUBECONFIG="$OPTARG";;
        w) PATCH="$OPTARG";;
        r) REMOVE="$OPTARG";; 
        d) DELETE=true;;
        h) func;; 
        ?) func;;
    esac
done

if [ "$DELETE" == true ]; then
   solarctl uninstall istio   

   solarctl uninstall cluster $CLUSTER
   
   solarctl uninstall  solarmesh

   exit 0
fi

if [ ! $CLUSTER ]; then 
  CLUSTER=cluster1
fi 

if [ ! $TAG ]; then
   TAG=v1.11.1
fi

if [ ! $MESHID ]; then
   MESHID=mesh01
fi

if [ ! $NETWORK ]; then
   NETWORK=network1
fi

if [ ! $PROFILE ]; then
   PROFILE=default
fi

if [ ! $IMAGE ]; then
   IMAGE=registry.cn-shenzhen.aliyuncs.com/solarmesh 
fi

if [ ! $VERSION ]; then
   VERSION=1.11
fi

if [ ! $KUBECONFIG ]; then
   KUBECONFIG=/home/ctg/.kube/config
fi 

if [ ! $NS ]; then
   NS=default
fi

if [ $VERSION = "1.9" ]; then
  ISTIO_VERSION=1.9.8 
elif [ $VERSION = "1.10" ]; then
  ISTIO_VERSION=1.10.4
elif [ $VERSION = "1.11" ]; then
  ISTIO_VERSION=1.11.5
elif [ $VERSION = "1.12" ]; then
  ISTIO_VERSION=1.12.6
elif [ $VERSION = "1.13" ]; then 
  ISTIO_VERSION=1.13.3
elif [ $VERSION = "1.14" ]; then
  ISTIO_VERSION=1.14.1
fi

  ## delete bookinfo
if [ $REMOVE = "b" ]; then
     kubectl delete deploy details-v1 productpage-v1 ratings-v1 reviews-v1 reviews-v2  reviews-v3  -n $NS   
     kubectl delete svc details productpage ratings reviews  -n $NS  
   exit 0
fi
   

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- - Let's install istio operator ......................."
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

istioctl operator init --hub $IMAGE --tag $ISTIO_VERSION

sleep 5

echo "---------- - istio operator inited ......................."

kubectl apply -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: example-istiocontrolplane
spec:
  hub: $IMAGE
  tag: $ISTIO_VERSION
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
      meshID: $MESHID
      multiCluster:
        clusterName: $CLUSTER
      network: $NETWORK
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

sleep 20

export ISTIOD_REMOTE_EP=$(kubectl get nodes|awk '{print $1}' |awk 'NR==2'|xargs -n 1 kubectl get nodes  -o jsonpath='{.status.addresses[0].address}')

solarctl operator init --external-ip $ISTIOD_REMOTE_EP --eastwest-external-ip $ISTIOD_REMOTE_EP --tag $TAG

sleep 5

kubectl apply -f - <<EOF
apiVersion: install.solar.io/v1alpha1
kind: SolarOperator
metadata:
  namespace: solar-operator
  name: abc  # 记住这里的集群名称，这里需要与 istioOperator 中 clusterName 对应
spec:
  istioVersion: "$VERSION"
  profile: default
EOF

sleep 30

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- --- Installed business ---------- --------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

kubectl create ns $NS || error=true

if [ $? < 0 ];then
  echo "namespace Already exists."
fi

solarctl install bookinfo -n $NS

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- -- Installed bookinfo ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

while true
do
  if [[ $(kubectl get po -n $NS -l app=productpage | wc -l) > 1 ]];then
     echo "---------- ---------- productpage get ready! ---------- ---------- "
     break
  fi
done

echo "auto inject default namespace"

kubectl label namespace default istio-injection=enabled --overwrite

kubectl patch svc -n $NS productpage -p '{
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

kubectl patch svc -n service-mesh networking-agent -p '{
   "spec": {
        "ports": [{
         "name": "grpc-7575",
          "nodePort": "30009",
          "port": 7575,
          "protocol": "TCP:,
          "targetPort": 7575,  
        }],
        "type": "NodePort"
    }
}'


kubectl rollout restart deploy

kubectl patch svc -n istio-system istio-ingressgateway -p '{"spec":{"externalIPs":["10.10.13.117"]}}'

#solarctl install grafana --name $CLUSTER

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- -- Installed grafana ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

sleep 1

#solarctl install jaeger --name $CLUSTER

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- -- Installed jaeger ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"


echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

echo "solarmesh登录地址: http://hostIp:30880"

echo "---------- ---------- ---------- ---------- ---------- ----------"

echo "bookinfo访问地址: http://hostIp:30201/productpage"

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

echo "Install demo success! Have a nice day!"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
