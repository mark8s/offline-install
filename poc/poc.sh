#!/bin/bash

CACHE_DIR=".cache"

function ::docker(){


}


function ::k8s(){


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
  command -v docker >/dev/null || (echo "Install docker first." && exit 1)
  command -v kind >/dev/null || (echo "Install kind from https://kind.sigs.k8s.io/docs/user/quick-start/ ." && exit 1)
  command -v kubectl >/dev/null || (echo "Install kubectl from https://github.com/kubernetes/kubernetes/releases ." && exit 1)
  command -v istioctl >/dev/null || (echo "Install istioctl from https://gcsweb.istio.io/gcs/istio-release/releases/1.15.0/" && exit 1)
  command -v solarctl >/dev/null || (echo "Install istioctl from http://release.solarmesh.cn/solar/v1.11/" && exit 1)

  ::download . https://ghproxy.com/http://release.solarmesh.cn/istio/istioctl/istioctl-1.11.5.tar.gz
  ::download . https://ghproxy.com/http://release.solarmesh.cn/istio/addon/prometheus.yaml
  ::download . https://ghproxy.com/http://release.solarmesh.cn/istio/addon/es.yaml
  ::download . https://ghproxy.com/http://release.solarmesh.cn/istio/addon/kiali.yaml

  systemctl stop firewalld || true
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
      "k8s")
        ::prepare
        ::k8s
        ;; 
      *)
        ::usage
        ;;
  esac
}

set -e

::main $@

set +e
