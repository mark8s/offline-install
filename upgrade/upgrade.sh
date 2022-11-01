#!/bin/bash

CACHE_DIR=".cache"

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

function ::data_plane(){
  read -r -p "You are ready to update istio's data plane. Are You Sure? [y/n] " input
  case $input in
    [yY][eE][sS]|[yY])
        echo "Yes."
        ;;
    [nN][oO]|[nN])
        exit 0
        ;;
    *)
        echo "Invalid input..."
        exit 1
        ;;
  esac

  # like bookinfo
  local NS=$1
  
  if [ ! -n "$1" ] ;then  
     echo "You need to specify namespace, this is required." 
     echo "You can use like this: $0 data-plane bookinfo"
     exit 1
  fi

  kubectl rollout restart deploy -n ${NS}
  kubectl rollout restart sts -n ${NS}
  kubectl rollout restart ds -n ${NS}
}

function ::control_plane() {
  # like 1.15.2
  local REVISION=$1
  
  if [ ! -n "$1" ] ;then  
     echo "You need to specify revision, this is required." 
     echo "You can use like this: $0 control-plane 1.15.2"
     exit 1
  fi
  
  echo "Getting Istioctl"
  ::download . https://ghproxy.com/https://github.com/istio/istio/releases/download/${REVISION}/istioctl-${REVISION}-linux-amd64.tar.gz  
  tar zxvf ${CACHE_DIR}/istioctl-${REVISION}-linux-amd64.tar.gz > /dev/null
  
  kubectl get istiooperator -n istio-system installed-state -oyaml > ${CACHE_DIR}/io.yaml 
  sed -i '/resourceVersion/d' ${CACHE_DIR}/io.yaml  
  sed -i '/uid/d' ${CACHE_DIR}/io.yaml  
  sed -i '/creationTimestamp/d' ${CACHE_DIR}/io.yaml
  sed -i '/generation/d' ${CACHE_DIR}/io.yaml

  echo "Ready to start upgrading istio control-plane. Your cluster's istiod and gateway will be updated."  
 
  ./istioctl install --set revision=${REVISION//./-} --set tag=${REVISION} -f ${CACHE_DIR}/io.yaml

  echo "Prepare to uninstall the old istio control plane"
  ./istioctl uninstall -f ${CACHE_DIR}/io.yaml
}

function ::prepare() {
  command -v kubectl >/dev/null || (echo "Install kubectl from https://github.com/kubernetes/kubernetes/releases ." && exit 1)
  command -v istioctl >/dev/null || (echo "Install istioctl from https://gcsweb.istio.io/gcs/istio-release/releases/..." && exit 1)
  command -v solarctl >/dev/null || (echo "Install istioctl from http://release.solarmesh.cn/solar/v1.11/" && exit 1)
}

function ::usage(){
  echo "This is a small tool to help you update istio, it can specify istio revision update and upgrade your istio cluster."
  echo ""
  echo "Usage $0 [arguments]"
  echo "Arguments:"
  echo "  control-plane: Upgrade the istio control plane. For example: $0 control-plane 1.15.2 , this means that the istio version of the cluster will be upgraded to version 1.15.2."
  echo "  date-plane: Upgrade the istio data plane. For example: $0 data-plane bookinfo ,this means that the sidecar under the bookinfo namespace will be updated."
}

function ::main() {
  case $1 in
      "control-plane")
        ::prepare
        ::control_plane $2 
        ;;
      "data-plane")
        ::prepare
        ::data_plane $2
        ;;
      *)
        ::usage
        ;;
  esac
}

set -e

::main $@

set +e
