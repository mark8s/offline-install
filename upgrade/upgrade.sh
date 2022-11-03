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

function ::clean(){
  rm -rf ${CACHE_DIR}/istioctl-*
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
  local REVISION=$2

  if [ ! -n "$1" ] ;then  
     echo "You need to specify namespace, this is required." 
     echo "You can use like this: $0 data-plane bookinfo $REVISION"
     exit 1
  fi

  if [ ! -n "$2" ] ;then  
     echo "You need to specify revision, this is required." 
     echo "You can use like this: $0 data-plane ${NAMESPACE} 1.15.2"
     exit 1
  fi
 
  kubectl label namespace ${NS}  istio-injection- istio.io/rev=${REVISION//./-}
 
  kubectl rollout restart deploy -n ${NS}
  kubectl rollout restart sts -n ${NS}
  kubectl rollout restart ds -n ${NS}
}

function ::remove(){
  local REVISION=$1 
 
  read -r -p "You are ready to remove istio's ${REVISION} control-plane. Are You Sure? [y/n] " input
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

  if [ ! -n "$1" ] ;then
    ./istioctl uninstall -f ${CACHE_DIR}/io-old-*.yaml
    kubectl delete -f ${CACHE_DIR}/io-old-*.yaml  
  else
    ./istioctl uninstall -f ${CACHE_DIR}/io-old-*-${REVISION//./-}.yaml
    kubectl delete -f ${CACHE_DIR}/io-old-*-${REVISION//./-}.yaml 
  fi 

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
  
  ::parse kubectl get istiooperator -o=custom-columns=:metadata.name -A  --no-headers 
  
  ::clean
}

function ::parse() {
  local out=$($@)
 
  for i in ${out} 
  do
    local ioName=$i 
    kubectl get istiooperator ${ioName} -n istio-system -oyaml > ${CACHE_DIR}/io-old-${ioName}.yaml  
    cp ${CACHE_DIR}/io-old-${ioName}.yaml ${CACHE_DIR}/io-new-${ioName}.yaml  
    sed -i '/resourceVersion/d' ${CACHE_DIR}/io-new-${ioName}.yaml  
    sed -i '/uid/d' ${CACHE_DIR}/io-new-${ioName}.yaml
    sed -i '/creationTimestamp/d' ${CACHE_DIR}/io-new-${ioName}.yaml
    sed -i '/generation/d' ${CACHE_DIR}/io-new-${ioName}.yaml
    local istiooperatorname="name: "${ioName}    
    echo ${istiooperatorname}
    sed -i "/$istiooperatorname/d" ${CACHE_DIR}/io-new-${ioName}.yaml
     
    # ./istioctl install --set revision=${REVISION//./-} --set tag=${REVISION} -f ${CACHE_DIR}/io-new-${ioName}.yaml
    ./istioctl install --set revision=${REVISION//./-} --set tag=${REVISION} --set components.ingressGateways[name:istio-ingressgateway].enabled=false -f ${CACHE_DIR}/io-new-${ioName}.yaml
  done
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
  echo "  control-plane: Upgrade the istio control plane. For example: $0 control-plane 1.15.2 ,this means that the istio version of the cluster will be upgraded to version 1.15.2."
  echo "  date-plane: Upgrade the istio data plane. For example:  $0 data-plane bookinfo 1.15.2 ,this means that the sidecar under the bookinfo namespace will be updated to the v1.15.2 version of the sidecar."
  echo "  remove: Remove the old control plane. When your data plane is completely updated, you may need to uninstall the old istio control plane, then you can use: For example:
            1) $0 remove ,this means you will uninstall the earliest version of the control plane. 
            2) $1 remove 1.15.2 ,this means you will uninstall version 1.15.2 of the control plane. "
}

function ::main() {
  case $1 in
      "control-plane")
        ::prepare
        ::control_plane $2 
        ;;
      "data-plane")
        ::prepare
        ::data_plane $2 $3
        ;;
      "remove")
        ::prepare
        ::remove $2
        ;;
      *)
        ::usage
        ;;
  esac
}

set -e

::main $@

set +e
