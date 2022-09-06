#!/bin/bash
set -e

func(){
    echo "Usage:"
    echo "$0"
    echo "Description:"
    echo "-c     Set ClusterName (default "cluster1")"
    echo "-k     Set KubeConfig path (default /home/ctg/.kube/config)"
    exit -1
}

while getopts 'c:k:d' OPT; do
    case $OPT in
        c) CLUSTER="$OPTARG";;
        k) KUBECONFIG="$OPTARG";;
        d) DELETE=true;;
        h) func;; 
        ?) func;;
    esac
done

if [ ! $KUBECONFIG ]; then
   KUBECONFIG=/home/ctg/.kube/config
fi 

if [ ! $CLUSTER ]; then 
  CLUSTER=cluster1
fi 

echo "kubeconfig: "$KUBECONFIG


solarctl install solar-mesh

sleep 3

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ------ Installed master ---------- ---------- --------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

while true
do
  if [[ $(kubectl get po -n service-mesh -l app=solar-controller | wc -l) > 0 ]];then
     echo "---------- ---------- solar-controller get ready! ---------- ---------- "
     break
  fi
done

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

kubectl create secret generic admin --from-literal=username=admin --from-literal=password=admin -n service-mesh

kubectl label secret admin app=solar-controller -n service-mesh

solarctl register --kube-config $KUBECONFIG --name $CLUSTER

echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- -- Registried business --------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"
echo "---------- ---------- ---------- ---------- ---------- ----------"

kubectl apply -f - <<EOF
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
            - "service-mesh"
            - "ibm.*"
            - "kial-operator"
            - "istio-system"
            - "kong"
      certificate:
        home_dir: /etc
      wasmPlugins:
      - name: dataclean
        nickname: 数据清洗
        description: 清洗掉所有手机号的数据
        uri: http://release.solarmesh.cn/wasm/data-cleaning.wasm
        type: 0
      - name: notice
        nickname: 通知公告
        description: 版本更新公告
        uri: http://release.solarmesh.cn/wasm/notice.wasm
        type: 0  
EOF

kubectl rollout restart deploy solar-controller -n service-mesh

