#!/bin/bash

set -e

func(){
    echo "Usage:"
    echo "$0"
    echo "Description:"
    echo "-c     set cluster name, -c cluster-name "
    echo "-s     set apiServerAddress, -s 10.10.13.xxx "
    echo "-d     delete cluster, -d"
    exit -1
}

DELETE=false

while getopts 'c:s:d' OPT; do
    case $OPT in
        c) CLUSTER="$OPTARG";;
        s) SERVER="$OPTARG";;
        d) DELETE=true;;
        h) func;; 
        ?) func;;
    esac
done

if [ ! $CLUSTER ]; then 
  CLUSTER=cluster
fi 

if [ "$DELETE" == true ]; then
   kind delete cluster --name $CLUSTER
   exit 0
fi


if [ ! $SERVER ]; then
  echo "You need set apiServerAddress! eg: -s 10.10.13.xxx"
  exit -1
fi 

cat <<EOF | kind create cluster --name $CLUSTER --image registry.cn-shenzhen.aliyuncs.com/solarmesh/node:v1.20.7  --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.cloud2go.cn"]
    endpoint = ["http://harbor.cloud2go.cn"]
networking:
  apiServerAddress: $SERVER
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
  - containerPort: 30009
    hostPort: 7575
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 9090
    hostPort: 9090
    listenAddress: "0.0.0.0" # Optional, defaults to "0.0.0.0"
    protocol: tcp # Optional, defaults to tcp
  - containerPort: 30008
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
