#!/bin/bash

set -e

func(){
    echo "Usage:"
    echo "$0"
    echo "Description:"
    echo "-h     specified hub, -h registry.cn-shenzhen.aliyuncs.com/solarmesh"
    echo "-t     specified IstioTag, -t 1.11.5 (default 1.11.5)"
    echo "-v     specified solarmesh version, -v v1.11.1 (default v1.11.1)"
    exit -1
}

while getopts 'h:t:v:' OPT; do
    case $OPT in
        h) HUB="$OPTARG";;
        t) ISTIO_TAG="$OPTARG";;
        v) VERSION="$OPTARG";;
        h) func;; 
        ?) func;;
    esac
done

if [ ! $ISTIO_TAG ]; then 
  ISTIO_TAG=1.11.5
fi 

if [ ! $HUB ]; then
  HUB=registry.cn-shenzhen.aliyuncs.com/solarmesh
fi

if [ ! $VERSION ]; then
  VERSION=v1.11.1
fi 

# istio
docker pull docker.io/istio/pilot:$ISTIO_TAG
docker pull docker.io/istio/proxyv2:$ISTIO_TAG
docker pull docker.io/istio/operator:$ISTIO_TAG

# addon
docker pull $HUB/grafana:7.5.5
docker pull $HUB/jaeger:1.21
docker pull $HUB/prometheus:v2.26.0
docker pull $HUB/alertmanager:v0.18.0
docker pull $HUB/configmap-reload:v0.0.1
docker pull $HUB/prometheus-operator:v0.38.1
docker pull $HUB/prometheus:v2.17.2

# solarmesh
BOOK_HUB=registry.cn-shenzhen.aliyuncs.com/solar-mesh
docker pull $BOOK_HUB/examples-bookinfo-details-v1:1.15.0
docker pull $BOOK_HUB/examples-bookinfo-productpage-v1:1.15.0
docker pull $BOOK_HUB/examples-bookinfo-ratings-v1:1.15.0
docker pull $BOOK_HUB/examples-bookinfo-reviews-v1:1.15.0
docker pull $BOOK_HUB/examples-bookinfo-reviews-v2:1.15.0
docker pull $BOOK_HUB/examples-bookinfo-reviews-v3:1.15.0

## save image
docker save \
docker.io/istio/pilot:$ISTIO_TAG \
docker.io/istio/proxyv2:$ISTIO_TAG \
docker.io/istio/operator:$ISTIO_TAG \
$HUB/grafana:7.5.5 \
$HUB/jaeger:1.21 \
$HUB/prometheus:v2.26.0 \
$HUB/alertmanager:v0.18.0 \
$HUB/configmap-reload:v0.0.1 \
$HUB/prometheus-operator:v0.38.1 \
$HUB/prometheus:v2.17.2 \
> solarmesh-$VERSION-image-offline.tar.gz

docker save \
$BOOK_HUB/examples-bookinfo-details-v1:1.15.0 \
$BOOK_HUB/examples-bookinfo-productpage-v1:1.15.0 \
$BOOK_HUB/examples-bookinfo-ratings-v1:1.15.0 \
$BOOK_HUB/examples-bookinfo-reviews-v1:1.15.0 \
$BOOK_HUB/examples-bookinfo-reviews-v2:1.15.0 \
$BOOK_HUB/examples-bookinfo-reviews-v3:1.15.0 \
> bookinfo-1.15.0-image-offline.tar.gz
